#-*- perl -*-
#
# RFC 5322 の group 構文。
#
#   group = display-name ":" [group-list] ";" [CFWS]      (section 3.4)
#
# 拡張ではなく本体の文法である。Mail::Address はこれを実装しておらず、
#
#   friends: taro@example.jp, hanako@example.jp;
#
# を二つに割ったうえで両方を壊す — 一つ目に group 名が残り、
# 二つ目に終端の ; が残る。
#
# fml8 はアドレスの一致で会員かどうかを決めるので、どちらも誰にも
# 一致しない。その宛先で投稿すると、会員が非会員として扱われる。
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Address;
use Mail::Message::Address;


# Descriptions: parse して修復したあとのアドレス一覧。
#    Arguments: STR($s)
# Side Effects: none
# Return Value: ARRAY_REF
sub parse
{
    my ($s) = @_;
    my @a = Mail::Address->parse($s);

    Mail::Message::Address::_repair_group_syntax(\@a);

    return [ map { $_->address } @a ];
}


# ---------------------------------------------------------------------
# 1. 壊れていたことの証拠
#
# 直す前が本当に壊れていたかを、修復を通さない生の Mail::Address で
# 確かめる。「たぶん壊れている」で直さない。
# ---------------------------------------------------------------------
subtest 'Mail::Address は group 構文を壊す' => sub {
    my $in = 'friends: taro@example.jp, hanako@example.jp;';
    my @raw = Mail::Address->parse($in);
    my @got = map { $_->address } @raw;

    diag(sprintf("Mail::Address %s -> %s",
		 $Mail::Address::VERSION || '?', join(", ", @got)));

    # XXX 壊れ方は版で違う。1.17 は group 名も終端の ; も残し、2.21 は
    # XXX ; を落として group 名だけ残す。だから「どう壊れるか」ではなく
    # XXX 「正しくない」ことだけを固定する。他人のモジュールの壊れ方を
    # XXX 字面で書くと、その版を上げただけでテストが落ちる。
    my @want = ( 'taro@example.jp', 'hanako@example.jp' );

    isnt(join(",", @got), join(",", @want),
	 'そのままでは正しい二つにならない');

    # 少なくとも一つは会員名簿と一致しない、というのが実害の形。
    my %want = map { $_ => 1 } @want;
    my @miss = grep { !$want{ $_ } } @got;

    cmp_ok(scalar(@miss), '>', 0, '名簿と一致しないものが出る')
	or diag("この版では壊れていない。修復は無害なので落とさなくてよいが、" .
		"同梱の Mail::Address が直ったなら 3 番の subtest で足りる");
};


# ---------------------------------------------------------------------
# 2. 直したあと
# ---------------------------------------------------------------------
subtest 'group 構文から素のアドレスが取れる' => sub {
    is_deeply(parse('friends: taro@example.jp, hanako@example.jp;'),
	      [ 'taro@example.jp', 'hanako@example.jp' ],
	      '二つとも素のアドレスになる');

    is_deeply(parse('friends: a@x.jp;'), [ 'a@x.jp' ], '一人だけの group');

    is_deeply(parse('A Group: a@x.jp, b@y.jp; c@z.jp'),
	      [ 'a@x.jp', 'b@y.jp', 'c@z.jp' ],
	      'group のあとに続くアドレス');

    # 空の group。RFC 5322 が明示的に許している形で、Bcc の常套句。
    is_deeply(parse('undisclosed-recipients:;'), [],
	      '空の group からはアドレスが出ない');
};


# ---------------------------------------------------------------------
# 3. group でないものを壊していないこと
#
# 修復は local part のコロンと domain の末尾のセミコロンを削る。
# どちらも RFC 5322 の atext / domain には現れないので、普通の
# アドレスには当たらない。当たっていないことを確かめる。
# ---------------------------------------------------------------------
subtest 'group でないアドレスはそのまま' => sub {
    my @same = (
	'taro@example.jp',
	'Taro Yamada <taro@example.jp>',
	'"Yamada, Taro" <taro@example.jp>',
	'taro+fml@example.jp',
	'taro.yamada@sub.example.co.jp',
	'a@[192.0.2.1]',
	'"very.unusual.@.unusual.com"@example.jp',
    );

    for my $s (@same) {
	my $got = parse($s);
	is(scalar(@$got), 1, "$s : 一件のまま");
	like($got->[ 0 ], qr/\@/, "$s : @ を持ったまま")
	    if @$got;
	unlike($got->[ 0 ], qr/^;|;$/, "$s : ; が付いていない")
	    if @$got;
    }
};


# ---------------------------------------------------------------------
# 4. 複数のアドレスを並べた普通の場合
# ---------------------------------------------------------------------
subtest '普通の複数アドレス' => sub {
    is_deeply(parse('a@x.jp, b@y.jp'), [ 'a@x.jp', 'b@y.jp' ], '二つ');
    is_deeply(parse('Taro <a@x.jp>, Hanako <b@y.jp>'),
	      [ 'a@x.jp', 'b@y.jp' ], '表示名つき二つ');
};


# ---------------------------------------------------------------------
# 5. Mail::Message::Address 経由でも同じ
#
# fml8 が実際に使う入口。
# ---------------------------------------------------------------------
subtest 'Mail::Message::Address からも正しく取れる' => sub {
    my $obj = new Mail::Message::Address 'friends: taro@example.jp;';

    is($obj->address(), 'taro@example.jp', 'address() が素のアドレス');

    my $plain = new Mail::Message::Address 'Taro <taro@example.jp>';
    is($plain->address(), 'taro@example.jp', '普通のアドレスも従来どおり');
};


done_testing();

1;
