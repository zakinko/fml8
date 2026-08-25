#-*- perl -*-
#
# FML::CGI::Compat — CGI.pm をやめた分の代わり。
#
# CGI.pm は perl 5.021 で core を外れ、fml8 は同梱していない。つまり
# 素の perl に fml8 を置くと、管理画面は「CGI.pm を別に入れた人」に
# しか動かない。fml8 が CGI.pm に頼んでいるのは 16 関数で、しかも
# その大半は HTML 生成のヘルパ — CGI.pm 自身が非推奨にした側 — なので、
# 外に依存を置くより自分で持つ方が小さい。
#
# ここで固定するのは二つ。fml8 が実際に書いている呼び方で正しい HTML
# が出ること、そして QUERY_STRING と POST body の読み取りが RFC 3875
# のとおりであること。
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
    $ENV{ REQUEST_METHOD } = 'GET';
    $ENV{ QUERY_STRING   } = '';
}

use FML::CGI::Compat;


# ---------------------------------------------------------------------
# 1. CGI.pm がいなくても読める
#
# これが目的そのもの。CGI.pm を @INC から隠して、管理画面のモジュール
# が全部読めるかを見る。
# ---------------------------------------------------------------------
subtest 'CGI.pm を隠しても CGI サブシステムが読める' => sub {
    # 子プロセスで走らせる。CGI.pm を隠すのは @INC のフックなので、
    # このプロセスで先に読まれていると隠したことにならない。
    my $script = <<'EOSCRIPT';
BEGIN { unshift @INC, sub { die "hidden\n" if $_[1] eq 'CGI.pm'; return } }
use lib 'fml/lib', 'cpan/lib';
my @f = `find fml/lib/FML/CGI fml/lib/FML/Process/CGI -name '*.pm'`;
chomp @f;
my @bad = ();
for my $p (sort @f) {
    (my $m = $p) =~ s{^fml/lib/}{};
    $m =~ s{/}{::}g;
    $m =~ s/\.pm$//;
    push @bad, $m unless eval "require $m; 1";
}
printf "%d %s", scalar(@bad), join(",", @bad);
EOSCRIPT

    my $tmp = "t/.60_nocgi.$$.pl";
    open(my $wh, '>', $tmp) or plan skip_all => "cannot write $tmp";
    print $wh $script;
    close($wh);

    my $out = `$^X $tmp 2>&1`;
    unlink($tmp);

    my ($bad, $names) = split(/ /, $out, 2);

    is($bad, '0', 'CGI.pm 抜きで CGI サブシステムが全部読める')
	or diag("読めなかったもの: " . ($names || ''));
};


# ---------------------------------------------------------------------
# 2. エスケープ
#
# 高位バイトはそのまま通す。fml8 が渡すのは euc-jp のオクテット列で、
# 文字として扱って実体参照にすると日本語が Latin-1 の名前に化ける。
# ---------------------------------------------------------------------
subtest 'HTML の予約文字だけをエスケープする' => sub {
    is(FML::CGI::Compat::escapeHTML('a & b'), 'a &amp; b',    '&');
    is(FML::CGI::Compat::escapeHTML('<b>'),   '&lt;b&gt;',    '< >');
    is(FML::CGI::Compat::escapeHTML('"x"'),   '&quot;x&quot;','"');
    is(FML::CGI::Compat::escapeHTML("it's"),  'it&#39;s',     "'");

    my $euc = "\xc6\xfc\xcb\xdc\xb8\xec";              # EUC-JP の「日本語」
    is(FML::CGI::Compat::escapeHTML($euc), $euc, 'EUC-JP はそのまま通る');
    is(FML::CGI::Compat::escapeHTML(undef), '',  'undef は空文字');
};


# ---------------------------------------------------------------------
# 3. フォーム部品
# ---------------------------------------------------------------------
subtest 'fml8 が書いている呼び方で正しい HTML が出る' => sub {
    like(FML::CGI::Compat::textfield(-name => 'ml_name', -size => 32),
	 qr{<input type="text" name="ml_name" size="32">}, 'textfield');

    like(FML::CGI::Compat::textfield(-name => 'a', -default => 'v', -maxlength => 8),
	 qr{value="v".*maxlength="8"}, 'textfield の default と maxlength');

    like(FML::CGI::Compat::hidden(-name => 'command', -value => 'close'),
	 qr{<input type="hidden" name="command" value="close">}, 'hidden');

    # CGI.pm はこれを value="" array(0x...) と書く。壊れているのは
    # 向こうなので、そこは真似しない。
    is(FML::CGI::Compat::hidden(-name => 'command', ['']),
       '<input type="hidden" name="command" value="">',
       'hidden に裸のリストを渡しても参照が漏れない');

    like(FML::CGI::Compat::hidden(-name => 'x', -default => [ 'y' ]),
	 qr{value="y"}, 'hidden の default が配列でも読む');

    like(FML::CGI::Compat::submit(-name => '-> close'),
	 qr{type="submit".*value="-&gt; close"}, 'submit の値はエスケープされる');

    like(FML::CGI::Compat::reset(-name => 'reset'),
	 qr{<input type="reset" name="reset" value="reset">}, 'reset');
};


# ---------------------------------------------------------------------
# 4. select
# ---------------------------------------------------------------------
subtest 'popup_menu と scrolling_list' => sub {
    my $p = FML::CGI::Compat::popup_menu(-name => 'order',
					 -values => [ 'asc', 'desc' ]);
    like($p, qr{<select name="order">},        'popup_menu に size はつかない');
    like($p, qr{<option value="asc">asc</option>}, '選択肢');

    my $s = FML::CGI::Compat::scrolling_list(-name    => 'ml_name',
					     -values  => [ 'a', 'b' ],
					     -size    => 5,
					     -default => 'b');
    like($s, qr{<select name="ml_name" size="5">}, 'scrolling_list は size をつける');
    like($s, qr{<option value="b" selected>b</option>}, '既定値が selected');
    unlike($s, qr{<option value="a" selected>}, '他は selected でない');
};


# ---------------------------------------------------------------------
# 5. table / Tr / td
#
# CGI.pm は Tr( undef, ... ) の undef を「属性なし」として読む。
# fml8 の呼び方がそれなので、同じに扱う。
# ---------------------------------------------------------------------
subtest 'フォームを並べる表' => sub {
    is(FML::CGI::Compat::td([ 'a', 'b' ]), '<td>a</td><td>b</td>',
       'td はリストを展開する');
    is(FML::CGI::Compat::Tr(undef, '<td>x</td>'), "<tr><td>x</td></tr>\n",
       'Tr の undef は属性なし');
    like(FML::CGI::Compat::table({ -border => undef }, '<tr></tr>'),
	 qr{^<table>\n}, 'HTML5 に border 属性は無いので落とす');
};


# ---------------------------------------------------------------------
# 6. 文書の枠
#
# CGI.pm が書いていたのは HTML 4.01 Transitional と BGCOLOR。
# <!DOCTYPE html> なら quirks mode に落ちないし、viewport を書かないと
# 携帯で 980px に組んでから縮小されて読めなくなる。
# ---------------------------------------------------------------------
subtest '現代のブラウザが素直に読める枠を出す' => sub {
    my $h = FML::CGI::Compat::start_html(-title   => 'fml & co',
					 -lang    => 'ja',
					 -charset => 'euc-jp');

    like($h, qr{^<!DOCTYPE html>\n}, 'HTML5 の DOCTYPE');
    like($h, qr{<html lang="ja">},   'lang');
    like($h, qr{<meta charset="euc-jp">}, 'charset');
    like($h, qr{name="viewport"},    'viewport');
    like($h, qr{<title>fml &amp; co</title>}, 'title はエスケープされる');

    is(FML::CGI::Compat::end_html(), "</body>\n</html>\n", 'end_html');
};


# ---------------------------------------------------------------------
# 7. フォームの enctype
#
# CGI.pm の start_form() は既定が multipart/form-data。fml8 はファイルを
# 受け取らないので、素直に urlencoded にする。読む側もそれ前提。
# ---------------------------------------------------------------------
subtest 'フォームは urlencoded で出す' => sub {
    my $f = FML::CGI::Compat::start_form(-action => '/x.cgi', -target => '_top');

    like($f, qr{method="post"},   'POST');
    like($f, qr{action="/x\.cgi"}, 'action');
    like($f, qr{target="_top"},   'target');
    like($f, qr{enctype="application/x-www-form-urlencoded"}, 'enctype');
    is(FML::CGI::Compat::end_form(), "</form>\n", 'end_form');
};


# ---------------------------------------------------------------------
# 8. 入力を読む
#
# ここが CGI をモジュールではなくプロトコルとして扱う部分。
# ---------------------------------------------------------------------
subtest 'QUERY_STRING と POST body を読む' => sub {
    my $out = `REQUEST_METHOD=GET QUERY_STRING='ml_name=elena&command=subscribe&x=a%20b&y=a+b' $^X -Ifml/lib -e 'use FML::CGI::Compat; printf "%s|%s|%s|%s|%s", scalar(param("ml_name")), scalar(param("command")), scalar(param("x")), scalar(param("y")), join(",", param())' 2>&1`;

    is($out, 'elena|subscribe|a b|a b|command,ml_name,x,y',
       'GET: %20 も + も空白になり、名前一覧が引ける');

    my $post = `printf 'a=1&b=2' | REQUEST_METHOD=POST CONTENT_LENGTH=7 $^X -Ifml/lib -e 'use FML::CGI::Compat; printf "%s|%s", scalar(param("a")), scalar(param("b"))' 2>&1`;
    is($post, '1|2', 'POST: body から読む');

    my $undef = `REQUEST_METHOD=GET QUERY_STRING='' $^X -Ifml/lib -e 'use FML::CGI::Compat; print defined(param("nope")) ? "defined" : "undef"' 2>&1`;
    is($undef, 'undef', '無い名前は undef');
};


# ---------------------------------------------------------------------
# 9. url() の scheme
#
# http:// 決め打ちで自分の URL を書くと、TLS のサイトでブラウザが
# 平文に降りる。HTTPS 環境変数とポートから決める。
# ---------------------------------------------------------------------
subtest '自分の URL は scheme を決め打ちしない' => sub {
    my $plain = `SERVER_PORT=80 HTTP_HOST=lists.example.jp SCRIPT_NAME=/cgi-bin/fml/admin/menu.cgi $^X -Ifml/lib -e 'use FML::CGI::Compat; print url()' 2>&1`;
    is($plain, 'http://lists.example.jp/cgi-bin/fml/admin/menu.cgi', '平文');

    my $tls = `HTTPS=on SERVER_PORT=443 HTTP_HOST=lists.example.jp SCRIPT_NAME=/x.cgi $^X -Ifml/lib -e 'use FML::CGI::Compat; print url()' 2>&1`;
    is($tls, 'https://lists.example.jp/x.cgi', 'HTTPS=on なら https');

    my $port = `SERVER_PORT=443 HTTP_HOST=lists.example.jp SCRIPT_NAME=/x.cgi $^X -Ifml/lib -e 'use FML::CGI::Compat; print url()' 2>&1`;
    is($port, 'https://lists.example.jp/x.cgi', '443 番でも https');
};


done_testing();

1;
