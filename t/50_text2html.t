#-*- perl -*-
#
# text2html(), now that HTML::FromText is not in the tree.
#
# fml8 used three of the eighteen decorators HTML::FromText offers --
# metachars, urls and pre -- so the 898 lines came out and the four
# things fml8 asked for went into Mail::Message::ToHTML.  The escaping
# came with them: HTML::FromText reached HTML::Entities through
# HTML::EntitiesLite, a cut fukachan@fml.org made from HTML-Parser
# 3.69 because the original is XS.
#
# Two things are held here.  The output for what fml8 passes, which
# should be what the module gave; and the one place it should not be,
# which is EUC-JP.
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Message::ToHTML;

sub t2h { return Mail::Message::ToHTML::text2html(@_) }


# ---------------------------------------------------------------------
# 1. the five characters that mean something to a parser
# ---------------------------------------------------------------------
subtest 'HTML metacharacters are escaped' => sub {
    is(t2h('a & b'),    'a &amp; b',       'ampersand');
    is(t2h('<b>'),      '&lt;b&gt;',       'angle brackets');
    is(t2h('"quoted"'), '&quot;quoted&quot;', 'double quote');
    is(t2h("it's"),     'it&#39;s',        'apostrophe, as a numeric reference');

    # &apos; is the name for it, and HTML-Parser 3.85 leaves it out of
    # its table on purpose -- "only one-way decoding" -- because older
    # browsers do not know it.  &#39; is what both give.
    unlike(t2h("it's"), qr/&apos;/, 'and not by the name older browsers miss');
};


# ---------------------------------------------------------------------
# 2. bytes above 127 are the caller's, not ours
#
# This is the bug the cut inherited.  HTML::Entities escapes "control
# chars, high bit chars" by default, which is right for a string of
# characters and wrong for a string of octets -- and ToHTML converts an
# article to euc-jp before calling this.  So
#
#     日本語  (c6fc cbdc b8ec)
#
# used to arrive as &AElig;&uuml;&Euml;&Uuml;&cedil;&igrave; in every
# Japanese article in every HTML archive.
# ---------------------------------------------------------------------
subtest 'EUC-JP octets pass through as themselves' => sub {
    my $euc = "\xc6\xfc\xcb\xdc\xb8\xec";              # 日本語 in EUC-JP

    is(t2h($euc), $euc, 'the bytes come back as the bytes that went in');
    unlike(t2h($euc), qr/&\w+;/, 'and not as Latin-1 entity names');

    is(t2h("mixed $euc & <b>"), "mixed $euc &amp; &lt;b&gt;",
       'while the metacharacters beside them are still escaped');
};


# ---------------------------------------------------------------------
# 3. urls, which fml8 turns on for article bodies
# ---------------------------------------------------------------------
subtest 'a URL becomes a link' => sub {
    like(t2h('see http://www.fml.org/ here', urls => 1),
	 qr{<a href="http://www\.fml\.org/"[^>]*>http://www\.fml\.org/</a>},
	 'http');

    like(t2h('ftp://ftp.jp/pub/', urls => 1), qr{<a href="ftp://},  'ftp');
    like(t2h('news:comp.lang.perl', urls => 1), qr{<a href="news:}, 'news');

    is(t2h('http://www.fml.org/'), 'http://www.fml.org/',
       'and nothing happens without the option');

    # The escaping runs first, so a URL with an ampersand in it is a
    # link whose href is escaped -- not a link that stops at the &.
    like(t2h('https://x.jp/a?b=1&c=2', urls => 1),
	 qr{href="https://x\.jp/a\?b=1&amp;c=2"},
	 'a query string keeps its parameters');
};


# ---------------------------------------------------------------------
# 4. pre, which is how an article keeps its shape
# ---------------------------------------------------------------------
subtest 'pre wraps and leaves the whitespace alone' => sub {
    my $got = t2h("  indented\nnext", pre => 1);

    like($got, qr{^<pre},   'opens with <pre>');
    like($got, qr{</pre>$}, 'and closes');
    like($got, qr{  indented}, 'the leading spaces survive');
};


# ---------------------------------------------------------------------
# 5. the tab expansion the module did on the way in
# ---------------------------------------------------------------------
subtest 'tabs are expanded, not passed on' => sub {
    my $got = t2h("a\tb");

    unlike($got, qr/\t/, 'no tab is left');
    like($got, qr/a\s+b/, 'and there is space where it was');
};


# ---------------------------------------------------------------------
# 6. the empty cases, which are where a rewrite usually breaks
# ---------------------------------------------------------------------
subtest 'nothing in, nothing out' => sub {
    is(t2h(''), '', 'an empty string');
    is(t2h('', urls => 1, pre => 0), '', 'with options');
    is(t2h('plain'), 'plain', 'text with nothing to do to it');
};


done_testing();

1;
