#-*- perl -*-
#
# List-* ヘッダを RFC 2369 に沿わせる。
#
# RFC 2369 section 2 は、山括弧で始まらないフィールドを
# 「クライアントは無視すべき」と定めている:
#
#   "if the content of the field (following any leading whitespace,
#    including comments) begins with any character other than the
#    opening angle bracket '<', the field SHOULD be ignored."
#
# fml8 は設定が空のとき 'unavailable' や 'maintainer'、そして
# "contact maintainer <addr>" — コメントが括弧より前に来る形 — を
# 入れていた。どれも読み手に捨てられるので、リストは何も言っていない
# のと同じで、しかも何か言ったように見える。
#
# RFC 2369 が「投稿できない」を表す形は決まっている:
#
#   List-Post: NO (posting not allowed on this list)
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Header;
use FML::Header;

# _get_header_type() は $rw_args から "article_header" などを組み立てる。
# ここで見たいのは値の作り方なので、種別は固定してよい。
{
    no warnings 'redefine';
    *FML::Header::_get_header_type = sub { return 'article_header' };
}


# Descriptions: $config を渡して List-* を書かせ、結果を引く。
#    Arguments: HASH_REF($cf)
# Side Effects: none
# Return Value: HASH_REF
sub emit
{
    my ($cf) = @_;

    my $header = new Mail::Header [ "Subject: test\n" ];
    bless $header, 'FML::Header';

    FML::Header::add_rfc2369($header, $cf, { type => '' });

    my %out = ();
    for my $f (qw(List-Id List-Owner List-Post List-Help
		  List-Subscribe List-Unsubscribe List-Archive)) {
	# Mail::Header は無いヘッダに undef ではなく空文字を返す。
	my $v = $header->get($f);
	next unless defined $v;
	chomp $v;
	next unless length $v;
	$out{ $f } = $v;
    }

    return \%out;
}


# config らしく振る舞う最小のもの。yes() だけ要る。
{
    package t::Config;
    sub new  { my ($c, $h) = @_; return bless { %$h }, $c }
    sub yes  { my ($s, $k) = @_; return(($s->{ $k } || '') eq 'yes' ? 1 : 0) }
}


# ---------------------------------------------------------------------
# 1. 何も設定されていないとき
#
# ここが今回直すところ。読み手に捨てられる文字列を書かない。
# ---------------------------------------------------------------------
subtest '設定が空なら、読まれないフィールドを書かない' => sub {
    my $out = emit(t::Config->new({
	ml_name   => 'elena',
	ml_domain => 'example.jp',
    }));

    ok($out->{'List-Id'}, 'List-Id は ml_name と ml_domain から作れる');
    like($out->{'List-Id'}, qr{<elena\.example\.jp>}, 'RFC 2919 の形');

    ok(!exists $out->{'List-Owner'},       'maintainer が無ければ List-Owner を書かない');
    ok(!exists $out->{'List-Help'},        'コマンドが無ければ List-Help を書かない');
    ok(!exists $out->{'List-Subscribe'},   '同 List-Subscribe');
    ok(!exists $out->{'List-Unsubscribe'}, '同 List-Unsubscribe');
    ok(!exists $out->{'List-Archive'},     'アーカイブが無ければ書かない');

    # 書かないのではなく、RFC の定めた形で「投稿不可」と言う。
    is($out->{'List-Post'}, 'NO (posting not allowed on this list)',
       '投稿先が無いときは List-Post: NO');
};


# ---------------------------------------------------------------------
# 2. 書いたものは必ず < で始まる
#
# RFC 2369 section 2 の規則そのもの。List-Post: NO と List-Id は
# 別の RFC / 別の規定なので対象外。
# ---------------------------------------------------------------------
subtest '書いたフィールドは山括弧で始まる' => sub {
    # 実際の default_config.cf は article_header_list_* に
    # <mailto:...> の形をあらかじめ入れている。ここもそれに合わせる。
    my $out = emit(t::Config->new({
	ml_name                   => 'elena',
	ml_domain                 => 'example.jp',
	maintainer                => 'elena-admin@example.jp',
	article_post_address      => 'elena@example.jp',
	command_mail_address      => 'elena-ctl@example.jp',
	use_command_mail_function => 'yes',
	html_archive_url          => 'https://example.jp/ml/elena/',

	article_header_list_post        => '<mailto:elena@example.jp>',
	article_header_list_help        => '<mailto:elena-ctl@example.jp?body=help>',
	article_header_list_subscribe   => '<mailto:elena-ctl@example.jp?body=subscribe>',
	article_header_list_unsubscribe => '<mailto:elena-ctl@example.jp?body=unsubscribe>',
	article_header_list_owner       => '<mailto:elena-admin@example.jp>',
    }));

    for my $f (qw(List-Owner List-Post List-Help
		  List-Subscribe List-Unsubscribe List-Archive)) {
	ok($out->{ $f }, "$f が出る");
	like($out->{ $f }, qr{^\s*<}, "$f は '<' で始まる")
	    if $out->{ $f };
    }

    like($out->{'List-Archive'}, qr{<https://example\.jp/ml/elena/>},
	 'List-Archive はアーカイブの URL');
};


# ---------------------------------------------------------------------
# 3. 直す前が本当に壊れていたか
#
# 「たぶん壊れている」で直さない。旧実装が書いていた値を、RFC 2369 の
# 規則にかけて確かめる。
# ---------------------------------------------------------------------
subtest '旧実装が書いていた値は、規則により捨てられる' => sub {
    my @old = (
	[ 'unavailable',                        'List-Post / List-Help の旧既定' ],
	[ 'maintainer',                         'List-Owner の旧既定'            ],
	[ 'contact maintainer <a@example.jp>',  'maintainer がある場合の旧既定'  ],
    );

    for my $o (@old) {
	my ($value, $what) = @$o;
	unlike($value, qr{^\s*<}, "$what は '<' で始まらない -> 無視される");
    }

    # 念のため、いま書く値は通る。
    like('<mailto:a@example.jp>', qr{^\s*<}, 'いまの形は通る');
};


# ---------------------------------------------------------------------
# 4. 空のフィールドを書かない
#
# RFC 2369 section 3 は各フィールドを 1 通に 1 つまでとしか言っておらず、
# 中身の無いフィールドを求めてはいない。
# ---------------------------------------------------------------------
subtest '値が無いフィールドはヘッダに現れない' => sub {
    my $out = emit(t::Config->new({
	ml_name   => 'elena',
	ml_domain => 'example.jp',
    }));

    for my $f (sort keys %$out) {
	isnt($out->{ $f }, '', "$f が空文字で出ていない");
    }
};


done_testing();

1;
