#-*- perl -*-
#
# The charset a caller asks for is the charset it gets.
#
# decode_base64_string() and decode_qp_string() both wrote
#
#	$out_code |= 'euc-jp';	# euc-jp by default.
#
# which is a bitwise or of two strings, not a default assignment.  With
# no $out_code the left side is empty and '' | 'euc-jp' is 'euc-jp', so
# the default case worked and nothing looked wrong.  With an explicit
# one, 'jis' | 'euc-jp' is 'o}s-jp', which matches no charset name, so
# the conversion was skipped and the caller got its input back in
# whatever charset it arrived in.  Silently: no error, no log, just the
# wrong octets.
#
# The same typo was in FML::Message::Encode::Obsolete, one line away
# from a correct ||= in the same file.
#
# These tests pass an explicit $out_code, which is the case that was
# broken, and they compare octets rather than asking whether a
# conversion "happened".
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);
use MIME::Base64 ();
use MIME::QuotedPrint ();

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Message::Encode;

my $ENC = new FML::Message::Encode;

# "日本語" as octets, in each encoding.
my %JP = (
    'utf8' => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e",
    'euc'  => "\xc6\xfc\xcb\xdc\xb8\xec",
    'sjis' => "\x93\xfa\x96\x7b\x8c\xea",
    'jis'  => "\x1b\x24\x42\x46\x7c\x4b\x5c\x38\x6c\x1b\x28\x42",
);

# The names a caller may reasonably use for each of them, and which of
# those the conversion layer actually recognises today.
#
# _jp_str_ref() matches /^(jis|sjis|euc)$|^(jis|sjis|euc)[-_]jp$/i plus
# iso-2022-jp, so fml's own shorthands work and the IANA names largely
# do not.  A name it does not recognise is not an error: the routine
# returns 0 and the string is handed back unconverted, which is the same
# silent failure the |= typo produced.  "Shift_JIS" is the one that
# matters, because that is what turns up in Content-Type: and in encoded
# words in real mail; t/01 records the same gap on the way in.
my %NAME = (
    'euc'  => [ qw(euc euc-jp euc_jp EUC-JP) ],
    'sjis' => [ qw(sjis sjis-jp) ],
    'jis'  => [ qw(jis jis-jp iso-2022-jp ISO-2022-JP) ],
);

my %NAME_NOT_YET = (
    'sjis' => [ qw(shift_jis Shift_JIS shift-jis x-sjis cp932 windows-31j) ],
    'euc'  => [ qw(x-euc-jp) ],
    'jis'  => [ qw(csiso2022jp iso-2022-jp-1) ],
);


# ---------------------------------------------------------------------
# 1. what the old line actually computed
#
# Written out so that the fix is not mistaken for a matter of taste.
# ---------------------------------------------------------------------
subtest '|= is a bitwise or, not a default' => sub {
    my $empty = '' | 'euc-jp';
    is($empty, 'euc-jp', 'with no left side it happens to give the default');

    # 'euc-jp' is left out on purpose: it is the default itself, and
    # x | x is x, so it is the one value the typo could not damage.
    for my $code (qw(jis sjis iso-2022-jp)) {
	my $bad = $code | 'euc-jp';
	isnt($bad, $code,
	     "'$code' |= 'euc-jp' does not leave '$code' alone");
    }

    is('euc-jp' | 'euc-jp', 'euc-jp',
       'the default charset is the one value the typo left intact');

    # And the result is not a charset, so nothing downstream matches it.
    my $bad = 'jis' | 'euc-jp';
    unlike($bad, qr/^(?:jis|sjis|euc)(?:[-_]jp)?$/i,
	   "the result ('$bad') is not a charset name");

    my $good = 'jis';
    $good ||= 'euc-jp';
    is($good, 'jis', 'the intended ||= leaves it alone');

    my $unset = '';
    $unset ||= 'euc-jp';
    is($unset, 'euc-jp', 'and still supplies the default when there is none');
};


# ---------------------------------------------------------------------
# 2. convert() honours an explicit output charset
#
# This is the layer the two decoders hand their $out_code to.
# ---------------------------------------------------------------------
subtest 'convert() gives the charset it was asked for' => sub {
    for my $to (qw(euc sjis jis)) {
	for my $name (@{ $NAME{ $to } }) {
	    is($ENC->convert($JP{ euc }, $name), $JP{ $to },
	       "euc-jp -> $name");
	}
    }

    # From each of them, not only from euc-jp.
    for my $from (qw(utf8 euc sjis jis)) {
	is($ENC->convert($JP{ $from }, 'euc-jp'), $JP{ euc },
	   "$from -> euc-jp");
    }
};


# ---------------------------------------------------------------------
# 2a. the IANA charset names, which are what real mail carries
#
# Recorded rather than hidden.  An unrecognised output charset is not
# reported: the string comes back in the charset it was already in, so
# a subscriber whose mailer says Shift_JIS gets EUC-JP octets labelled
# Shift_JIS, which is mojibake with no error anywhere.
#
# This needs the charset model to change rather than another name in a
# regexp -- see the same gap on the way in, in t/01.
# ---------------------------------------------------------------------
subtest 'the IANA charset names are not recognised yet' => sub {
    for my $to (sort keys %NAME_NOT_YET) {
	for my $name (@{ $NAME_NOT_YET{ $to } }) {
	    my $got = $ENC->convert($JP{ euc }, $name);

	    local $TODO = "'$name' is not in the conversion layer's name list";
	    is($got, $JP{ $to }, "euc-jp -> $name");
	}
    }

    # What happens instead, asserted so the behaviour is at least known:
    # the input is returned untouched.
    is($ENC->convert($JP{ euc }, 'Shift_JIS'), $JP{ euc },
       'an unrecognised charset silently returns the input unconverted');
};


# ---------------------------------------------------------------------
# 3. decode_base64_string() with an explicit charset
#
# The case the typo broke.
# ---------------------------------------------------------------------
subtest 'decode_base64_string() honours $out_code' => sub {
    my $b64 = MIME::Base64::encode_base64($JP{ euc }, '');

    is($ENC->decode_base64_string($b64), $JP{ euc },
       'no $out_code: euc-jp, as documented');

    for my $to (qw(euc sjis jis)) {
	for my $name (@{ $NAME{ $to } }) {
	    is($ENC->decode_base64_string($b64, $name), $JP{ $to },
	       "explicit '$name' gives $to");
	}
    }

    # The failure mode being guarded against is the input coming back
    # unchanged, so say that separately.
    isnt($ENC->decode_base64_string($b64, 'sjis'), $JP{ euc },
	 'asking for Shift_JIS does not hand back the EUC-JP input');
};


# ---------------------------------------------------------------------
# 4. decode_qp_string() with an explicit charset
# ---------------------------------------------------------------------
subtest 'decode_qp_string() honours $out_code' => sub {
    my $qp = MIME::QuotedPrint::encode_qp($JP{ euc });

    is($ENC->decode_qp_string($qp), $JP{ euc },
       'no $out_code: euc-jp, as documented');

    for my $to (qw(euc sjis jis)) {
	is($ENC->decode_qp_string($qp, $to), $JP{ $to },
	   "explicit '$to' gives $to");
    }

    isnt($ENC->decode_qp_string($qp, 'jis'), $JP{ euc },
	 'asking for ISO-2022-JP does not hand back the EUC-JP input');
};


# ---------------------------------------------------------------------
# 5. base64 from any source charset
#
# The decoder detects the input charset itself, so the pair
# (what arrived, what was asked for) is what has to be got right.
# ---------------------------------------------------------------------
subtest 'every source charset reaches every requested one' => sub {
    for my $from (qw(utf8 euc sjis jis)) {
	my $b64 = MIME::Base64::encode_base64($JP{ $from }, '');

	for my $to (qw(euc sjis jis)) {
	    is($ENC->decode_base64_string($b64, $to), $JP{ $to },
	       "base64($from) -> $to");
	}
    }
};


# ---------------------------------------------------------------------
# 6. the same typo in Encode::Obsolete
#
# One line above the one that was wrong, the same file had a correct
# ||=.  The module is not reachable from running code, but it must not
# be broken while it sits there.
# ---------------------------------------------------------------------
subtest 'Encode::Obsolete honours $out_code too' => sub {
    require FML::Message::Encode::Obsolete;
    my $obj = new FML::Message::Encode::Obsolete;

    # An encoded word carrying "日本語" in ISO-2022-JP.
    my $mime = "=?ISO-2022-JP?B?" .
	MIME::Base64::encode_base64($JP{ jis }, '') . "?=";

    my $default = $obj->decode_mime_string($mime);
    is($default, $JP{ euc }, 'no $out_code: euc-jp');

    for my $to (qw(euc sjis jis)) {
	is($obj->decode_mime_string($mime, $to), $JP{ $to },
	   "explicit '$to' gives $to");
    }
};


# ---------------------------------------------------------------------
# 7. ASCII is not touched, whatever charset is asked for
#
# Article bodies pass through fml8, so a converter that rewrote ASCII
# would be damaging mail that has nothing to do with Japanese.
# ---------------------------------------------------------------------
subtest 'ASCII survives every conversion' => sub {
    my $ascii = "Subject: hello, world!\n\t-- and a tab, and 0-9.\n";

    for my $to (qw(euc euc-jp sjis jis iso-2022-jp)) {
	is($ENC->convert($ascii, $to), $ascii, "ASCII unchanged into $to");
    }

    my $b64 = MIME::Base64::encode_base64($ascii, '');
    for my $to (qw(euc sjis jis)) {
	is($ENC->decode_base64_string($b64, $to), $ascii,
	   "base64(ASCII) -> $to is still the same octets");
    }
};


# ---------------------------------------------------------------------
# 8. round trips
#
# Conversion has to be reversible for the encodings that can represent
# the same characters, or a subject rewritten on the way in and back out
# does not survive the trip.
# ---------------------------------------------------------------------
subtest 'every conversion round trips' => sub {
    for my $a (qw(euc sjis jis)) {
	for my $b (qw(euc sjis jis)) {
	    my $there = $ENC->convert($JP{ $a }, $b);
	    my $back  = $ENC->convert($there,    $a);

	    is($back, $JP{ $a }, "$a -> $b -> $a");
	}
    }
};

done_testing();
