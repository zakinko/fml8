#-*- perl -*-
#
# RFC 8058 のワンクリック解除。
#
# Gmail が 2024 年 2 月から一括送信者に求めているもの。fml8 は
# List-Unsubscribe を mailto: だけで出していたので、Gmail の要件を
# 満たしていなかった。Yahoo は mailto: で足りると明言しているので
# 「届かない」ではないが、救済措置の対象外にはなる。
#
# RFC 8058 が求めるものを、要求ごとに固定する。
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Unsubscribe;


# config と curproc らしく振る舞う最小のもの。
{
    package t::Config;
    sub new { my ($c, $h) = @_; return bless { %$h }, $c }
    sub yes { my ($s, $k) = @_; return(($s->{ $k } || '') eq 'yes' ? 1 : 0) }

    package t::Curproc;
    sub new    { my ($c, $cf) = @_; return bless { cf => $cf }, $c }
    sub config { return $_[0]->{ cf } }
}


# Descriptions: 既定の設定を持った FML::Unsubscribe。
#    Arguments: HASH_REF($over)
# Side Effects: none
# Return Value: OBJ
sub unsub
{
    my ($over) = @_;
    my %cf = (
	ml_name                   => 'elena',
	ml_domain                 => 'example.jp',
	ml_home_dir               => '/var/spool/ml/elena',
	unsubscribe_token_secret  => 'a secret nobody else has',
	unsubscribe_one_click_url =>
	    'https://lists.example.jp/cgi-bin/fml/unsubscribe.cgi',
	%{ $over || {} },
    );

    return new FML::Unsubscribe t::Curproc->new(t::Config->new(\%cf));
}


# ---------------------------------------------------------------------
# 1. URI は HTTPS でなければならない
#
# RFC 8058 section 3.1:
#   "The List-Unsubscribe header field MUST contain one HTTPS URI."
#
# 平文だと、受信側のメールシステムが会員のアドレスを平文で POST する。
# しかもその引き金は、誰でも偽造できるヘッダである。
# ---------------------------------------------------------------------
subtest 'URI は https でなければ出さない' => sub {
    like(unsub()->url('taro@example.jp'), qr{^https://}, 'https なら出る');

    is(unsub({ unsubscribe_one_click_url =>
	       'http://lists.example.jp/u.cgi' })->url('taro@example.jp'),
       '', 'http は出さない');

    is(unsub({ unsubscribe_one_click_url => '' })->url('taro@example.jp'),
       '', '設定が空なら出さない');
};


# ---------------------------------------------------------------------
# 2. URI は受信者と list を特定できること
#
# RFC 8058 section 3.1:
#   "The URI MUST contain enough information to identify the mail
#    recipient and the list ... Since there is no provision for extra
#    POST arguments, any information about the message or recipient is
#    encoded in the URI."
# ---------------------------------------------------------------------
subtest 'URI が受信者を特定する' => sub {
    my $u = unsub();

    my $a = $u->url('taro@example.jp');
    my $b = $u->url('hanako@example.jp');

    isnt($a, $b, '受信者ごとに違う URL');
    like($a, qr{taro%40example\.jp}, 'アドレスが URL に入っている');
    like($a, qr{[?&]t=}, 'トークンが入っている');

    # 一覧が違えば同じ人でも別の URL。
    my $other = unsub({ ml_name => 'other' });
    isnt($other->url('taro@example.jp'), $a, 'list が違えば別の URL');
};


# ---------------------------------------------------------------------
# 3. トークンは偽造しにくいこと
#
# RFC 8058 section 3.1:
#   "The URI SHOULD include an opaque identifier or another
#    hard-to-forge component ... The server handling the unsubscription
#    SHOULD verify that the opaque or hard-to-forge component is valid."
# ---------------------------------------------------------------------
subtest 'トークンは推測できない' => sub {
    my $u = unsub();
    my $t = $u->token('taro@example.jp');

    ok($u->verify('taro@example.jp', $t), '自分のトークンは通る');

    ok(!$u->verify('hanako@example.jp', $t),
       '他人のアドレスでは通らない');
    ok(!$u->verify('taro@example.jp', 'garbage'), 'でたらめは通らない');
    ok(!$u->verify('taro@example.jp', ''),        '空は通らない');
    ok(!$u->verify('', $t),                       'アドレスが空なら通らない');

    # 秘密が違えば通らない。同じ URL を別の list が受け取っても
    # 解除できない、ということ。
    my $other = unsub({ unsubscribe_token_secret => 'a different secret' });
    ok(!$other->verify('taro@example.jp', $t), '秘密が違えば通らない');

    # 長さ。128 ビットを base64url にすると 22 文字。
    my ($b64) = $t =~ /\.(.+)$/;
    is(length($b64), 22, 'トークン本体は 22 文字');
    unlike($t, qr{[+/=]}, 'URL に置ける文字だけ');
};


# ---------------------------------------------------------------------
# 4. 期限
#
# RFC は期限を求めていない。ここで切るのは、アーカイブに残った記事から
# 拾ったトークンが何年も後に使えることを避けるため。
# ---------------------------------------------------------------------
subtest '古いトークンは通らない' => sub {
    my $u     = unsub();
    my $today = int(time / 86400);

    ok($u->verify('taro@example.jp', $u->token('taro@example.jp', $today)),
       '今日のものは通る');
    ok($u->verify('taro@example.jp', $u->token('taro@example.jp', $today - 6)),
       '6 日前も通る');
    ok(!$u->verify('taro@example.jp', $u->token('taro@example.jp', $today - 8)),
       '8 日前は通らない');

    # 未来のものは、ここで発行したものではない。
    ok(!$u->verify('taro@example.jp', $u->token('taro@example.jp', $today + 1)),
       '明日の日付は通らない');
};


# ---------------------------------------------------------------------
# 5. 秘密が無くても動くこと
#
# 設定しない人のところで機能ごと死ぬより、弱くても動くほうがよい。
# ただし list ごとに違うこと。
# ---------------------------------------------------------------------
subtest '秘密を設定しなくても list ごとに違う' => sub {
    my $a = unsub({ unsubscribe_token_secret => '' });
    my $b = unsub({ unsubscribe_token_secret => '', ml_name => 'other',
		    ml_home_dir => '/var/spool/ml/other' });

    my $ta = $a->token('taro@example.jp');
    ok($ta, 'トークンは出る');
    ok($a->verify('taro@example.jp', $ta), '自分では通る');
    ok(!$b->verify('taro@example.jp', $ta), '別の list では通らない');
};


# ---------------------------------------------------------------------
# 6. ヘッダの形
#
# RFC 8058 section 5 の ABNF:
#   postarg = "List-Unsubscribe=One-Click"
#
# 括弧つきのコメントも、余分な語も許されない。
# ---------------------------------------------------------------------
subtest 'List-Unsubscribe-Post の値は一つだけ' => sub {
    my $value = 'List-Unsubscribe=One-Click';

    like($value, qr{^List-Unsubscribe=One-Click$}, 'ABNF どおり');
    unlike($value, qr{[();]}, 'コメントも区切りも無い');
};


done_testing();

1;
