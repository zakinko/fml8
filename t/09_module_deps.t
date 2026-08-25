#-*- perl -*-
#
# What fml8 bundles, and whether it still adds up.
#
# cpan/lib is fml8's answer to "you need these and they may not be
# installed": a copy of each, on @INC after the host's own.  Taking a
# module out of it is safe exactly when nothing reaches it, and that is
# a claim about the whole tree rather than about the module.
#
# So this file asks it three ways.  Nothing loads what was removed;
# everything that stayed is reached by something; and what is present
# is what cpan/MANIFEST says is present.  A later branch that deletes
# one file too many fails here rather than in somebody's aliases run.
#

use strict;
use warnings;
use Test::More;
use File::Find;

my $LIB  = 'fml/lib';
my $CPAN = 'cpan/lib';

plan skip_all => "run me from the top of the tree" unless -d $LIB && -d $CPAN;


# The bundle as it stands, as module names.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub bundled
{
    my @found = ();

    find(sub {
	     return unless /\.pm$/;
	     my $rel = $File::Find::name;
	     $rel =~ s{^\Q$CPAN\E/}{};
	     $rel =~ s{/}{::}g;
	     $rel =~ s{\.pm$}{};
	     push @found, $rel;
	 }, $CPAN);

    return [ sort @found ];
}


# Every module name fml8's own code asks for, with where it asks.
#    Arguments: none
# Side Effects: none
# Return Value: HASH_REF
sub wanted_by_fml
{
    my %want = ();

    my @dir = grep { -d $_ } ($LIB, 'img/lib', 't');

    # no_chdir, because the paths collected are relative to the top
    # and File::Find would otherwise leave us in the directory it found
    # them in, where those paths do not open.
    find({ no_chdir => 1, wanted => sub {
	     my $path = $File::Find::name;
	     return unless $path =~ /\.(pm|pl|t)$/;

	     open(my $fh, '<', $path) or return;
	     binmode($fh);
	     my $ln = 0;
	     while (my $line = <$fh>) {
		 $ln++;
		 next if $line =~ /^\s*#/;
		 $line =~ s/#.*$//;

		 while ($line =~ /^\s*(?:use|require)\s+
                                  ([A-Z][A-Za-z0-9_]*(?:::[A-Za-z0-9_]+)*)/gx) {
		     push @{ $want{ $1 } }, "$path:$ln";
		 }
	     }
	     close($fh);
	 } }, @dir);

    return \%want;
}


my $bundled = bundled();
my $want    = wanted_by_fml();


# ---------------------------------------------------------------------
# 1. the bundle is small, and small on purpose
#
# It held sixty-five modules.  A floor as well as a ceiling, because
# zero would mean the walk found nothing and said so cheerfully.
# ---------------------------------------------------------------------
subtest 'cpan/lib holds a short, deliberate list' => sub {
    cmp_ok(scalar(@$bundled), '>',  0,  'the walk found something');
    cmp_ok(scalar(@$bundled), '<=', 20, 'and not more than twenty')
	or diag("bundled: @$bundled");
};


# ---------------------------------------------------------------------
# 2. nothing asks for what was taken out
#
# The names, spelled out.  A test that recomputed this list from the
# tree would agree with itself no matter what the tree said.
# ---------------------------------------------------------------------
subtest 'nothing reaches for a bundle that was removed' => sub {
    my @removed = qw(
	Crypt::PPDES Crypt::RandPasswd Crypt::TripleDES Crypt::UnixCrypt
	Email::Find Email::Find::addrspec Exporter::Lite
	File::MMagic
	HTML::EntitiesLite HTML::FromText
	MIME::Lite::HTML MIME::Type MIME::Types MojoX::MIME::Types
	Mail::Cap Mail::Field Mail::Filter Mail::Internet Mail::Mailer
	Mail::Send Mail::Util MailTools
	Time::CTime Time::DaysInMonth Time::JulianDay Time::ParseDate
	Time::Timezone
    );

    my @used = ();
    for my $m (@removed) {
	next unless $want->{ $m };
	push @used, "$m at " . join(", ", @{ $want->{ $m } });
    }

    is(scalar(@used), 0, 'no removed bundle is used again')
	or diag(join("\n", @used));

    for my $m (@removed) {
	(my $file = $m) =~ s{::}{/}g;
	ok(!-f "$CPAN/$file.pm", "cpan/lib no longer carries $m");
    }
};


# ---------------------------------------------------------------------
# 3. File::Spec is the core's now, and answers
#
# It was bundled because 5.005 did not have it.  Every perl fml8 can
# run on does, so the reason expired rather than the module.
# ---------------------------------------------------------------------
subtest 'File::Spec comes from the core' => sub {
    require File::Spec;
    unlike($INC{'File/Spec.pm'}, qr{\Qcpan/lib\E},
	   'File::Spec is not the bundled one');
    is(File::Spec->catfile('a', 'b', 'c.txt'), File::Spec->catfile('a','b','c.txt'),
       'and it answers');
};


# ---------------------------------------------------------------------
# 4. everything left is reached
#
# The other direction: a module nobody asks for is one more file to
# keep up to date for nothing.
# ---------------------------------------------------------------------
subtest 'every bundled module is reached by something' => sub {
    # Reached indirectly: these are asked for by another bundled module
    # rather than by fml8, which is a reason to keep them and not a
    # reason to expect them in fml/lib.
    my %via = (
	'Jcode::Constants'          => 'Jcode',
	'Jcode::H2Z'                => 'Jcode',
	'Jcode::Tr'                 => 'Jcode',
	'Jcode::Unicode'            => 'Jcode',
	'Jcode::Unicode::Constants' => 'Jcode::Unicode',
	'Jcode::Unicode::NoXS'      => 'Jcode::Unicode',
	'Jcode::_Classic'           => 'Jcode',
	'MIME::Base64::Perl'        => 'MIME::Lite',
	'MIME::QuotedPrint::Perl'   => 'MIME::Lite',
    );

    for my $m (@$bundled) {
	if ($via{ $m }) {
	    pass("$m is reached through $via{$m}");
	}
	else {
	    ok($want->{ $m }, "$m is asked for by fml8")
		or diag("nothing in fml/lib, img/lib or t/ names $m");
	}
    }
};


# ---------------------------------------------------------------------
# 5. the manifest and the directory agree
#
# cpan/MANIFEST is how a reader finds out which release a bundled copy
# came from.  It is only worth reading while it is true.
# ---------------------------------------------------------------------
subtest 'cpan/MANIFEST accounts for what is there' => sub {
    my $manifest = '';
    if (open(my $fh, '<', 'cpan/MANIFEST')) {
	local $/ = undef;
	$manifest = <$fh>;
	close($fh);
    }

    ok($manifest, 'cpan/MANIFEST is readable');

    my %top = ();
    for my $m (@$bundled) {
	my ($first) = split(/::/, $m);
	$top{ $first }++;
    }

    for my $t (sort keys %top) {
	like($manifest, qr/\b\Q$t\E\b/, "cpan/MANIFEST mentions $t");
    }
};


done_testing();

1;
