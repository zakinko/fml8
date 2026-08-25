#-*- perl -*-
#
# MTA が受け取らなかったときの退避。
#
# Mail::Delivery::SMTP::_fallback_into_queue() は、配送に失敗した記事を
# キューに入れて後で送り直すための関数である。その関数が、キューに
# 入れる前に落ちていた。
#
#     my $queue       = $args->{ queue } || undef;
#     my $retry_count = $queue->get_retry_count() || 0;   # ここ
#
# $args->{queue} は「この配送が出てきたキュー」で、再送のときにしか
# 渡されない。初回配送 — FML::Process::Distribute::_deliver_article()
# がそのまま配る経路 — では undef で、同じ関数が二行あとに
#
#     $curproc->lock($lock_channel) unless defined $queue;
#
# と書いていて、undef になる経路があることをコード自身が認めている。
#
# つまり「MTA が落ちている初回配送」で退避関数が死ぬ。記事は
# キューに入らず失われる。出るのは MTA が落ちているときなので、
# いちばん困る場面である。
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Delivery::SMTP;


# Descriptions: ログと外部依存を黙らせた SMTP オブジェクト。
#    Arguments: NUM($in_queue) NUM($pos) NUM($retry)
# Side Effects: replace methods in Mail::Delivery::SMTP.
# Return Value: OBJ
sub fake_smtp
{
    my ($in_queue, $pos) = @_;
    my $smtp = bless {}, 'Mail::Delivery::SMTP';

    no warnings 'redefine';
    no strict 'refs';
    for my $m (qw(log logdebug logerror)) {
	*{"Mail::Delivery::SMTP::$m"} = sub { 1 };
    }
    # 名前を一度しか使わない警告を黙らせる。差し替えが目的なので。
    no warnings q(once);
    *Mail::Delivery::SMTP::set_not_done     = sub { $_[0]->{ _not_done } = 1 };
    *Mail::Delivery::SMTP::_is_map_in_queue = sub { $in_queue };
    *Mail::Delivery::SMTP::get_map_position = sub { $pos };

    return $smtp;
}


# 再送のときに渡ってくるキューの代わり。
{
    package t::Queue;
    sub new             { my ($c, $n) = @_; return bless { n => $n }, $c }
    sub get_retry_count { return $_[0]->{ n } }
}


# ---------------------------------------------------------------------
# 1. 初回配送 — キューが無いとき
#
# ここが直すところ。落ちないこと、そして退避に進むこと。
# ---------------------------------------------------------------------
subtest 'キューが無くても退避関数が生きている' => sub {
    my $smtp = fake_smtp(0, 0);

    my $ok = eval {
	$smtp->_fallback_into_queue({}, 'file:/nonexistent', '451 busy');
	1;
    };

    ok($ok, '落ちない') or diag("死因: $@");
    unlike($@ || '', qr/get_retry_count/, 'undef に get_retry_count を呼ばない');

    # 退避に進んだこと。set_not_done() は「退避しない」と決めたときに
    # だけ呼ばれるので、呼ばれていなければ落ちずに先へ行っている。
    ok(!$smtp->{ _not_done }, '「退避しない」と判断していない');
};


# ---------------------------------------------------------------------
# 2. 再送のとき — 元の判断を変えていないこと
#
# キューにあり、再送回数があり、位置が 0 なら、そのキューをそのまま
# 残す。ここは触っていない。
# ---------------------------------------------------------------------
subtest '再送中の判断は変わっていない' => sub {
    my $smtp = fake_smtp(1, 0);

    my $ok = eval {
	$smtp->_fallback_into_queue({ queue => t::Queue->new(3) },
				    'file:/nonexistent', '451 busy');
	1;
    };

    ok($ok, '落ちない');
    ok($smtp->{ _not_done },
       'キュー内・再送あり・位置 0 なら退避せずそのまま残す');
};


# ---------------------------------------------------------------------
# 3. キューはあるが、まだ再送していないとき
# ---------------------------------------------------------------------
subtest '再送回数 0 のキューでは退避に進む' => sub {
    my $smtp = fake_smtp(1, 0);

    my $ok = eval {
	$smtp->_fallback_into_queue({ queue => t::Queue->new(0) },
				    'file:/nonexistent', '451 busy');
	1;
    };

    ok($ok, '落ちない');
    ok(!$smtp->{ _not_done }, '退避に進む');
};


# ---------------------------------------------------------------------
# 4. 位置が 0 でないとき
# ---------------------------------------------------------------------
subtest '途中まで配れていたら退避に進む' => sub {
    my $smtp = fake_smtp(1, 42);

    my $ok = eval {
	$smtp->_fallback_into_queue({ queue => t::Queue->new(3) },
				    'file:/nonexistent', '451 busy');
	1;
    };

    ok($ok, '落ちない');
    ok(!$smtp->{ _not_done }, '残りを退避する');
};


done_testing();

1;
