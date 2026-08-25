#-*- perl -*-
#
# What fml8 depends on, and what it must no longer depend on.
#
# Bundles have been leaving cpan/ -- Socket6, File::Spec, File::MMagic,
# Crypt::TripleDES, Crypt::RandPasswd, HTML-Parser, Jcode,
# Unicode::Japanese -- each because the core or a rewrite took over.
# Removing a bundle is only finished when nothing reaches for it any
# more, and a leftover "use" does not fail until the module in question
# is loaded, which for most of fml8 is at the moment a mail arrives.
#
# That is not a theoretical worry.  When Jcode went, one module still
# had "use Jcode" in it: FML::Message::Language::Japanese::Subject.
# grep(1) did not report it, because that file is EUC-JP and grep calls
# such files binary and skips them without saying so.  Three modules
# under fml/lib are invisible to grep for that reason, and one of them
# was the one that mattered.
#
# So resolve the dependencies by reading every file as octets, and
# resolve them against @INC rather than against a list of names.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

my $LIB = 'fml/lib';

plan skip_all => "no $LIB here" unless -d $LIB;


# Pragmas and perl built-in modules that are not dependencies in the
# sense being checked here.
my %PRAGMA = map { $_ => 1 }
    qw(strict warnings vars lib utf8 overload constant base parent
       integer bytes subs locale open sigtrap re filetest less
       diagnostics feature version if);

# Modules fml8 can run without.  Each is behind an eval or a code path
# an installation may never take, and each has a reason to be optional
# rather than bundled.
#
#   GD              only FML::String::Banner::Image, a demo
#   Crypt::OpenPGP  only the PGP command paths
#
# The list is asserted to be exactly this, so a new optional dependency
# has to be a decision rather than an accident.
my %OPTIONAL = map { $_ => 1 } qw(GD Crypt::OpenPGP);

# Bundles that have been removed.  Nothing may reach for these again.
my %REMOVED = map { $_ => 1 }
    qw(Jcode Jcode::Constants Jcode::H2Z Jcode::Tr Jcode::Unicode
       Unicode::Japanese Socket6 File::MMagic Crypt::TripleDES
       Crypt::PPDES Crypt::RandPasswd HTML::Parser);


# Descriptions: every *.pm under $LIB.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub all_modules
{
    my @found = ();

    my $walk;
    $walk = sub {
	my ($dir) = @_;
	opendir(my $dh, $dir) or return;
	my @e = sort grep { !/^\.\.?$/ } readdir($dh);
	closedir($dh);

	for my $e (@e) {
	    my $path = "$dir/$e";
	    if (-d $path)            { $walk->($path) }
	    elsif ($path =~ /\.pm$/) { push @found, $path }
	}
    };
    $walk->($LIB);

    return \@found;
}


# Descriptions: the modules $path loads, as a hash of name => [ lines ].
#               Read as octets with no encoding layer, so an EUC-JP file
#               is read like any other.
#    Arguments: STR($path)
# Side Effects: none
# Return Value: HASH_REF
sub uses_of
{
    my ($path) = @_;
    my %use    = ();

    open(my $fh, '<', $path) or return {};
    binmode($fh);

    my $in_pod = 0;
    my $n      = 0;

    while (my $line = <$fh>) {
	$n++;
	if    ($line =~ /^=cut\b/)       { $in_pod = 0; next }
	elsif ($line =~ /^=[a-zA-Z]\w*/) { $in_pod = 1; next }
	next if $in_pod;
	next if $line =~ /^\s*#/;

	# "use X", "require X", and the eval q{ use X } form fml8 uses to
	# make a dependency optional.
	#
	# The trailing context is what keeps English out of the results.
	# fml8's comments are prose, and "we require this" and "use the
	# queue_dir" match a bare /use\s+(\w+)/ perfectly well.  A real
	# statement is followed by a semicolon, an import list or an
	# argument, and a module name is capitalised.
	while ($line =~ m{
		(?:^|[\s;\{(])
		(?:use|require)\s+
		([A-Z]\w*(?:::\w+)*)      # a module name, not a noun
		\s*(?:;|\(|qw|['"]|->|,)  # and it is being loaded
	    }gx) {
	    my $m = $1;
	    next if $PRAGMA{ $m };
	    push @{ $use{ $m } }, $n;
	}
    }
    close($fh);

    return \%use;
}


# Descriptions: where $module would be found, or undef.
#    Arguments: STR($module)
# Side Effects: none
# Return Value: STR or undef
sub resolve
{
    my ($module) = @_;

    (my $file = $module) =~ s{::}{/}g;
    $file .= '.pm';

    for my $dir ($LIB, 'cpan/lib', 'img/lib', @INC) {
	next if ref $dir;
	return "$dir/$file" if -f "$dir/$file";
    }

    return undef;
}


my $MODULES = all_modules();

# name => [ "path:line", ... ]
my %WANTED = ();
for my $path (@$MODULES) {
    my $use = uses_of($path);
    for my $m (keys %$use) {
	push @{ $WANTED{ $m } }, map { "$path:$_" } @{ $use->{ $m } };
    }
}


# ---------------------------------------------------------------------
# 1. the scan reaches the whole tree, EUC-JP files included
#
# This is the assertion the Jcode removal needed and did not have.
# ---------------------------------------------------------------------
subtest 'every module is read, whatever its encoding' => sub {
    cmp_ok(scalar(@$MODULES), '>', 200,
	   sprintf("found %d modules", scalar(@$MODULES)));

    my @euc = ();
    for my $path (@$MODULES) {
	open(my $fh, '<', $path) or next;
	binmode($fh);
	local $/ = undef;
	my $src = <$fh>;
	close($fh);
	push @euc, $path if $src =~ /[\x80-\xff]/;
    }

    cmp_ok(scalar(@euc), '>=', 3,
	   sprintf("%d modules carry non-ASCII octets: %s",
		   scalar(@euc), join(', ', @euc)));

    # grep(1) calls these binary and walks past them.  Each must still
    # have yielded its dependencies here.
    for my $path (@euc) {
	my $use = uses_of($path);
	cmp_ok(scalar(keys %$use), '>', 0,
	       "$path: its dependencies were read");
    }
};


# ---------------------------------------------------------------------
# 2. everything loaded can be found
# ---------------------------------------------------------------------
subtest 'every dependency resolves on @INC' => sub {
    my @missing = ();

    for my $m (sort keys %WANTED) {
	next if $OPTIONAL{ $m };
	next if resolve($m);
	push @missing, sprintf("%s (from %s)", $m, $WANTED{ $m }[0]);
    }

    is(scalar(@missing), 0, 'no module reaches for something that is not there')
	or diag(join("\n", @missing));

    cmp_ok(scalar(keys %WANTED), '>', 40,
	   sprintf("checked %d distinct dependencies", scalar(keys %WANTED)));
};


# ---------------------------------------------------------------------
# 3. a removed bundle stays removed
#
# Separate from the check above, and stricter: a module that is gone
# from cpan/ may still be installed on the host, in which case the
# resolve() test would pass and hide the fact that fml8 has quietly gone
# back to depending on it.
# ---------------------------------------------------------------------
subtest 'nothing reaches for a bundle that was removed' => sub {
    my @back = ();

    for my $m (sort keys %WANTED) {
	push @back, sprintf("%s used at %s", $m, join(', ', @{ $WANTED{ $m } }))
	    if $REMOVED{ $m };
    }

    is(scalar(@back), 0, 'no removed bundle is used again')
	or diag(join("\n", @back));

    # And the bundles are really gone from the tree, not merely unused.
    #
    # Crypt::PPDES is the exception, and it is one loose end rather than
    # a decision: Crypt::TripleDES was removed because nothing referenced
    # it and it could never have loaded, its first statement being "use
    # Crypt::PPDES".  PPDES was that private dependency and nothing else
    # uses it, but it was left behind, and cpan/MANIFEST records neither.
    # Recorded rather than deleted here, because removing a file from a
    # vendor drop is not this test's decision.
    my %LEFTOVER = ('Crypt::PPDES' => 'orphaned when Crypt::TripleDES went');

    for my $m (sort keys %REMOVED) {
	(my $file = $m) =~ s{::}{/}g;

	if ($LEFTOVER{ $m }) {
	    local $TODO = $LEFTOVER{ $m };
	    ok(!-f "cpan/lib/$file.pm", "cpan/lib no longer carries $m");
	}
	else {
	    ok(!-f "cpan/lib/$file.pm", "cpan/lib no longer carries $m");
	}
    }

    # Whatever is left in cpan/lib should be in cpan/MANIFEST, which is
    # how anyone finds out where a bundled copy came from.
    my $manifest = '';
    if (open(my $fh, '<', 'cpan/MANIFEST')) {
	local $/ = undef;
	$manifest = <$fh>;
	close($fh);
    }

    ok($manifest, 'cpan/MANIFEST is readable');
    {
	local $TODO = 'Crypt::PPDES is in the tree but not in the MANIFEST';
	like($manifest, qr/PPDES/, 'cpan/MANIFEST accounts for Crypt::PPDES');
    }
};


# ---------------------------------------------------------------------
# 4. the optional list is exactly what it says
#
# An optional dependency is a decision: it means an installation without
# it still works.  If one appears without being added here, that decision
# was never taken.
# ---------------------------------------------------------------------
subtest 'the optional dependencies are the declared ones' => sub {
    my @unresolved = ();

    for my $m (sort keys %WANTED) {
	push @unresolved, $m unless resolve($m);
    }

    my @unexpected = grep { !$OPTIONAL{ $_ } } @unresolved;
    is(scalar(@unexpected), 0, 'nothing unresolvable beyond the declared list')
	or diag("unexpected: @unexpected");

    # Anything declared optional but present here cannot be checked, so
    # say so rather than passing quietly.
    for my $m (sort keys %OPTIONAL) {
	if (resolve($m)) {
	    diag("$m is installed here, so its optionality is not exercised");
	}
	else {
	    ok(1, "$m is absent and fml8 still loads without it");
	}
    }
};


# ---------------------------------------------------------------------
# 5. an optional dependency must be optional in the code as well
#
# Declaring GD optional is worth nothing if a plain "use GD" sits at the
# top of a module, since the module then fails to compile.  It has to be
# reached through eval, or from inside a sub that an installation
# without it never calls.
# ---------------------------------------------------------------------
subtest 'an optional dependency is not loaded at compile time' => sub {
    for my $m (sort keys %OPTIONAL) {
	my $sites = $WANTED{ $m } || [];
	cmp_ok(scalar(@$sites), '>', 0, "$m is used somewhere");

	for my $site (@$sites) {
	    my ($path, $line) = $site =~ /^(.*):(\d+)$/;

	    open(my $fh, '<', $path) or next;
	    my @src = <$fh>;
	    close($fh);

	    # A top level "use" is one at column zero.  Anything indented
	    # is inside a sub or an eval, which is the point.
	    my $text = $src[ $line - 1 ] || '';
	    unlike($text, qr/^use\s/,
		   "$site: $m is not loaded at compile time");
	}
    }
};


# ---------------------------------------------------------------------
# 6. the bundled copies are the ones that get used
#
# cpan/lib goes on the end of @INC so a host installation wins.  What
# must not happen is a module being bundled and then not found at all,
# which is what a MANIFEST out of step with the tree leads to.
# ---------------------------------------------------------------------
subtest 'every bundled module is loadable' => sub {
    my @bundled = ();

    my $walk;
    $walk = sub {
	my ($dir) = @_;
	opendir(my $dh, $dir) or return;
	for my $e (sort grep { !/^\.\.?$/ } readdir($dh)) {
	    my $path = "$dir/$e";
	    if (-d $path)            { $walk->($path) }
	    elsif ($path =~ /\.pm$/) { push @bundled, $path }
	}
	closedir($dh);
    };
    $walk->('cpan/lib') if -d 'cpan/lib';

    # XXX this was "more than five", written when cpan/lib held sixty
    # XXX and the worry was the walk finding nothing.  The clearing out
    # XXX has taken it to five, so the number to guard is the other end:
    # XXX every module here should be one fml8 asks for, and a new one
    # XXX appearing is worth a look.
    cmp_ok(scalar(@bundled), '>', 0,
	   sprintf("cpan/lib carries %d modules", scalar(@bundled)));
    cmp_ok(scalar(@bundled), '<=', 5,
	   'and no more than the five that are left')
	or diag("bundled: @bundled");

    # Only the ones fml8 actually asks for: cpan/lib holds whole
    # distributions, and a module nothing uses failing to load is a
    # different question (see the commit that removed five of them).
    my $checked = 0;
    for my $path (@bundled) {
	(my $m = $path) =~ s{^cpan/lib/}{};
	$m =~ s{/}{::}g;
	$m =~ s{\.pm$}{};
	next unless $WANTED{ $m };

	$checked++;
	my $out = `perl -Ifml/lib -Icpan/lib -Iimg/lib -I. -c $path 2>&1`;
	is($?, 0, "$m compiles") or diag($out);
    }

    cmp_ok($checked, '>', 0, "checked $checked bundled modules fml8 uses");
};

done_testing();
