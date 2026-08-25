#-*- perl -*-
#
# Do fml4 and fml8 turn the same octets into the same octets?
#
# t/2*_parity_*.t compare what the two can be asked.  This one compares
# what they answer: fml4's jcode.pl and fml8's Mail::Message::Encode are
# both run on the same input and their output is compared byte for byte.
#
# Charset conversion is where fml is reported to mangle mail, and it is
# the one part of fml4 that can be run on its own -- jcode.pl is a
# self-contained Perl 4 library.  So this is the piece of behaviour that
# can actually be held to fml4's answer rather than to an opinion about
# what the answer should be.
#
# fml4 runs in a process of its own; see ParityFML4::run_in_fml4.
#
# Everything here is raw octets on purpose.  Mail arrives as octets and
# both generations handle it as octets, so perl must not be allowed to
# decode any of it into characters.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);
use lib 't';

# cpan/lib and img/lib go on the end of @INC, so that a module the host
# has installed wins over the bundled copy.  It used to matter more than
# that: cpan/lib carried File::Spec 0.7, which lacks splitdir() and
# splitpath(), and putting it first broke fml8 and prove(1) alike.  That
# copy is gone now, but the order is still the right way round.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use ParityFML4;
use Mail::Message::Encode;

plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless ParityFML4::fml4_dir();
plan skip_all => "fml4 will not run here"
    unless ParityFML4::fml4_is_runnable();

# fml4 as published does not compile on a perl newer than 5.30, so this
# comparison can only be made against a tree that has been made to.  The
# modernize-perl branch is exactly that and changes nothing else.
my $LOAD_ERROR = ParityFML4::fml4_load_error("module/Japanese/jcode.pl");
plan skip_all => $LOAD_ERROR if $LOAD_ERROR;

my $ENC = new Mail::Message::Encode;

# The same text in each encoding, as octets.
my %JP = (
    'euc'  => "\xc6\xfc\xcb\xdc\xb8\xec",
    'sjis' => "\x93\xfa\x96\x7b\x8c\xea",
    'jis'  => "\x1b\x24\x42\x46\x7c\x4b\x5c\x38\x6c\x1b\x28\x42",
    'utf8' => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e",
);

# A longer sample, so a conversion that only handles the first character
# has somewhere to go wrong.  "こんにちは、世界。" in EUC-JP.
my $LONG_EUC = "\xa4\xb3\xa4\xf3\xa4\xcb\xa4\xc1\xa4\xcf\xa1\xa2" .
	       "\xc0\xa4\xb3\xa6\xa1\xa3";

# fml4's jcode code names against fml8's.
my %CODE = (
    'euc'  => 'euc-jp',
    'sjis' => 'sjis-jp',
    'jis'  => 'jis-jp',
);


# Descriptions: run fml4's jcode.pl over $hex and return the result as
#               hex.  Everything crosses the process boundary as hex so
#               that no shell, pipe or locale can touch the octets.
#    Arguments: STR($hex) STR($to)
# Side Effects: forks a perl(1).
# Return Value: STR
sub fml4_convert
{
    my ($hex, $to) = @_;

    my $out = ParityFML4::run_in_fml4(qq{
	require "./module/Japanese/jcode.pl";
	my \$s = pack("H*", "$hex");
	jcode::convert(\\\$s, "$to");
	print unpack("H*", \$s), "\\n";
    });

    chomp($out);
    $out =~ s/\s+//g;
    return $out;
}


# Descriptions: ask fml4's jcode.pl what encoding $hex is.
#    Arguments: STR($hex)
# Side Effects: forks a perl(1).
# Return Value: STR
sub fml4_getcode
{
    my ($hex) = @_;

    my $out = ParityFML4::run_in_fml4(qq{
	require "./module/Japanese/jcode.pl";
	my \$s = pack("H*", "$hex");
	my \$c = jcode::getcode(\\\$s);
	print "\$c\\n";
    });

    chomp($out);
    # getcode() returns its answer with a leading field count in this
    # vintage; keep the name.
    $out =~ s/^\d+//;
    return $out;
}


# Descriptions: the same conversion through fml8.
#    Arguments: STR($hex) STR($to)
# Side Effects: none
# Return Value: STR
sub fml8_convert
{
    my ($hex, $to) = @_;
    my $s = pack("H*", $hex);

    return unpack("H*", $ENC->convert($s, $CODE{ $to }));
}


# ---------------------------------------------------------------------
# 1. fml4's converter really runs
#
# If it did not, every comparison below would be against the empty
# string and would pass for the wrong reason.
# ---------------------------------------------------------------------
subtest "fml4's jcode.pl runs and converts" => sub {
    my $got = fml4_convert(unpack("H*", $JP{sjis}), 'euc');

    ok(length($got), 'something came back');
    is($got, unpack("H*", $JP{euc}), 'Shift_JIS -> EUC-JP is right');
};


# ---------------------------------------------------------------------
# 2. every conversion between the three Japanese encodings
# ---------------------------------------------------------------------
subtest 'fml4 and fml8 convert identically' => sub {
    for my $from (qw(euc sjis jis)) {
	for my $to (qw(euc sjis jis)) {
	    my $hex = unpack("H*", $JP{ $from });
	    my $f4  = fml4_convert($hex, $to);
	    my $f8  = fml8_convert($hex, $to);

	    is($f8, $f4, "$from -> $to: fml8 $f8 == fml4 $f4");
	}
    }
};


# ---------------------------------------------------------------------
# 3. the same, on a longer string
#
# Nine characters with punctuation, so a converter that stops at the
# first shift sequence or mishandles a two-byte symbol shows up.
# ---------------------------------------------------------------------
subtest 'a longer string converts identically' => sub {
    my $hex = unpack("H*", $LONG_EUC);

    for my $to (qw(euc sjis jis)) {
	my $f4 = fml4_convert($hex, $to);
	my $f8 = fml8_convert($hex, $to);

	is($f8, $f4, "long euc -> $to agrees (" . length($f4) / 2 . " octets)");
    }
};


# ---------------------------------------------------------------------
# 4. round trips lose nothing, in both
# ---------------------------------------------------------------------
subtest 'a round trip returns the original, in both' => sub {
    my $euc = unpack("H*", $JP{euc});

    for my $via (qw(sjis jis)) {
	my $f4 = fml4_convert(fml4_convert($euc, $via), 'euc');
	my $f8 = fml8_convert(fml8_convert($euc, $via), 'euc');

	is($f4, $euc, "fml4: euc -> $via -> euc");
	is($f8, $euc, "fml8: euc -> $via -> euc");
    }
};


# ---------------------------------------------------------------------
# 5. encoding detection agrees
#
# The conversion is only as good as the guess about what came in, and
# both generations guess rather than being told.
# ---------------------------------------------------------------------
subtest 'fml4 and fml8 detect the same encoding' => sub {
    for my $c (qw(euc sjis jis)) {
	my $hex = unpack("H*", $JP{ $c });
	my $f4  = fml4_getcode($hex);
	my $f8  = $ENC->detect_code($JP{ $c });

	is($f8, $f4, "$c: fml8 says $f8, fml4 says $f4");
    }

    # ASCII: fml4 answers with the empty string rather than a name.
    my $f4_ascii = fml4_getcode(unpack("H*", "plain ascii"));
    is($ENC->detect_code("plain ascii"), 'ascii',
       "fml8 says ascii, fml4 says '" . $f4_ascii . "'");
};


# ---------------------------------------------------------------------
# 6. UTF-8, where the two generations part company
#
# fml4 predates UTF-8 mail; fml8 reads it.  This is a difference, not a
# regression, but it should be visible: a UTF-8 subscriber is the case
# fml4 could never serve and fml8 half can.
# ---------------------------------------------------------------------
subtest 'UTF-8 input: fml8 understands it, fml4 does not' => sub {
    my $hex = unpack("H*", $JP{utf8});

    my $f4 = fml4_getcode($hex);
    my $f8 = $ENC->detect_code($JP{utf8});

    is($f8, 'utf8', 'fml8 detects UTF-8');
    isnt($f4, 'utf8', "fml4 does not; it says '" . $f4 . "'");

    # fml8 can bring it in to the internal encoding.  fml4 has no name
    # for the conversion at all, so there is nothing to compare with.
    is(unpack("H*", $ENC->convert($JP{utf8}, 'euc-jp')),
       unpack("H*", $JP{euc}),
       'fml8 converts UTF-8 into the internal EUC-JP');

    # And back out, which it still cannot do.
    local $TODO = 'Mail::Message::Encode cannot emit UTF-8 yet';
    is(unpack("H*", $ENC->convert($JP{euc}, 'utf8')), $hex,
       'fml8 converts EUC-JP into UTF-8');
};


# ---------------------------------------------------------------------
# 7. ASCII is never touched by either
#
# Article bodies pass through fml unchanged; anything that rewrote plain
# ASCII would be corrupting mail that has nothing to do with Japanese.
# ---------------------------------------------------------------------
subtest 'ASCII passes through untouched in both' => sub {
    my @sample = (
	'hello world',
	'Subject: [elena:00001] hello',
	"line one\nline two\n",
	'user@example.jp',
	'-----BEGIN PGP SIGNATURE-----',
    );

    for my $s (@sample) {
	my $hex = unpack("H*", $s);

	for my $to (qw(euc jis sjis)) {
	    my $f4 = fml4_convert($hex, $to);
	    my $f8 = fml8_convert($hex, $to);

	    is($f4, $hex, "fml4 leaves it alone (-> $to)");
	    is($f8, $hex, "fml8 leaves it alone (-> $to)");
	}
    }
};

done_testing();
