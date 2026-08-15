#-*- perl -*-
#
# @ISA has to name real packages.
#
# FML::Command::User::signoff carried
#
#	@ISA = qw(FML::Command::User::unsubscribe use);
#
# for years.  "use" is not a package; it is a word that fell into the
# list.  Perl does not complain when @ISA is assigned, only when method
# resolution walks past the working parent and reaches the junk, so the
# defect sat there invisible for as long as unsubscribe answered
# everything asked of it.
#
# That is the kind of thing that is only found by looking at every
# module rather than the one that failed, so look at every module.  The
# source is read rather than the tree loaded: loading 292 modules pulls
# in DBI, LDAP, GD and CGI, and a missing optional module would turn
# this into a test of what happens to be installed.
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

my $LIB = 'fml/lib';

plan skip_all => "no $LIB here" unless -d $LIB;


# Descriptions: every *.pm under $LIB, as a sorted list of paths.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub all_modules
{
    my @found = ();

    my $walk;
    $walk = sub {
	my ($dir) = @_;
	opendir(my $dh, $dir) or die "cannot read $dir: $!";
	my @e = sort grep { !/^\.\.?$/ } readdir($dh);
	closedir($dh);

	for my $e (@e) {
	    my $path = "$dir/$e";
	    if (-d $path)          { $walk->($path) }
	    elsif ($path =~ /\.pm$/) { push @found, $path }
	}
    };
    $walk->($LIB);

    return \@found;
}


# Descriptions: the package names $path declares as its parents, however
#               they are written: an @ISA assignment, a push onto @ISA,
#               "use base" or "use parent".
#    Arguments: STR($path)
# Side Effects: none
# Return Value: ARRAY_REF
sub parents_of
{
    my ($path) = @_;

    open(my $fh, '<', $path) or die "cannot read $path: $!";
    local $/ = undef;
    my $src = <$fh>;
    close($fh);

    # Drop POD before comments.  fml8 scatters POD through the body
    # rather than collecting it at the end, and a SYNOPSIS shows the
    # caller's code -- FML::Command::Syntax documents itself with
    # "push(@ISA, qw(FML::Command::Syntax))", which is what the module
    # using it writes, not what it does to itself.  Read as code that is
    # a self-referential @ISA that is not there.
    my @code = ();
    my $in_pod = 0;
    for my $line (split(/\n/, $src, -1)) {
	if    ($line =~ /^=cut\b/)      { $in_pod = 0; next }
	elsif ($line =~ /^=[a-zA-Z]\w*/) { $in_pod = 1; next }
	next if $in_pod;
	next if $line =~ /^\s*#/;
	push @code, $line;
    }
    $src = join("\n", @code);

    my @p = ();

    while ($src =~ /\@ISA\s*=\s*qw\(([^)]*)\)/gs) {
	push @p, split(' ', $1);
    }
    while ($src =~ /push\s*\(?\s*\@ISA\s*,\s*qw\(([^)]*)\)/gs) {
	push @p, split(' ', $1);
    }
    while ($src =~ /^\s*use\s+(?:base|parent)\s+(?:-norequire\s*,\s*)?qw\(([^)]*)\)/gms) {
	push @p, split(' ', $1);
    }

    return \@p;
}


my $MODULES = all_modules();


# ---------------------------------------------------------------------
# 1. there is something to look at
# ---------------------------------------------------------------------
subtest 'the tree is where it is expected to be' => sub {
    cmp_ok(scalar(@$MODULES), '>', 200,
	   sprintf("found %d modules under %s", scalar(@$MODULES), $LIB));

    my ($signoff) = grep { m{FML/Command/User/signoff\.pm$} } @$MODULES;
    ok($signoff, 'the module the defect was found in is among them');
};


# ---------------------------------------------------------------------
# 2. every element of every @ISA is shaped like a package name
#
# This is what catches "use": a perl keyword is a legal bareword inside
# qw(), so nothing below the syntax level notices.
# ---------------------------------------------------------------------
subtest 'no @ISA element is a stray word' => sub {
    # Words that are perl syntax rather than packages.  A parent named
    # any of these is a mistake however it got there.
    my %keyword = map { $_ => 1 }
	qw(use no require our my local sub package if else elsif unless
	   for foreach while until do return last next redo and or not
	   qw q qq eval BEGIN END);

    my $checked = 0;

    for my $path (@$MODULES) {
	my $parents = parents_of($path);
	next unless @$parents;

	for my $p (@$parents) {
	    $checked++;

	    ok(!$keyword{ $p }, "$path: parent '$p' is not a perl keyword");
	    like($p, qr/\A[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*\z/,
		 "$path: parent '$p' is shaped like a package name");
	}
    }

    cmp_ok($checked, '>', 50, "checked $checked parent declarations");
};


# ---------------------------------------------------------------------
# 3. a parent must actually exist somewhere
#
# A parent of ours has to be in the tree.  A parent from elsewhere --
# IO::File from the core, Mail::Header from the bundled MailTools -- has
# to be findable on @INC, which is the same requirement expressed
# against a different directory.  Naming one that is nowhere is the
# failure being looked for either way.
# ---------------------------------------------------------------------
subtest 'every declared parent can be found' => sub {
    my $checked = 0;

    for my $path (@$MODULES) {
	for my $p (@{ parents_of($path) }) {
	    (my $file = $p) =~ s{::}{/}g;
	    $file .= '.pm';
	    $checked++;

	    my $found = (-f "$LIB/$file") ? "$LIB/$file" : undef;
	    unless ($found) {
		for my $dir (@INC) {
		    next if ref $dir;
		    if (-f "$dir/$file") { $found = "$dir/$file"; last }
		}
	    }

	    ok($found, "$path: parent $p is on \@INC");
	}
    }

    cmp_ok($checked, '>', 20, "checked $checked parent declarations");
};


# ---------------------------------------------------------------------
# 4. nothing inherits from itself
#
# A self-referential @ISA is an infinite loop in method resolution
# rather than an error message.
# ---------------------------------------------------------------------
subtest 'no module is its own parent' => sub {
    for my $path (@$MODULES) {
	(my $pkg = $path) =~ s{^\Q$LIB\E/}{};
	$pkg =~ s{/}{::}g;
	$pkg =~ s{\.pm$}{};

	my @self = grep { $_ eq $pkg } @{ parents_of($path) };
	is(scalar(@self), 0, "$pkg does not inherit from itself");
    }
};


# ---------------------------------------------------------------------
# 5. the one that was wrong, specifically
#
# signoff forwards to unsubscribe and has almost no body of its own, so
# every method it answers comes through @ISA.  Load it and ask.
# ---------------------------------------------------------------------
subtest 'signoff really does inherit from unsubscribe' => sub {
    require FML::Command::User::signoff;

    no strict 'refs';
    my @isa = @{ "FML::Command::User::signoff::ISA" };

    is_deeply(\@isa, [ 'FML::Command::User::unsubscribe' ],
	      '@ISA names exactly the one parent');

    my $obj = FML::Command::User::signoff->new();
    ok(defined $obj, 'new() returns an object');
    isa_ok($obj, 'FML::Command::User::unsubscribe');

    # These come from the parent.  With junk in @ISA they resolve only
    # because the good parent happens to be listed first.
    for my $m (qw(process verify_syntax)) {
	can_ok($obj, $m) if FML::Command::User::unsubscribe->can($m);
    }
};

done_testing();
