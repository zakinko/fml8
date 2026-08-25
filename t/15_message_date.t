#-*- perl -*-
#
# Reading a Date: header, now that it is HTTP::Date doing it.
#
# fml8 wanted one function out of Time-modules, parsedate(), and
# carried four files to get it.  HTTP::Date is one file and answers the
# same question, so the swap is only safe while the answers match --
# and where they do not, while the difference is the one written down.
#
# What depends on this: Mail::Message::DB files an article under the
# month in its Date:, and Mail::Message::ToHTML puts the HTML copy in
# the matching directory.  A wrong answer here is an article in the
# wrong month, silently.
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib img/lib cpan/lib)) {
	push @INC, $d if -d $d;
    }
}

use HTTP::Date;
use Mail::Header;
use Mail::Message::Utils;


# Descriptions: a header object with just a Date: in it.
#    Arguments: STR($date)
# Side Effects: none
# Return Value: OBJ
sub hdr
{
    my ($date) = @_;

    return new Mail::Header [ "Date: $date\n" ];
}


# ---------------------------------------------------------------------
# 1. the ten headers the two parsers were compared on
#
# Nine of these Time::ParseDate and HTTP::Date agreed on to the second.
# The values are pinned rather than recomputed so that a later change
# of parser has something to fail against.
# ---------------------------------------------------------------------
subtest 'a Date: header is the instant it says' => sub {
    my @v = (
	[ 'Tue, 25 Aug 2026 10:30:00 +0900', 1787621400 ],
	[ 'Mon, 3 Nov 2025 23:59:59 -0800',  1762243199 ],
	[ 'Thu, 01 Jan 1970 00:00:00 GMT',            0 ],
	[ 'Sat, 29 Feb 2020 12:00:00 +0900', 1582945200 ],
	[ 'Sun, 2 Nov 2014 01:30:00 -0500',  1414909800 ],
	[ 'Wed, 31 Dec 2025 15:00:00 JST',   1767160800 ],
	[ 'Fri, 13 Sep 2013 09:12:00 +0000', 1379063520 ],
	[ 'Tue, 25 Aug 2026 10:30:00 GMT',   1787653800 ],
	[ 'Mon, 1 Jan 2001 00:00:01 +0100',   978303601 ],
    );

    for my $t (@v) {
	is(str2time($t->[0]), $t->[1], $t->[0]);
    }
};


# ---------------------------------------------------------------------
# 2. the tenth, which is the difference
#
# "01 Jan 1970" has no time in it.  Time::ParseDate read that as local
# midnight; HTTP::Date refuses, the time not being optional in RFC
# 5322.  Named here so that it is a decision on the record rather than
# something found later in a wrongly filed article.
# ---------------------------------------------------------------------
subtest 'a Date: with no time in it is refused' => sub {
    is(str2time('01 Jan 1970'), undef, 'HTTP::Date will not guess a time');
};


# ---------------------------------------------------------------------
# 3. what fml8 does with the answer
#
# get_time_from_header() is the only caller.  It formats a month, and
# an unreadable Date: has always come out as this month -- undef went
# into localtime(), where it means now.  That is unchanged; it is just
# written down now instead of left to localtime(undef).
# ---------------------------------------------------------------------
subtest 'get_time_from_header() files by the month in the Date:' => sub {
    is(Mail::Message::Utils::get_time_from_header(hdr('Tue, 25 Aug 2026 10:30:00 +0900'), 'yyyymm'),
       '202608', 'yyyymm');
    is(Mail::Message::Utils::get_time_from_header(hdr('Tue, 25 Aug 2026 10:30:00 +0900'), 'yyyy/mm'),
       '2026/08', 'yyyy/mm');

    my @now   = localtime(time);
    my $month = sprintf("%04d%02d", 1900 + $now[5], $now[4] + 1);

    is(Mail::Message::Utils::get_time_from_header(hdr('garbage'), 'yyyymm'),
       $month, 'an unreadable Date: files under this month, as it always has');
    is(Mail::Message::Utils::get_time_from_header(hdr('01 Jan 1970'), 'yyyymm'),
       $month, 'and so does one with no time in it');
};


# ---------------------------------------------------------------------
# 4. no Date: at all
# ---------------------------------------------------------------------
subtest 'a message with no Date: says so and returns nothing' => sub {
    my $h = new Mail::Header [ "Subject: no date here\n" ];

    my $out = '';
    local $SIG{__WARN__} = sub { $out .= $_[0] };

    is(Mail::Message::Utils::get_time_from_header($h, 'yyyymm'), '',
       'the empty string, not a month');
    like($out, qr/cannot pick up Date:/, 'and a warning saying why');
};


done_testing();

1;
