#-*- perl -*-
#
# Charset handling regression tests.
#
# fml8 is reported to mangle mail fairly often ("文字化け").  These tests
# pin down the charset layer so that regressions are caught by CI.
#
# NOTE: the strings below are raw octets on purpose.  Mail arrives as
# octets and fml8 handles it as octets, so the tests must not let perl
# decode them into character strings.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

# The bundled cpan/lib must be APPENDED, never prepended: it ships
# File::Spec 0.7, which lacks splitdir()/splitpath()/rel2abs() that both
# fml8 and prove(1) call.  Putting it in front of the core library breaks
# the test harness itself.
BEGIN {
    for my $d (qw(fml/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Message::Encode;
use Mail::Message::Charset;

my $enc = new Mail::Message::Encode;
my $cs  = new Mail::Message::Charset;

# "日本語" in each encoding, as octets.
my %JP = (
    'utf8' => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e",
    'euc'  => "\xc6\xfc\xcb\xdc\xb8\xec",
    'sjis' => "\x93\xfa\x96\x7b\x8c\xea",
    'jis'  => "\x1b\x24\x42\x46\x7c\x4b\x5c\x38\x6c\x1b\x28\x42",
);

# ---------------------------------------------------------------------
# 1. code detection
# ---------------------------------------------------------------------
subtest 'detect_code() recognises the Japanese encodings' => sub {
    is($enc->detect_code($JP{utf8}), 'utf8', 'UTF-8 detected');
    is($enc->detect_code($JP{euc}),  'euc',  'EUC-JP detected');
    is($enc->detect_code($JP{sjis}), 'sjis', 'Shift_JIS detected');
    is($enc->detect_code($JP{jis}),  'jis',  'ISO-2022-JP detected');
    is($enc->detect_code("plain ascii"), 'ascii', 'ASCII detected');
};

# ---------------------------------------------------------------------
# 2. conversion into the internal charset (euc-jp)
# ---------------------------------------------------------------------
subtest 'every Japanese encoding converts into internal euc-jp' => sub {
    for my $from (qw(utf8 euc sjis jis)) {
	is($enc->convert($JP{$from}, 'euc-jp'), $JP{euc},
	   "$from -> euc-jp");
    }
};

# ---------------------------------------------------------------------
# 3. conversion back out
# ---------------------------------------------------------------------
subtest 'conversion out of the internal charset' => sub {
    is($enc->convert($JP{euc}, 'jis-jp'),  $JP{jis},  'euc-jp -> ISO-2022-JP');
    is($enc->convert($JP{euc}, 'sjis-jp'), $JP{sjis}, 'euc-jp -> Shift_JIS');

    # KNOWN GAP: _jp_str_ref() only accepts jis/sjis/euc as $out_code, so
    # asking for utf8 silently returns the input untouched.  That is one
    # root cause of mojibake for UTF-8 subscribers: fml8 can read UTF-8
    # but can never emit it.
    my $out = $enc->convert($JP{euc}, 'utf8');
    {
	local $TODO = 'Mail::Message::Encode cannot emit UTF-8 yet';
	is($out, $JP{utf8}, 'euc-jp -> UTF-8');
    }
};

# ---------------------------------------------------------------------
# 4. MIME charset name -> language
#
# This is what FML::Header::Subject uses to pick $in_code/$out_code when
# it rewrites a Subject:.  A charset name that does not resolve makes
# both codes empty, and the subject is then handled with the wrong
# assumption.  Real mail uses the IANA names, so those must be known.
# ---------------------------------------------------------------------
subtest 'message_charset_to_language() knows the IANA charset names' => sub {
    is($cs->message_charset_to_language('iso-2022-jp'), 'ja', 'iso-2022-jp');
    is($cs->message_charset_to_language('ISO-2022-JP'), 'ja', 'case insensitive');
    is($cs->message_charset_to_language('euc-jp'),      'ja', 'euc-jp');
    is($cs->message_charset_to_language('us-ascii'),    'en', 'us-ascii');

    # The names that actually turn up in Content-Type: and in =?...?=
    # encoded words, as opposed to fml's own shorthands.  A name missing
    # from the map resolves to no language, so the message gets no
    # language hint at all and silently falls back to the default.
    for my $name (qw(shift_jis shift-jis x-sjis cp932 windows-31j
		     euc_jp x-euc-jp
		     iso-2022-jp-1 iso-2022-jp-2 csiso2022jp)) {
	is($cs->message_charset_to_language($name), 'ja', $name);
    }
    is($cs->message_charset_to_language('Shift_JIS'), 'ja',
       'Shift_JIS resolves whatever the case');
    is($cs->message_charset_to_language('ascii'), 'en', 'ascii');

    # A Japanese charset must carry through to both the internal and the
    # wire charset, which is what the callers actually ask for.
    my $lang = $cs->message_charset_to_language('Shift_JIS');
    is($cs->language_to_internal_charset($lang), 'euc-jp',
       'Shift_JIS -> internal euc-jp');
    is($cs->language_to_message_charset($lang), 'iso-2022-jp',
       'Shift_JIS -> wire iso-2022-jp');

    # KNOWN GAP: utf-8 is absent entirely.  fml8 has no language-neutral
    # notion of a charset, so utf-8 cannot be mapped to "ja" without
    # breaking non-Japanese mail.  Fixing this needs a design change, not
    # just another hash entry.
    {
	local $TODO = 'utf-8 is not represented in the charset model';
	isnt($cs->message_charset_to_language('utf-8'), '', 'utf-8 resolves');
    }
};

# ---------------------------------------------------------------------
# 5. undef must not warn (fml8 issue #8)
# ---------------------------------------------------------------------
subtest 'charset lookups tolerate undef (issue #8)' => sub {
    my @warn = ();
    local $SIG{__WARN__} = sub { push @warn, $_[0] };

    is($cs->language_to_message_charset(undef),  '', 'message charset');
    is($cs->language_to_internal_charset(undef), '', 'internal charset');
    is($cs->message_charset_to_language(undef),  '', 'charset to language');

    is(scalar(@warn), 0, 'no "uninitialized value in lc" warning')
	or diag("warnings: @warn");
};

# ---------------------------------------------------------------------
# 6. non-Japanese mail must survive untouched
#
# Article relay and spooling do no charset conversion, so non-Japanese
# bodies are passed through verbatim.  detect_code() guesses wrongly for
# them, so nothing may act on that guess in the relay path.
# ---------------------------------------------------------------------
subtest 'non-Japanese octets are not silently rewritten' => sub {
    my %other = (
	'French UTF-8'  => "caf\xc3\xa9 cr\xc3\xa8me",
	'Russian UTF-8' => "\xd0\xbf\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82",
	'Korean UTF-8'  => "\xed\x95\x9c\xea\xb5\xad\xec\x96\xb4",
    );

    for my $name (sort keys %other) {
	my $s = $other{$name};
	is(length($s), length($s), "$name: length is stable");
    }

    # detect_code() is a Japanese-oriented heuristic and misfires here.
    # Recorded so that a future language-neutral detector shows up as a
    # deliberate change rather than a surprise.
    isnt($enc->detect_code($other{'Korean UTF-8'}), 'utf8',
	 'Korean UTF-8 is currently mis-detected (documented behaviour)');
};

# ---------------------------------------------------------------------
# 7. the external ("printable") form
#
# as_external_form() is what gets written to local files such as
# "summary" and "log"; it is not used for mail transfer.  Its charset was
# hard-coded to EUC-JP with an XXX-TODO saying it should become UTF-8.
# The charset is now overridable per object, so pin both the unchanged
# default and the override.
# ---------------------------------------------------------------------
subtest 'external form charset is the default unless enforced' => sub {
    use Mail::Message::Subject;

    my $mime = "=?UTF-8?B?W2VsZW5hOjAwMDAxXSDml6XmnKzoqp4=?=";  # [elena:00001] 日本語
    my $tag  = "[elena:%05d]";

    my $strip = sub {
	my ($s) = @_;
	$s->mime_header_decode();
	$s->delete_tag($tag);
	my $out = $s->as_external_form();
	$out =~ s/^\s+//;
	return $out;
    };

    my $default = $strip->(new Mail::Message::Subject $mime);
    is($default, $JP{euc}, 'default is still EUC-JP (unchanged behaviour)');

    my $sbj = new Mail::Message::Subject $mime;
    $sbj->set_mime_charset('UTF-8');
    is($strip->($sbj), $JP{utf8}, 'set_mime_charset("UTF-8") is honoured');

    # set_mime_charset() used to be an empty stub, so this would have
    # silently returned EUC-JP.
    isnt($strip->($sbj), $default, 'the override actually changes the output');
};

# ---------------------------------------------------------------------
# 8. guess_encoding()
#
# This used to call Unicode::Japanese, which was the only reason
# Mail::Message::Encode::Perl needed anything outside the perl core.
# Encode::Guess replaces it and must agree on every case, and must say
# "unknown" rather than inventing an answer when it cannot decide.
# ---------------------------------------------------------------------
subtest 'guess_encoding() needs nothing outside the core' => sub {
    use Mail::Message::Encode::Perl;
    my $e = new Mail::Message::Encode::Perl;

    is($e->guess_encoding($JP{utf8}), 'utf8',  'UTF-8');
    is($e->guess_encoding($JP{euc}),  'euc',   'EUC-JP');
    is($e->guess_encoding($JP{sjis}), 'sjis',  'Shift_JIS');
    is($e->guess_encoding($JP{jis}),  'jis',   'ISO-2022-JP');
    is($e->guess_encoding("plain ascii"), 'ascii', 'ASCII');

    # Unicode::Japanese answered "utf16" for this; an honest "unknown"
    # is what the rest of fml8 checks for.
    is($e->guess_encoding("\xff\xfe\x00\x01"), 'unknown',
       'undecidable input is reported as unknown');

    # %INC cannot answer this: the old Mail::Message::Encode is loaded by
    # other tests in this file and drags Jcode, and therefore
    # Unicode::Japanese, in behind it.  Ask the source instead.
    my $src = '';
    for my $dir (@INC) {
	my $path = "$dir/Mail/Message/Encode/Perl.pm";
	next unless -f $path;
	open(my $fh, '<', $path) or next;
	local $/ = undef;
	$src = <$fh>;
	close($fh);
	last;
    }
    ok($src, 'found the module source');

    # Comments are documentation: the XXX note explaining the removal
    # mentions the module by name on purpose. Only look at code.
    my $code = join("\n", grep { !/^\s*#/ } split(/\n/, $src));
    unlike($code, qr/Unicode::Japanese/,
	   'Mail::Message::Encode::Perl no longer uses Unicode::Japanese');
};

done_testing();
