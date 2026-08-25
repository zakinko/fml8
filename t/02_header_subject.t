#-*- perl -*-
#
# FML::Header::Subject regression tests.
#
# encode_mime_string() and decode_mime_string() were moved out of
# FML::Message::Encode into FML::Message::Encode::Obsolete, but the two
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

use FML::Header::Subject;
use FML::Message::Encode::Obsolete;

# The obsolete path calls into the bundled IM package: decode_mime_string()
# goes through IM::EncDec and encode_mime_string() through IM::Iso2022jp.
# Both calls sit inside eval q{...}, so a load failure is swallowed and the
# string is handed back untouched -- a subject that quietly stays MIME
# encoded, which is the mojibake being chased here.
#
# Probe before any call site runs.  Once one of those evals has failed,
# %INC holds a false entry and every later require reports "Attempt to
# reload IM/EncDec.pm aborted", which says nothing about the real cause.
my %IM_ERROR = ();
for my $m (qw(IM::EncDec IM::Iso2022jp)) {
    (my $file = $m) =~ s{::}{/}g;
    eval { require "$file.pm"; 1 } or $IM_ERROR{ $m } = $@;
}

my $TAG = "[elena:%05d]";

# "日本語" in EUC-JP, which is the internal charset cleanup() returns.
my $JP_EUC = "\xc6\xfc\xcb\xdc\xb8\xec";

# "[elena:00001] 日本語" as a MIME encoded word.
my $SBJ_JIS  = "=?ISO-2022-JP?B?W2VsZW5hOjAwMDAxXSAbJEJGfEtcOGwbKEI=?=";
my $SBJ_UTF8 = "=?UTF-8?B?W2VsZW5hOjAwMDAxXSDml6XmnKzoqp4=?=";


# ---------------------------------------------------------------------
# 1. Encode::Obsolete must be usable on its own
# ---------------------------------------------------------------------
subtest 'FML::Message::Encode::Obsolete is a usable object' => sub {
    my $obj = eval { new FML::Message::Encode::Obsolete };
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
    my $obj = new FML::Message::Encode::Obsolete;
    can_ok($obj, 'encode_mime_string');
    can_ok($obj, 'decode_mime_string');
    can_ok($obj, 'decode_mime_utf8_to_euc');

    # They are gone from where the call sites used to look.
    use FML::Message::Encode;
    my $old = new FML::Message::Encode;
    ok(!$old->can('decode_mime_string'),
       'decode_mime_string is no longer in FML::Message::Encode');
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

    # Without IM::EncDec this branch is a no-op and $jis comes back still
    # encoded.  Say which module is missing and why rather than failing on
    # a machine that simply cannot load it.
  SKIP: {
	skip("IM::EncDec does not load here, so this branch is a no-op: " .
	     $IM_ERROR{'IM::EncDec'}, 1) if $IM_ERROR{'IM::EncDec'};
	is($trim->($jis), $JP_EUC, 'ISO-2022-JP: decoded to internal EUC-JP');
    }

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


# ---------------------------------------------------------------------
# 5. encode_mime_string(): the other half, and the other IM module
#
# XXX IM::Util picks the OS with $^O =~ /win/i, and "darwin" matches, so
# XXX on macOS it calls Win32::IsWinNT() and dies at compile time.
# XXX Everything that uses IM::Util -- IM::Iso2022jp among them -- is
# XXX unloadable there, and encode_mime_string() then returns the subject
# XXX with raw ISO-2022-JP octets in the header instead of an encoded
# XXX word.  img/ is a vendor drop synced from IM releases, and nothing
# XXX outside this obsolete path uses IM, so record it here rather than
# XXX patching a tree that the next sync overwrites.
# ---------------------------------------------------------------------
subtest 'encode_mime_string() produces an encoded word' => sub {
    my $obj = new FML::Message::Encode::Obsolete;

  SKIP: {
	skip("IM::Iso2022jp does not load here, so this branch is a no-op: " .
	     $IM_ERROR{'IM::Iso2022jp'}, 2) if $IM_ERROR{'IM::Iso2022jp'};

	my $out = $obj->encode_mime_string($JP_EUC, 'base64', 'jis', 'euc-jp');
	like($out, qr/^=\?ISO-2022-JP\?B\?/i, 'base64 encoded word');

	# The point of encoding: no raw octet may reach the header.
	unlike($out, qr/[\x80-\xff\e]/, 'no raw octets left in the header');
    }
};

done_testing();
