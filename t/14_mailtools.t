#-*- perl -*-
#
# What fml8 asks of MailTools, held to its answers.
#
# cpan/lib carried MailTools 1.17 -- Graham Barr's last release, from
# 1998 -- while cpan/dist carried 2.19 beside it.  cpan/lib is what goes
# on @INC, so fml8 has been running the 1998 code all along.  Both are
# now 2.22, which is what pkgsrc mail/p5-MailTools packages.
#
# That is a nineteen year jump in a module that parses addresses, and
# address parsing is what decides who is a member of a mailing list.  So
# the point of this file is not that MailTools works -- it has its own
# tests -- but that the eleven places fml8 reaches into it still get the
# answers fml8 was written against.
#
# The bundled copy is forced to the front of @INC here.  On a host with
# its own MailTools the tests would otherwise measure that one, and the
# bundled copy is what an installation without it gets.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

# The bundled copy first, on purpose, and only in this file.  Everywhere
# else in t/ cpan/lib goes last so a host installation wins.
BEGIN {
    unshift @INC, 'cpan/lib' if -d 'cpan/lib';
    for my $d (qw(fml/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Address;
use Mail::Header;


# ---------------------------------------------------------------------
# 1. the copy under test is the bundled one
# ---------------------------------------------------------------------
subtest 'the bundled MailTools is the one loaded here' => sub {
    like($INC{'Mail/Address.pm'}, qr{cpan/lib/},
	 'Mail::Address came from cpan/lib');
    like($INC{'Mail/Header.pm'}, qr{cpan/lib/},
	 'Mail::Header came from cpan/lib');

    # 1.17 is the version that must not come back: it predates the
    # change of maintainer and nineteen years of address parsing fixes.
    cmp_ok($Mail::Address::VERSION, '>=', 2.22,
	   "Mail::Address is $Mail::Address::VERSION");
    cmp_ok($Mail::Header::VERSION, '>=', 2.22,
	   "Mail::Header is $Mail::Header::VERSION");
};


# ---------------------------------------------------------------------
# 2. the address forms a mailing list actually receives
#
# parse() returns a list of objects; fml8 takes the first and calls
# address() on it, at every one of its call sites.  So what matters is
# that the first object is the right one and its address() is the bare
# address, with no display name, no comment and no angle brackets.
# ---------------------------------------------------------------------
subtest 'parse() reduces a From: to a bare address' => sub {
    my %case = (
	'bare'                 => [ 'taro@example.jp',                'taro@example.jp' ],
	'angle brackets'       => [ '<taro@example.jp>',              'taro@example.jp' ],
	'display name'         => [ 'Taro Yamada <taro@example.jp>',  'taro@example.jp' ],
	'quoted display name'  => [ '"Yamada, Taro" <taro@example.jp>', 'taro@example.jp' ],
	'comment after'        => [ 'taro@example.jp (Taro Yamada)',  'taro@example.jp' ],
	'comment before'       => [ '(Taro Yamada) taro@example.jp',  'taro@example.jp' ],
	'leading space'        => [ '   taro@example.jp',             'taro@example.jp' ],
	'trailing space'       => [ 'taro@example.jp   ',             'taro@example.jp' ],
	'plus addressing'      => [ 'taro+ml@example.jp',             'taro+ml@example.jp' ],
	'dotted user'          => [ 'taro.yamada@example.co.jp',      'taro.yamada@example.co.jp' ],
	'subdomain'            => [ 'taro@mail.example.co.jp',        'taro@mail.example.co.jp' ],
	'uppercase'            => [ 'Taro@Example.JP',                'Taro@Example.JP' ],
    );

    for my $name (sort keys %case) {
	my ($in, $want) = @{ $case{ $name } };
	my @a = Mail::Address->parse($in);

	cmp_ok(scalar(@a), '>=', 1, "$name: something was parsed");
	is($a[0]->address, $want, "$name: address() is the bare address")
	    if @a;
    }
};


# ---------------------------------------------------------------------
# 3. the parts fml8 reads off an address
# ---------------------------------------------------------------------
subtest 'user, host and phrase' => sub {
    my ($a) = Mail::Address->parse('Taro Yamada <taro@example.co.jp>');

    ok($a, 'parsed');
    is($a->user,    'taro',           'user');
    is($a->host,    'example.co.jp',  'host');
    is($a->phrase,  'Taro Yamada',    'phrase');
    is($a->address, 'taro@example.co.jp', 'address');

    # format() is the round trip: what fml8 would put back in a header.
    like($a->format, qr/taro\@example\.co\.jp/, 'format() keeps the address');
};


# ---------------------------------------------------------------------
# 4. more than one address in a field
#
# To: and Cc: carry lists.  fml8 mostly wants the first, but the
# recipient analysis walks all of them, so the order and the count have
# to be right.
# ---------------------------------------------------------------------
subtest 'a list of addresses comes back in order' => sub {
    my $line = 'Taro <taro@example.jp>, hanako@example.jp, ' .
	       '"Suzuki, Ichiro" <ichiro@example.co.jp>';

    my @a = Mail::Address->parse($line);

    is(scalar(@a), 3, 'three addresses');
    is($a[0]->address, 'taro@example.jp',      'first');
    is($a[1]->address, 'hanako@example.jp',    'second');
    is($a[2]->address, 'ichiro@example.co.jp', 'third');

    # The comma inside the quoted phrase must not split the list.  The
    # phrase comes back with its quotes still on, which is what fml8
    # gets and therefore what is pinned; only address() is used to
    # decide membership, and that one is unquoted.
    is($a[2]->phrase, '"Suzuki, Ichiro"',
       'a comma inside a quoted phrase does not end the address');
};


# ---------------------------------------------------------------------
# 5. input that is not an address
#
# The list of addresses a mailing list is handed includes rubbish, and
# what parse() does with rubbish decides whether fml8 crashes or refuses.
# Recorded rather than asserted to be any particular thing: the contract
# fml8 needs is only that it does not die.
# ---------------------------------------------------------------------
subtest 'rubbish is survived' => sub {
    my @junk = ('', ' ', 'not an address', '@', '@example.jp', 'taro@',
		'<<>>', 'taro@@example.jp', "taro\@example.jp\n",
		'taro@example.jp; rm -rf /', '"unclosed <taro@example.jp>');

    for my $in (@junk) {
	my $shown = $in;
	$shown =~ s/([^\x20-\x7e])/sprintf("\\x%02x", ord($1))/ge;

	my @a = eval { Mail::Address->parse($in) };
	is($@, '', "[$shown]: parse() does not die") or diag($@);
    }
};


# ---------------------------------------------------------------------
# 6. the adapter fml8 wraps around it
#
# Mail::Message::Address is object composition rather than inheritance,
# on purpose -- there is an XXX in it saying so -- and it forwards
# through AUTOLOAD.  So the forwarding is what to check.
# ---------------------------------------------------------------------
subtest 'Mail::Message::Address forwards to Mail::Address' => sub {
    require Mail::Message::Address;

    my $a = new Mail::Message::Address 'Taro Yamada <taro@example.co.jp>';

    ok(defined $a, 'the adapter constructs');
    is($a->as_str(), 'taro@example.co.jp', 'as_str() is the bare address');

    # Forwarded through AUTOLOAD to the wrapped object.
    is($a->address, 'taro@example.co.jp', 'address() is forwarded');
    is($a->user,    'taro',               'user() is forwarded');
    is($a->host,    'example.co.jp',      'host() is forwarded');

    # cleanup() strips angle brackets the parser left behind.
    my $b = new Mail::Message::Address '<taro@example.jp>';
    $b->cleanup();
    is($b->as_str(), 'taro@example.jp', 'cleanup() removes < and >');

    # substr() is used to truncate an address for a fixed width listing.
    is($a->substr(0, 4), 'taro', 'substr() cuts the address');
};


# ---------------------------------------------------------------------
# 6a. the adapter on input that does not parse
#
# new() takes $addrs[0]->address without checking whether parse()
# returned anything.  An address it cannot parse is therefore a died
# process rather than a rejected address, and this runs on whatever
# arrives in a From:.
# ---------------------------------------------------------------------
subtest 'the adapter on unparseable input' => sub {
    require Mail::Message::Address;

    for my $in ('', ' ', '@', 'not an address') {
	my $shown = $in eq '' ? '(empty)' : $in;
	my $obj   = eval { new Mail::Message::Address $in };

	local $TODO = 'new() calls ->address on $addrs[0] without checking it';
	is($@, '', "[$shown]: the adapter does not die");
    }
};


# ---------------------------------------------------------------------
# 7. Mail::Header, which is what Mail::Message parses into
# ---------------------------------------------------------------------
subtest 'Mail::Header reads a header the way fml8 expects' => sub {
    my @hdr = split(/\n/, <<'END_OF_HEADER');
From: Taro Yamada <taro@example.jp>
To: elena@example.jp
Subject: hello
Received: from a.example.jp by b.example.jp; Sun, 9 Sep 2001 01:46:40 +0000
Received: from b.example.jp by c.example.jp; Sun, 9 Sep 2001 01:46:41 +0000
X-Long: this value is continued
	onto a second line
END_OF_HEADER

    my $h = new Mail::Header \@hdr;
    ok(defined $h, 'the header parses');

    my $from = $h->get('From');
    $from =~ s/\n$//;
    is($from, 'Taro Yamada <taro@example.jp>', 'get() returns the field');

    # Field names are case insensitive in mail, and fml8 asks in every
    # case there is.
    for my $name (qw(from From FROM fRoM)) {
	my $v = $h->get($name);
	$v =~ s/\n$// if defined $v;
	is($v, 'Taro Yamada <taro@example.jp>', "get('$name') is the same");
    }

    # A field that is not there is undef, not the empty string, and
    # asking must not create it.
    is($h->get('X-No-Such-Field'), undef, 'a missing field is undef');

    # Received: appears more than once and the order matters for tracing.
    my @rcvd = $h->get('Received');
    is(scalar(@rcvd), 2, 'both Received: lines come back');
    like($rcvd[0], qr/a\.example\.jp/, 'in the order they appeared');

    # A folded value is one value, not two.
    my $long = $h->get('X-Long');
    like($long, qr/continued/,      'the folded field is readable');
    like($long, qr/second line/,    'including its continuation');
};


# ---------------------------------------------------------------------
# 8. building a header, which is the other direction
# ---------------------------------------------------------------------
subtest 'Mail::Header can be written as well as read' => sub {
    my $h = new Mail::Header;

    $h->add('From',    'taro@example.jp');
    $h->add('Subject', '[elena:00001] hello');

    my $from = $h->get('From');
    $from =~ s/\n$//;
    is($from, 'taro@example.jp', 'add() then get()');

    $h->replace('Subject', '[elena:00002] hello again');
    my $s = $h->get('Subject');
    $s =~ s/\n$//;
    is($s, '[elena:00002] hello again', 'replace() overwrites');

    $h->delete('Subject');
    is($h->get('Subject'), undef, 'delete() removes it');

    # The whole header as text, which is what goes out on the wire.
    my $text = join('', @{ $h->header() });
    like($text, qr/^From:\s*taro\@example\.jp/m, 'as_string keeps From:');
    unlike($text, qr/Subject:/, 'and not the deleted field');
};


# ---------------------------------------------------------------------
# 9. octets in a header
#
# Mail is octets.  A header module that decoded would hand fml8
# characters, and everything downstream counts bytes.
# ---------------------------------------------------------------------
subtest 'a header value keeps its octets' => sub {
    my $euc  = "\xc6\xfc\xcb\xdc\xb8\xec";   # 日本語 in EUC-JP
    my $utf8 = "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e";

    for my $pair ([ 'euc-jp', $euc ], [ 'utf-8', $utf8 ]) {
	my ($name, $octets) = @$pair;

	my $h = new Mail::Header;
	$h->add('X-Test', $octets);

	my $got = $h->get('X-Test');
	$got =~ s/\n$// if defined $got;

	is($got, $octets, "$name: the octets come back unchanged");
	is(length($got), length($octets), "$name: and the same length");
    }
};

done_testing();
