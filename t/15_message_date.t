#-*- perl -*-
#
# FML::Message::Date.
#
# This module writes the Date: header on every article fml8 sends, the
# timestamps in every log line, and the YYYYMMDD names the spool and the
# archive are laid out under.  It had no tests.
#
# It has two documented ways of being read, and they disagreed.  Its own
# SYNOPSIS says
#
#	$date = new FML::Message::Date time;
#	$date->{ log_file_style }
#	$date->log_file_style
#
# The hash form held what _date() built for the time given to new().
# The method form recomputes from "$time || $self->{ _default_unixtime }
# || time", and new() never set that key -- only set() did -- so every
# accessor silently answered for the current time instead.  Passing a
# time to the constructor therefore did nothing at all.
#
# Everything below fixes a time and asserts against it, which is the
# only way that class of defect shows up: an accessor that always
# returns "now" looks perfectly correct in a test that also uses "now".
#

use strict;
use warnings;
use Test::More;
use POSIX ();

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Message::Date;

# 2001-09-09 01:46:40 UTC.  A round number, and far enough from now that
# "now" cannot be mistaken for it.
my $T = 1_000_000_000;

# What that instant is in the local zone, which is what the module uses.
my @L = localtime($T);
my $Y = 1900 + $L[5];
my $M = $L[4] + 1;
my $D = $L[3];


# ---------------------------------------------------------------------
# 1. the constructor remembers the time it was given
#
# The defect, stated directly.
# ---------------------------------------------------------------------
subtest 'new($time) is a date for $time, not for now' => sub {
    my $d = FML::Message::Date->new($T);

    is($d->as_unixtime(), $T, 'as_unixtime() is the time given');
    is($d->YYYYMMDD(), sprintf("%04d%02d%02d", $Y, $M, $D),
       'YYYYMMDD() is that day');

    isnt($d->YYYYMMDD(), FML::Message::Date->new()->YYYYMMDD(),
	 'and it is not today');
};


# ---------------------------------------------------------------------
# 2. the two documented ways of reading it agree
#
# The hash form was right and the method form was wrong, so a test that
# used only one of them would have passed either way.
# ---------------------------------------------------------------------
subtest 'the hash form and the method form agree' => sub {
    my $d = FML::Message::Date->new($T);

    for my $style (qw(log_file_style mail_header_style YYYYMMDD
		      current_time precise_current_time)) {
	is($d->$style(), $d->{ $style }, "$style: method eq hash");
    }
};


# ---------------------------------------------------------------------
# 3. each style is the shape its consumer parses
#
# These are not free choices: the Date: header has to be RFC 5322, and
# the log timestamps are read back by the log viewer.
# ---------------------------------------------------------------------
subtest 'every style has the documented shape' => sub {
    my $d = FML::Message::Date->new($T);

    like($d->mail_header_style(),
	 qr/^(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat),[ ]\d{1,2}[ ]
	    (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[ ]
	    \d{4}[ ]\d\d:\d\d:\d\d[ ][-+]\d{4}$/x,
	 'mail_header_style is RFC 5322');

    like($d->log_file_style(), qr/^\d\d\/\d\d\/\d\d \d\d:\d\d:\d\d$/,
	 'log_file_style is YY/MM/DD HH:MM:SS');

    like($d->YYYYMMDD(),   qr/^\d{8}$/,  'YYYYMMDD is eight digits');
    like($d->YYYYxMMxDD(), qr/^\d{4}\/\d{2}\/\d{2}$/, 'YYYYxMMxDD is slashed');
    like($d->current_time(), qr/^\d{12}$/, 'current_time is twelve digits');
    like($d->precise_current_time(), qr/^\d{14}$/,
	 'precise_current_time is fourteen digits');
};


# ---------------------------------------------------------------------
# 4. and each style says the same instant
#
# A style that formatted the right shape from the wrong time would pass
# everything above.
# ---------------------------------------------------------------------
subtest 'every style describes the same instant' => sub {
    my $d = FML::Message::Date->new($T);

    my $ymd = sprintf("%04d%02d%02d", $Y, $M, $D);

    is($d->YYYYMMDD(), $ymd, 'YYYYMMDD');
    is($d->YYYYxMMxDD(), sprintf("%04d/%02d/%02d", $Y, $M, $D), 'YYYYxMMxDD');
    is(substr($d->current_time(), 0, 8),         $ymd, 'current_time');
    is(substr($d->precise_current_time(), 0, 8), $ymd, 'precise_current_time');

    like($d->mail_header_style(), qr/\b$Y\b/, 'mail_header_style has the year');
    is(substr($d->log_file_style(), 0, 8),
       sprintf("%02d/%02d/%02d", $Y % 100, $M, $D), 'log_file_style');
};


# ---------------------------------------------------------------------
# 5. the accessors still take an explicit time
#
# That is how they were being used while the constructor was ignored,
# so it must not have been broken by making the constructor work.
# ---------------------------------------------------------------------
subtest 'an explicit argument overrides the object' => sub {
    my $d     = FML::Message::Date->new($T);
    my $other = $T + 86_400 * 100;

    my @o = localtime($other);
    my $want = sprintf("%04d%02d%02d", 1900 + $o[5], $o[4] + 1, $o[3]);

    is($d->YYYYMMDD($other), $want, 'YYYYMMDD($t) uses $t');
    is($d->YYYYMMDD(), sprintf("%04d%02d%02d", $Y, $M, $D),
       'and the object is unchanged afterwards');
};


# ---------------------------------------------------------------------
# 6. no argument means now
#
# The commonest call by far: every log line takes this path.
# ---------------------------------------------------------------------
subtest 'new() with no argument is now' => sub {
    my $before = time;
    my $d      = FML::Message::Date->new();
    my $after  = time;

    my $got = $d->as_unixtime();
    cmp_ok($got, '>=', $before, 'not earlier than when it was made');
    cmp_ok($got, '<=', $after,  'not later either');

    my @n = localtime($before);
    is($d->YYYYMMDD(), sprintf("%04d%02d%02d", 1900 + $n[5], $n[4]+1, $n[3]),
       'and it is today');
};


# ---------------------------------------------------------------------
# 7. parsing a date out of a header
#
# date_to_unixtime() reads what other mailers wrote, which is the widest
# possible range of formats.  These are the ones fml8 meets.
# ---------------------------------------------------------------------
subtest 'date_to_unixtime() reads real Date: headers' => sub {
    my $d = FML::Message::Date->new();

    my %case = (
	'RFC 5322 with +0000'  => [ 'Sun, 9 Sep 2001 01:46:40 +0000', $T ],
	'no day name'          => [ '9 Sep 2001 01:46:40 +0000',      $T ],
	'two digit day'        => [ 'Sun, 09 Sep 2001 01:46:40 +0000', $T ],
	'a positive zone'      => [ 'Sun, 9 Sep 2001 10:46:40 +0900', $T ],
	'a negative zone'      => [ 'Sat, 8 Sep 2001 21:46:40 -0400', $T ],
    );

    for my $name (sort keys %case) {
	my ($in, $want) = @{ $case{ $name } };
	is($d->date_to_unixtime($in), $want, "$name");
    }

    # Nothing to parse is 0, not a warning and not today.
    is($d->date_to_unixtime(undef), 0, 'undef is 0');
    is($d->date_to_unixtime(''),    0, 'the empty string is 0');
};


# ---------------------------------------------------------------------
# 8. set() and the constructor now behave the same way
#
# set() was the one path that recorded _default_unixtime, which is why
# it worked and new() did not.  They have to agree.
# ---------------------------------------------------------------------
subtest 'set() and new() give the same object' => sub {
    my $header = 'Sun, 9 Sep 2001 01:46:40 +0000';

    my $a = FML::Message::Date->new($T);

    my $b = FML::Message::Date->new();
    $b->set($header);

    for my $style (qw(log_file_style mail_header_style YYYYMMDD
		      current_time precise_current_time)) {
	is($b->$style(), $a->$style(), "$style agrees");
    }

    is($b->as_unixtime(), $a->as_unixtime(), 'and so does as_unixtime()');

    # And the constructor accepts the header form directly.
    my $c = FML::Message::Date->new($header);
    is($c->as_unixtime(), $T, 'new($header_string) parses it');
    is($c->YYYYMMDD(), $a->YYYYMMDD(), 'and gives the same day');
};


# ---------------------------------------------------------------------
# 9. a date far from now
#
# The spool is laid out by YYYYMMDD, so an article with an old Date: has
# to land under its own date rather than under today.
# ---------------------------------------------------------------------
subtest 'old and future dates are handled' => sub {
    my %case = (
	'1999'  => 946_684_800 - 86_400,   # 1999-12-31 UTC
	'2000'  => 946_684_800,            # 2000-01-01 UTC
	'2038'  => 2_147_483_647,          # the 32 bit boundary
	'2039'  => 2_147_483_648,          # one second past it
    );

    for my $name (sort keys %case) {
	my $t = $case{ $name };
	my $d = FML::Message::Date->new($t);

	my @l = localtime($t);
	is($d->YYYYMMDD(),
	   sprintf("%04d%02d%02d", 1900 + $l[5], $l[4] + 1, $l[3]),
	   "$name: the right day");
	is($d->as_unixtime(), $t, "$name: the right unixtime");
    }
};


# ---------------------------------------------------------------------
# 10. the zone in the header is a real offset
#
# fml8 speculates the zone once and reuses it.  A Date: with a bad zone
# is one that other mailers will misread.
# ---------------------------------------------------------------------
subtest 'the timezone offset is well formed' => sub {
    my $d   = FML::Message::Date->new($T);
    my $hdr = $d->mail_header_style();

    my ($sign, $hh, $mm) = $hdr =~ /([-+])(\d\d)(\d\d)$/;

    ok(defined $sign, "the header carries a zone: $hdr");
    cmp_ok($hh, '<=', 14, 'the hour part is a real offset');
    cmp_ok($mm, '<=', 59, 'and so is the minute part');

    # It has to agree with what the system says for that instant.
    my $want = POSIX::strftime("%z", localtime($T));
    is("$sign$hh$mm", $want, 'and it agrees with the system zone')
	if $want =~ /^[-+]\d{4}$/;
};

done_testing();
