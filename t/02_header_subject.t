#-*- perl -*-
#
# FML::Header::Subject regression tests.
#
# encode_mime_string() and decode_mime_string() were moved out of
# Mail::Message::Encode into Mail::Message::Encode::Obsolete, but the two
# call sites here were left pointing at the old package, so every call
# died with "Can't locate object method".  Encode::Obsolete itself had no
# constructor and no parent either, so it could not have served them.
#
# The module is not reachable from the running code today: the only
# reference to it is inside FML::Header::rewrite_article_subject_tag_obsolete(),
# which is itself marked obsolete and never called.  These tests exist so
# that it is at least not broken, and so that the day it is either revived
# or deleted is a deliberate one.
#

use strict;
use warnings;
use Test::More;

# cpan/lib and img/lib must be APPENDED, never prepended: cpan/lib ships
# File::Spec 0.7, which lacks splitdir()/splitpath()/rel2abs() that both
# fml8 and prove(1) call.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Header::Subject;
use Mail::Message::Encode::Obsolete;

my $TAG = "[elena:%05d]";

# "日本語" in EUC-JP, which is the internal charset cleanup() returns.
my $JP_EUC = "\xc6\xfc\xcb\xdc\xb8\xec";

# "[elena:00001] 日本語" as a MIME encoded word.
my $SBJ_JIS  = "=?ISO-2022-JP?B?W2VsZW5hOjAwMDAxXSAbJEJGfEtcOGwbKEI=?=";
my $SBJ_UTF8 = "=?UTF-8?B?W2VsZW5hOjAwMDAxXSDml6XmnKzoqp4=?=";


# ---------------------------------------------------------------------
# 1. Encode::Obsolete must be usable on its own
# ---------------------------------------------------------------------
subtest 'Mail::Message::Encode::Obsolete is a usable object' => sub {
    my $obj = eval { new Mail::Message::Encode::Obsolete };
    ok(!$@, 'new() does not die') or diag($@);
    ok(defined $obj, 'constructor returns an object');

    # The moved routines call these on $self but the package defines
    # none of them; they have to come from the parent.
    for my $m (qw(new convert detect_code raw_decode_base64 raw_decode_qp)) {
	can_ok($obj, $m);
    }

    is($obj->{ _language }, 'japanese', '_language is initialised');
};


# ---------------------------------------------------------------------
# 2. the methods the call sites need actually resolve
# ---------------------------------------------------------------------
subtest 'the relocated methods resolve' => sub {
    my $obj = new Mail::Message::Encode::Obsolete;
    can_ok($obj, 'encode_mime_string');
    can_ok($obj, 'decode_mime_string');
    can_ok($obj, 'decode_mime_utf8_to_euc');

    # They are gone from where the call sites used to look.
    use Mail::Message::Encode;
    my $old = new Mail::Message::Encode;
    ok(!$old->can('decode_mime_string'),
       'decode_mime_string is no longer in Mail::Message::Encode');
};


# ---------------------------------------------------------------------
# 3. cleanup(): mime decode, strip the tag, return the internal charset
# ---------------------------------------------------------------------
subtest 'cleanup() decodes and de-tags' => sub {
    my $trim = sub { my $s = shift; $s =~ s/^\s+//; $s =~ s/\s+$//; return $s };

    my $ascii = eval { FML::Header::Subject->cleanup("[elena:00001] hello", $TAG) };
    ok(!$@, 'plain ASCII does not die') or diag($@);
    is($trim->($ascii), 'hello', 'ASCII: tag removed');

    my $jis = eval { FML::Header::Subject->cleanup($SBJ_JIS, $TAG) };
    ok(!$@, 'ISO-2022-JP does not die') or diag($@);
    is($trim->($jis), $JP_EUC, 'ISO-2022-JP: decoded to internal EUC-JP');

    my $utf8 = eval { FML::Header::Subject->cleanup($SBJ_UTF8, $TAG) };
    ok(!$@, 'UTF-8 does not die') or diag($@);
    is($trim->($utf8), $JP_EUC, 'UTF-8: decoded to internal EUC-JP');
};


# ---------------------------------------------------------------------
# 4. decode() returns the charset pair the caller relies on
# ---------------------------------------------------------------------
subtest 'decode() reports the wire and internal charsets' => sub {
    my ($subject, $tag, $in_code, $out_code) =
	FML::Header::Subject->decode($SBJ_JIS, $TAG);

    is($in_code,  'iso-2022-jp', 'in_code is the wire charset');
    is($out_code, 'euc-jp',      'out_code is the internal charset');

    # A subject with no encoded word has no charset to report.
    my (undef, undef, $in2, $out2) =
	FML::Header::Subject->decode("plain subject", $TAG);
    is($in2,  '', 'no encoded word: in_code empty');
    is($out2, '', 'no encoded word: out_code empty');
};

done_testing();
