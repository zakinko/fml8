#-*- perl -*-
#
# どのファイルがどの符号か。
#
# fml8 は EUC-JP で書かれてきた。Unicode に移す途中は EUC-JP と UTF-8 が
# 混ざるので、その間こそ「どちらでもないファイル」が生まれやすい。
# 編集ツールが黙って変換すると、EUC-JP のコメントが UTF-8 の置換文字に
# 化けて、関係のない行まで書き換わる。過去に一度、46 行がそうなった。
#
# ここで見るのは三つ。
#
#   1. すべてのファイルが UTF-8 か EUC-JP のどちらかで読めること
#   2. 置換文字 (U+FFFD) が混じっていないこと
#   3. まだ EUC-JP のものが、EUC-JP でなければならない理由を持つこと
#
# 3 が要るのは、移行が「やり残し」ではなく「意図」であることを
# 記録に残すためである。
#

use strict;
use warnings;
use Test::More;
use Encode qw(decode);

plan skip_all => "run me from the top of the tree" unless -d 'fml/lib';


# Descriptions: git が知っているファイルのうち、非 ASCII を含むもの。
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub interesting_files
{
    my @out = ();

    my @all = `git ls-files 2>/dev/null`;
    chomp @all;
    return \@out unless @all;

    for my $f (@all) {
	# 同梱物と他人のもの、そして画像は対象外。
	next if $f =~ m{^(cpan|gnu|img|3rdparty)/};
	next if $f =~ m{\.(gif|jpg|jpeg|png|pdf|gz|Z)$};
	next unless -f $f;

	open(my $fh, '<', $f) or next;
	binmode($fh);
	local $/ = undef;
	my $buf = <$fh>;
	close($fh);

	next unless defined $buf;
	next unless $buf =~ /[\x80-\xff]/;

	push @out, [ $f, $buf ];
    }

    return \@out;
}


my $files = interesting_files();

plan skip_all => "not a git checkout" unless @$files;


# ---------------------------------------------------------------------
# 1. どちらかで読めること
# ---------------------------------------------------------------------
subtest 'すべて UTF-8 か EUC-JP で読める' => sub {
    my (@utf8, @euc, @bad) = ();

    for my $e (@$files) {
	my ($f, $buf) = @$e;

	# 名前で符号を宣言しているものは、その符号で読めればよい。
	# regress/ の .sjis は Shift_JIS のメールを食わせる試験材料で、
	# EUC-JP でも UTF-8 でも読めないのが正しい。
	if ($f =~ /\.sjis$/) {
	    ok(eval { decode("Shift_JIS", $buf, Encode::FB_CROAK); 1 },
	       "$f は名前どおり Shift_JIS");
	    next;
	}

	my $is_utf8 = eval { decode("UTF-8",   $buf, Encode::FB_CROAK); 1 } ? 1 : 0;
	my $is_euc  = eval { decode("EUC-JP",  $buf, Encode::FB_CROAK); 1 } ? 1 : 0;

	if    ($is_utf8) { push @utf8, $f }
	elsif ($is_euc)  { push @euc,  $f }
	else             { push @bad,  $f }
    }

    is(scalar(@bad), 0, 'どちらでも読めないファイルが無い')
	or diag(join("\n", map { "  $_" } @bad));

    diag(sprintf("UTF-8 %d / EUC-JP %d", scalar(@utf8), scalar(@euc)));

    cmp_ok(scalar(@utf8) + scalar(@euc), '>', 100, '対象がちゃんと集まっている');
};


# ---------------------------------------------------------------------
# 2. 置換文字
#
# U+FFFD は変換が半分だけ進んだ跡である。それ自体は正しい UTF-8 なので、
# 1 の検査は通ってしまう。ここで見ないと誰も気付かない。
# ---------------------------------------------------------------------
subtest '変換に失敗した跡が残っていない' => sub {
    my @bad = ();

    for my $e (@$files) {
	my ($f, $buf) = @$e;
	push @bad, $f if $buf =~ /\xef\xbf\xbd/;
    }

    is(scalar(@bad), 0, 'U+FFFD を含むファイルが無い')
	or diag(join("\n", map { "  $_" } @bad));
};


# ---------------------------------------------------------------------
# 3. EUC-JP のまま残すものには理由がある
#
# 移行が途中で止まっているのではなく、そこは残すと決めた、という記録。
# 理由に当てはまらない EUC-JP が現れたら、それは移行のやり残しである。
# ---------------------------------------------------------------------
subtest 'EUC-JP のまま残すものは、残す理由を持つ' => sub {
    # 理由は三つだけ。
    my @reason = (
	[ qr{^fml/share/message/},
	  'ディレクトリ名が符号そのもの (euc-jp/)。動かすと実行時の挙動が変わる' ],
	[ qr{^fml/etc/},
	  '設定と設定テンプレート。$template_file_charset などと連動する' ],
	[ qr{^(regress/testmails/|regress/base/mime\.pl|regress/ISO2022JP/)},
	  'オクテット列そのものが試験対象' ],
	[ qr{^fml/lib/(Mail/Message/Language/Japanese/Subject|Mail/Bounce/Language/Japanese|FML/Demo/Language/Japanese)\.pm$},
	  '日本語がコード中にある。Subject.pm は Jcode で euc に変換してから照合する' ],
    );

    my @unexplained = ();
    for my $e (@$files) {
	my ($f, $buf) = @$e;

	next if eval { decode("UTF-8", $buf, Encode::FB_CROAK); 1 };
	next unless eval { decode("EUC-JP", $buf, Encode::FB_CROAK); 1 };

	my $why = '';
	for my $r (@reason) {
	    if ($f =~ $r->[ 0 ]) { $why = $r->[ 1 ]; last }
	}

	push @unexplained, $f unless $why;
    }

    is(scalar(@unexplained), 0, '理由の無い EUC-JP が無い')
	or diag("移行のやり残しか、理由を書き足すべきもの:\n" .
		join("\n", map { "  $_" } @unexplained));
};


# ---------------------------------------------------------------------
# 4. コードの中の日本語
#
# 実行される行に日本語があるファイルは、符号を変えると挙動が変わる。
# どれがそうなのかを一覧として固定しておく。
# ---------------------------------------------------------------------
subtest 'コード中に日本語を持つモジュールは分かっている' => sub {
    my %known = map { $_ => 1 } qw(
	fml/lib/Mail/Message/Language/Japanese/Subject.pm
	fml/lib/Mail/Bounce/Language/Japanese.pm
	fml/lib/FML/Demo/Language/Japanese.pm
    );

    my @found = ();
    for my $e (@$files) {
	my ($f, $buf) = @$e;
	next unless $f =~ /\.pm$/;

	for my $line (split(/\n/, $buf)) {
	    next unless $line =~ /[\x80-\xff]/;
	    next if $line =~ /^\s*#/;      # コメント
	    next if $line =~ /^=/;         # POD
	    push @found, $f;
	    last;
	}
    }

    my %seen = ();
    @found = grep { !$seen{ $_ }++ } @found;

    for my $f (@found) {
	ok($known{ $f }, "$f は把握済み")
	    or diag("実行される行に日本語がある。符号を変える前に中身を見ること");
    }

    # 逆向き。一覧に書いてあるものが消えたら一覧を直す。
    for my $f (sort keys %known) {
	ok(-f $f, "$f がまだある") if -e 'fml/lib';
    }
};


done_testing();

1;
