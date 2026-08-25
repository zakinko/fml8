#-*- perl -*-
#
# 文書が指している先が実在するか。
#
# fml/doc/ja/tutorial の中身は 2001〜2008 年のもので、2018 年に触られて
# いるが commit の件名はすべて "reviewed. alignment cosmetics." — 整形
# である。その間にクラス構成は変わっており、文書だけが古い名前を指した
# まま残っている。
#
# .github の module-paths ジョブはこれを拾えない。あれが探すのは
# "X/Y.pm" の形をした文字列で、文書に書いてあるのはクラス名だから。
#
# 見つかったものは TODO として固定してある。直すのは overhaul の
# 仕事で、ここでの仕事は「どれが嘘か」を数えて見えるようにすること。
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

plan skip_all => "run me from the top of the tree" unless -d 'fml/doc/ja';


# Descriptions: fml/lib と img/lib にあるクラス名。
#    Arguments: none
# Side Effects: none
# Return Value: HASH_REF
sub known_classes
{
    my %known = ();

    my @f = `find fml/lib img/lib 3rdparty -name '*.pm' -type f 2>/dev/null`;
    chomp @f;

    for my $p (@f) {
	my $n = $p;
	$n =~ s{^(fml|img)/lib/}{};
	$n =~ s{^3rdparty/[^/]+/lib/}{};
	$n =~ s{/}{::}g;
	$n =~ s{\.pm$}{};
	$known{ $n } = 1;

	# 名前空間そのものへの言及も本文には出る。
	my @part = split(/::/, $n);
	for my $i (1 .. $#part) {
	    $known{ join('::', @part[ 0 .. $i - 1 ]) } = 1;
	}
    }

    # 同梱の CPAN も実在する。
    my @c = `find cpan/lib -name '*.pm' -type f 2>/dev/null`;
    chomp @c;
    for my $p (@c) {
	my $n = $p;
	$n =~ s{^cpan/lib/}{};
	$n =~ s{/}{::}g;
	$n =~ s{\.pm$}{};
	$known{ $n } = 1;
    }

    return \%known;
}


# Descriptions: 文書が名指ししているクラスと、その出どころ。
#    Arguments: ARRAY_REF($dirs)
# Side Effects: none
# Return Value: HASH_REF
sub referenced_classes
{
    my ($dirs) = @_;
    my %ref = ();

    my @f = ();
    for my $d (@$dirs) {
	next unless -d $d;
	my @x = `find $d -type f \\( -name '*.sgml' -o -name '*.txt' \\) 2>/dev/null`;
	chomp @x;
	push @f, @x;
    }

    for my $p (@f) {
	open(my $fh, '<', $p) or next;
	binmode($fh);
	my $ln = 0;
	while (my $line = <$fh>) {
	    $ln++;
	    while ($line =~ /(?<![\w:])((?:FML|Mail|IO|Tie)(?:::[A-Za-z][A-Za-z0-9_]*)+)/g) {
		push @{ $ref{ $1 } }, "$p:$ln";
	    }
	}
	close($fh);
    }

    return \%ref;
}


my $known = known_classes();

plan skip_all => "no modules found" unless keys %$known > 50;


# ---------------------------------------------------------------------
# 1. 走査そのものが効いているか
#
# 何も見つけない検査は、いつでも通る。
# ---------------------------------------------------------------------
subtest '走査が文書からクラス名を拾えている' => sub {
    my $ref = referenced_classes([ 'fml/doc/ja/tutorial' ]);

    cmp_ok(scalar(keys %$ref), '>', 50, '50 種より多く拾えている');
    ok($ref->{ 'FML::Process::Kernel' } || $ref->{ 'FML::Config' },
       '中心のクラスが出てくる');
};


# ---------------------------------------------------------------------
# 2. 指している先が実在するか
#
# いま 17 種が実在しない。CGI の章と lock の章が、存在しないクラス
# 構成を説明している。読んだ人がその名前を探しても見つからない。
# ---------------------------------------------------------------------
subtest '文書が実在するクラスを指している' => sub {
    my $ref  = referenced_classes([ 'fml/doc/ja/tutorial' ]);
    my @dead = grep { !$known->{ $_ } } sort keys %$ref;

    {
	local $TODO = 'issue #1: 2001-2008 年の記述が現在のクラス構成を' .
		      '指していない。fml/doc/ja/design/document-overhaul.txt';
	is(scalar(@dead), 0, '実在しないクラスを指していない');
    }

    diag(sprintf("実在しない %d 種:", scalar(@dead)));
    for my $n (@dead) {
	diag(sprintf("  %-36s %s", $n, $ref->{ $n }->[ 0 ]));
    }

    # 増えていないこと。overhaul が進めば減るので、そのときは下げる。
    cmp_ok(scalar(@dead), '<=', 20, '実在しない参照が増えていない');
};


# ---------------------------------------------------------------------
# 3. 文書が組み上がる道が通っているか
#
# 中身が古いことより先に、そもそも生成できないという問題があった。
# sgml_compile.sh が openjade を /usr/pkg/bin に決め打ちしていたため、
# pkgsrc の無い機械では必ず "not found" で止まる。
# ---------------------------------------------------------------------
subtest '文書を組む道具を PATH から探す' => sub {
    my $sh = 'fml/utils/bin/sgml_compile.sh';

    plan skip_all => "no $sh" unless -f $sh;

    open(my $fh, '<', $sh) or plan skip_all => "cannot read $sh";
    local $/ = undef;
    my $buf = <$fh>;
    close($fh);

    unlike($buf, qr{/usr/pkg/bin/openjade},
	   'openjade を絶対パスで決め打ちしていない');
    unlike($buf, qr{/usr/pkg/bin/lynx}, 'lynx も');
    unlike($buf, qr{/usr/pkg/bin/w3m},  'w3m も');

    like($buf, qr{PATH}, 'PATH を見ている');
    like($buf, qr{apt install|pkg_add|brew install},
	 '足りないときに何を入れればよいか言う');
};


done_testing();

1;
