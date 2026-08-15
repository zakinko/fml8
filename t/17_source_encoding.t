#-*- perl -*-
#
# The tree's own encoding.
#
# Parts of fml8 are EUC-JP: fml/doc/ja, and three modules whose comments
# are in Japanese.  An editor that decides a file is UTF-8, or a tool
# that reads it through a decoding layer and writes it back, turns those
# bytes into U+FFFD replacement characters and rewrites lines that had
# no business changing.  That has happened here once already: forty-six
# lines of one file at a stroke.
#
# The damage is quiet.  A file full of U+FFFD is valid UTF-8, it
# compiles, and every test still passes -- the comments are simply gone,
# replaced by a row of question marks, and the diff looks like somebody
# reformatted the file.
#
# So the check is not "is this file UTF-8" but "does this file still
# decode as something".  A file that is neither valid UTF-8 nor valid
# EUC-JP is one that a conversion got half way through.
#

use strict;
use warnings;
use Test::More;
use Encode qw(decode);

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

my @ROOT = grep { -d $_ } qw(fml cpan/lib t);

plan skip_all => "no source tree here" unless @ROOT;

# The files that are EUC-JP and are meant to stay that way.  Listed
# rather than discovered, so that one of them silently becoming UTF-8
# is a failure rather than a shorter list.
my @EUC_JP_SOURCE = qw(
    fml/lib/FML/Demo/Language/Japanese.pm
    fml/lib/Mail/Bounce/Language/Japanese.pm
    fml/lib/Mail/Message/Language/Japanese/Subject.pm
    fml/utils/bin/listup_recipes.pl
    fml/utils/bin/version_replace.pl
    fml/doc/en/tutorial/changes/conv2sgml.pl
    fml/doc/ja/tutorial/changes/conv2sgml.pl
);


# Descriptions: every file under @ROOT that this test judges.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub all_files
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
	    next if -l $path;
	    if (-d $path)                            { $walk->($path) }
	    elsif ($path =~ /\.(?:pm|pl|t|txt|sgml)$/) { push @found, $path }
	}
    };
    $walk->($_) for @ROOT;

    return \@found;
}


# Descriptions: the raw octets of $path.
#    Arguments: STR($path)
# Side Effects: none
# Return Value: STR
sub slurp
{
    my ($path) = @_;

    open(my $fh, '<', $path) or return '';
    binmode($fh);
    local $/ = undef;
    my $s = <$fh>;
    close($fh);

    return defined $s ? $s : '';
}


# Descriptions: which of UTF-8 and EUC-JP $octets decodes as.
#    Arguments: STR($octets)
# Side Effects: none
# Return Value: HASH_REF
sub decodes_as
{
    my ($octets) = @_;

    return {
	utf8 => (eval { decode("UTF-8",  $octets, Encode::FB_CROAK); 1 } ? 1 : 0),
	euc  => (eval { decode("EUC-JP", $octets, Encode::FB_CROAK); 1 } ? 1 : 0),
    };
}


my $FILES = all_files();

# The ones with anything above ASCII in them; the rest cannot be damaged
# by a transcode and are not interesting here.
my @NON_ASCII = grep { slurp($_) =~ /[\x80-\xff]/ } @$FILES;


# ---------------------------------------------------------------------
# 1. there is something to check
# ---------------------------------------------------------------------
subtest 'the tree has files with non-ASCII octets in it' => sub {
    cmp_ok(scalar(@$FILES), '>', 300,
	   sprintf("walked %d files", scalar(@$FILES)));
    cmp_ok(scalar(@NON_ASCII), '>=', scalar(@EUC_JP_SOURCE),
	   sprintf("%d of them carry non-ASCII octets", scalar(@NON_ASCII)));
};


# ---------------------------------------------------------------------
# 2. every file decodes as something
#
# The failure this is really looking for: a file that is half converted
# decodes as neither.
# ---------------------------------------------------------------------
subtest 'every file is valid UTF-8 or valid EUC-JP' => sub {
    my @bad = ();

    for my $path (@NON_ASCII) {
	my $d = decodes_as(slurp($path));
	push @bad, $path unless $d->{ utf8 } || $d->{ euc };
    }

    is(scalar(@bad), 0, 'no file is half converted')
	or diag("neither UTF-8 nor EUC-JP:\n" . join("\n", @bad));
};


# ---------------------------------------------------------------------
# 3. no replacement characters
#
# U+FFFD is what a decode with a lenient fallback leaves behind, and it
# is valid UTF-8, so the check above cannot see it.  There is no reason
# for one to be in a source file: it means text was decoded as the wrong
# encoding and written back.
# ---------------------------------------------------------------------
subtest 'no file carries a U+FFFD replacement character' => sub {
    my @bad = ();

    for my $path (@NON_ASCII) {
	my $s = slurp($path);
	# U+FFFD in UTF-8.
	push @bad, $path if $s =~ /\xef\xbf\xbd/;
    }

    is(scalar(@bad), 0, 'no replacement characters anywhere')
	or diag("contains U+FFFD:\n" . join("\n", @bad));
};


# ---------------------------------------------------------------------
# 4. the EUC-JP files are still EUC-JP
#
# The list is fixed on purpose.  A file leaving it means somebody
# transcoded it, which is exactly the event being guarded against, and
# it would not show up in a check that merely discovered whatever
# happened to be EUC-JP today.
# ---------------------------------------------------------------------
subtest 'the EUC-JP sources have not been transcoded' => sub {
    for my $path (@EUC_JP_SOURCE) {
      SKIP: {
	    skip("$path is not in this checkout", 3) unless -f $path;

	    my $s = slurp($path);
	    my $d = decodes_as($s);

	    ok($s =~ /[\x80-\xff]/, "$path: still has non-ASCII octets");
	    ok($d->{ euc },  "$path: decodes as EUC-JP");
	    ok(!$d->{ utf8 }, "$path: and not as UTF-8, so it was not converted");
	}
    }
};


# ---------------------------------------------------------------------
# 5. the mode line survives
#
# Every module starts with "#-*- perl -*-" and the Japanese ones under
# fml/doc/ja carry a coding cookie.  Both are how an editor is told what
# it is looking at, so losing one is how the next transcode happens.
# ---------------------------------------------------------------------
subtest 'the emacs mode lines are intact' => sub {
    my @missing = ();

    for my $path (@$FILES) {
	next unless $path =~ m{^fml/lib/.*\.pm$};

	open(my $fh, '<', $path) or next;
	my $first = <$fh>;
	close($fh);
	$first = '' unless defined $first;

	push @missing, $path unless $first =~ /-\*-\s*(?:mode:\s*)?perl/i;
    }

    # One module has never had it.  Recorded so the count cannot grow
    # without somebody deciding it should.
    is(scalar(@missing), 1,
       sprintf("exactly one module lacks the mode line: %s",
	       join(', ', @missing)))
	or diag(join("\n", @missing));
};


# ---------------------------------------------------------------------
# 6. no file mixes the two
#
# A file that is valid EUC-JP and also valid UTF-8 is almost always pure
# ASCII, which is fine.  One that is neither has already been caught.
# What is left to say is that the Japanese documentation is consistently
# one encoding rather than a mixture built up over time.
# ---------------------------------------------------------------------
subtest 'fml/doc/ja is consistently encoded' => sub {
  SKIP: {
	skip("no fml/doc/ja here", 1) unless -d 'fml/doc/ja';

	my %count = (utf8 => 0, euc => 0, both => 0, neither => 0);
	my @neither = ();

	for my $path (grep { m{^fml/doc/ja/} } @NON_ASCII) {
	    my $d = decodes_as(slurp($path));

	    if    ($d->{ utf8 } && $d->{ euc }) { $count{ both }++ }
	    elsif ($d->{ utf8 })                { $count{ utf8 }++ }
	    elsif ($d->{ euc })                 { $count{ euc }++ }
	    else { $count{ neither }++; push @neither, $path }
	}

	diag(sprintf("fml/doc/ja: euc-jp=%d utf-8=%d ambiguous=%d broken=%d",
		     $count{ euc }, $count{ utf8 },
		     $count{ both }, $count{ neither }));

	is($count{ neither }, 0, 'nothing under fml/doc/ja is half converted')
	    or diag(join("\n", @neither));
    }
};

done_testing();
