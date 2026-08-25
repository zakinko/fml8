#-*- perl -*-
#
# 配線が繋がっているか — fml/etc/modules と install.cf の突き合わせ。
#
# fml8 は「実行ファイル名 → クラス名」を fml/etc/modules で引く。この表と
# 実際のクラスは誰も突き合わせていないので、クラスが無い行があっても
# インストールは成功し、その名前を叩いた人だけが起動時に落ちる。
#
# 実際に 2 件あった。fmlserv は install.cf.in が作るのに
# FML::Process::ListServer が fml/lib に無い — fml4 の libexec/fmlserv.pl は
# 実在するので、移植されないまま配線だけ残ったもの。remind の方は
# fml8 にも fml4 にも実体が無く、install.cf.in にだけ名前がある。
#
# どちらもインストールは成功する。叩いた人だけが落ちる。
#
# .github の module-paths ジョブはこれを拾えない。あれが探すのは
# "X/Y.pm" の形をした文字列で、fml/etc/modules に書いてあるのは
# クラス名だから。
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

plan skip_all => "run me from the top of the tree" unless -f 'fml/etc/modules';


# Descriptions: 実行ファイル名 => クラス名 を fml/etc/modules から読む。
#    Arguments: none
# Side Effects: none
# Return Value: HASH_REF
sub module_map
{
    my %map = ();

    open(my $fh, '<', 'fml/etc/modules') or return \%map;
    while (my $line = <$fh>) {
	next if $line =~ /^\s*#/;
	next if $line =~ /^\s*$/;

	my ($name, $class) = split(/\s+/, $line);
	next unless defined $class;
	next unless $class =~ /^[A-Z]/;

	$map{ $name } = $class;
    }
    close($fh);

    return \%map;
}


my $map = module_map();


# ---------------------------------------------------------------------
# 1. 表そのものが読めること
# ---------------------------------------------------------------------
subtest 'fml/etc/modules が読めて、行が揃っている' => sub {
    cmp_ok(scalar(keys %$map), '>', 20, '20 行より多い');

    for my $name (sort keys %$map) {
	like($map->{ $name }, qr/^(FML|Mail|IM)::/,
	     "$name のクラス名が名前空間から始まる");
    }
};


# ---------------------------------------------------------------------
# 2. 名指しされたクラスがファイルとして実在すること
#
# ここが fmlserv で落ちる。TODO で可視化する — 隠すと、また誰も
# 気付かないまま次の版が出る。
# ---------------------------------------------------------------------
subtest '名指しされたクラスがツリーにある' => sub {
    # fml4 の libexec/fmlserv.pl は実在する。fml8 に移植されていない。
    my %not_ported = (
	'FML::Process::ListServer' =>
	    'fml4 の fmlserv が fml8 に移植されていない',
    );

    my %seen = ();
    for my $name (sort keys %$map) {
	my $class = $map->{ $name };
	next if $seen{ $class }++;

	(my $file = $class) =~ s{::}{/}g;
	my $found = 0;
	for my $dir (qw(fml/lib img/lib 3rdparty/demo/lib)) {
	    $found = 1 if -f "$dir/$file.pm";
	}

	if ($not_ported{ $class }) {
	    local $TODO = $not_ported{ $class };
	    ok($found, "$class がある");
	}
	else {
	    ok($found, "$class がある")
		or diag("fml/etc/modules が $name => $class と書いているが、" .
			"そのファイルが無い");
	}
    }
};


# ---------------------------------------------------------------------
# 3. インストールされる実行ファイルが表に載っていること
#
# 逆向き。install.cf.in が作るのに表に無ければ、その名前は
# 起動時にクラスを引けない。
# ---------------------------------------------------------------------
subtest 'インストールされる名前が表に載っている' => sub {
    plan skip_all => "no install.cf.in" unless -f 'fml/etc/install.cf.in';

    open(my $fh, '<', 'fml/etc/install.cf.in') or plan skip_all => "cannot read";
    my $buf = do { local $/ = undef; <$fh> };
    close($fh);

    # libexec_programs の中身。ここが「起動されうる名前」の一覧で、
    # bin_programs の方は loader への symlink なので表を引かない。
    my ($block) = $buf =~ /libexec_programs\s*=\s*(.*?)(?:\n\s*\n|\z)/s;
    plan skip_all => "no libexec_programs" unless defined $block;

    my @name = grep { /^[a-z][a-z0-9._]*$/ }
               map  { my $x = $_; $x =~ s/^\s+//; $x =~ s/\s+$//; $x }
               split(/\s+/, $block);

    cmp_ok(scalar(@name), '>', 5, '実行ファイルが列挙されている')
	or diag("読めた名前: @name");

    for my $n (sort @name) {
	# remind は fml8 にも fml4 にも実体が無い。install.cf.in が
	# この名前を作るだけで、クラスの割り当ても実装も無い。
	my %not_ported = (remind => 'remind は install.cf.in にしか無い');

	if ($not_ported{ $n }) {
	    local $TODO = $not_ported{ $n };
	    ok($map->{ $n }, "$n が fml/etc/modules にある");
	}
	else {
	    ok($map->{ $n }, "$n が fml/etc/modules にある")
		or diag("install.cf.in が $n を作るのに、クラスの割り当てが無い");
	}
    }
};


done_testing();

1;
