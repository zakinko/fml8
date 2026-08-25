#-*- perl -*-
#
# What fml8 asks of MailTools, held to its answers.
#
# cpan/lib carried Mail::Address 1.17 and Mail::Header 1.19 -- Graham
# Barr's last release, from 1998 -- while cpan/dist carried 2.19 beside
# them.  cpan/lib is what goes on @INC, so fml8 has been running the
# 1998 code all along.  Both are now 2.22, which is what pkgsrc
# mail/p5-MailTools packages.
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

# ---------------------------------------------------------------------
# The places RFC 5322 is awkward, and whether this one gets them right
#
# Mail::Header's own documentation says it "does not always follow the
# RFCs strict enough, does not help you with character encodings", and
# points at Mail::Message::Head as "much newer and therefore better".
# The advice is the author's own -- MARKOV maintains both -- and it
# cannot be taken.
#
# Mail-Message pulls Log::Report, String::Print, User::Identity, URI,
# IO-stringy and TimeDate behind it, 223 modules against the seven
# cpan/lib holds, and it requires Mail::Address, so MailTools would not
# even leave.  That is only the size of it.  The reason is one module
# further down:
#
#     Mail::Message -> Log::Report -> String::Print -> Unicode::GCString
#
# and Unicode::GCString is Unicode-LineBreak, which is C.  String::Print
# line 23 is "use Unicode::GCString ()", not a require inside an eval, so
# there is no path around it -- Log::Report::Optional and its Minimal
# variant reach the same line through Log::Report::Util.  fml8 bundles
# pure perl; this would make a compiler a requirement for installing a
# mailing list manager.  Unicode-LineBreak last moved in 2018, which is
# older than the module all this was meant to get away from.
#
# So the question is not whether Mail::Header is imperfect in general.
# It is whether fml8 stands anywhere near the imperfection.  These are
# the awkward parts of RFC 5322 and 2047 for the eight methods fml8
# inherits, and the answers are recorded rather than argued about: if
# one of them starts failing, that is the day the trade becomes worth
# making, and the failure says which input to take to the maintainer.
# ---------------------------------------------------------------------
subtest 'the awkward parts of RFC 5322' => sub {
    my $folded = _header("Subject: a long subject\n which continues\n\tand again");
    my $got    = $folded->get('Subject');
    like($got, qr/which continues/, 'a folded line keeps its middle');
    like($got, qr/and again/,       'and its tail');

    my $case = _header("Subject: hello");
    ok(defined $case->get('subject'), 'field names are matched case-insensitively');
    ok(defined $case->get('SUBJECT'), 'in either direction');

    # Received: is the one field whose order carries meaning.
    my $rcvd = _header("Received: from a\nReceived: from b\nReceived: from c");
    my @r    = $rcvd->get('Received');
    is(scalar(@r), 3, 'every Received: is kept, not just the first');
    like($r[0], qr/from a/, 'and they come back in the order they arrived');

    # A subject tag holds a colon, and so does the Re: in front of it.
    my $colon = _header("Subject: Re: [elena:00123] hello");
    like($colon->get('Subject'), qr/^Re: \[elena:00123\] hello/,
         'a colon in the value does not split the field');

    my $empty = _header("X-Empty:\nSubject: after");
    ok(defined $empty->get('X-Empty'), 'an empty value is a value');
    like($empty->get('Subject'), qr/after/, 'and does not swallow what follows');

    # RFC 2047 is somebody else's job -- Mail::Message::Encode's -- and
    # the header must hand it over untouched for that to work.
    my $ew = _header("Subject: =?ISO-2022-JP?B?GyRCJUYlOSVIGyhC?=");
    like($ew->get('Subject'), qr/\Q=?ISO-2022-JP?B?\E/,
         'an encoded-word is passed through, not decoded here');

    # A line with no colon is not a header field.  What matters is that
    # the fields after it are still found.
    my $addr = 'a@b.jp';
    my $junk = _header("Subject: ok\nthis line has no colon\nFrom: $addr");
    like($junk->get('From'), qr/\Q$addr\E/,
         'a malformed line does not lose the fields behind it');
};


# ---------------------------------------------------------------------
# Writing a header out again
#
# RFC 5322 puts a hard limit of 998 characters on a line, and RFC 2047
# says an encoded-word may not be split across a fold.  A Japanese
# subject is where both meet: it arrives as one long encoded-word and
# has to leave as something a receiving MTA will accept.
# ---------------------------------------------------------------------
subtest 'a long Japanese subject survives being written out' => sub {
    my $word = "=?ISO-2022-JP?B?" . ("GyRCJUYlOSVIGyhC" x 6) . "?=";

    my $head = Mail::Header->new;
    $head->add('Subject', $word);
    my $out = $head->as_string;

    my ($longest) = sort { $b <=> $a } map { length } split /\n/, $out;
    cmp_ok($longest, '<=', 998, 'no line exceeds what RFC 5322 allows')
	or diag("longest line is $longest characters");

    my $split = 0;
    for my $line (split /\n/, $out) {
	$split++ if $line =~ /=\?[^?]*\?[BQ]\?[^?]*$/;
    }
    is($split, 0, 'and no encoded-word is broken across a fold');
};


# ---------------------------------------------------------------------
# Where it does get RFC 5322 wrong
#
# The group syntax -- "friends: a@x.jp, b@y.jp;" -- is a legal way to
# write a To: or Cc:, and Mail::Address does not take the group name
# off the first address in it.  fml8 decides who is a member by
# comparing addresses, so a post whose To: is written that way has one
# recipient it will not recognise.
#
# Recorded as TODO rather than worked around here.  It is the first
# thing found that Mail::Message::Head would answer correctly, and it
# is the sort of evidence that decides whether carrying 223 modules is
# worth it -- an input that fails, rather than a sentence in somebody's
# documentation.
# ---------------------------------------------------------------------
subtest 'the group syntax loses an address' => sub {
    my @addr = Mail::Address->parse('friends: a@x.jp, b@y.jp;');

    is(scalar(@addr), 2, 'both members of the group are found');

    # The second one is right, which is what makes the first a bug
    # rather than a decision not to support groups at all.
    is($addr[1]->address, 'b@y.jp', 'the last address in a group is clean');

    local $TODO = 'Mail::Address keeps the group name on the first address';
    is($addr[0]->address, 'a@x.jp',
       'the first address in a group is not prefixed with the group name');
    is($addr[0]->user, 'a',
       'and its user part is the user part');
};


# ---------------------------------------------------------------------
# The rest of what fml8 inherits, held to its answers
# ---------------------------------------------------------------------
subtest 'replace, delete, count and dup' => sub {
    my $head = _header("X-A: 1\nX-A: 2\nX-B: 3");

    $head->replace('X-B', '9');
    like($head->get('X-B'), qr/9/, 'replace() puts the new value in');

    $head->delete('X-A');
    is(scalar($head->count('X-A')), 0, 'delete() takes every copy of a field');

    my $orig = _header("Subject: orig");
    my $copy = $orig->dup;
    $copy->replace('Subject', 'changed');

    like($orig->get('Subject'), qr/orig/,
	 'dup() gives a copy that can be changed without touching the original');
    like($copy->get('Subject'), qr/changed/, 'and the copy did change');
};


subtest 'a header keeps octets it does not understand' => sub {
    # EUC-JP straight into the field, which is what fml8 hands it after
    # Mail::Message::Encode has converted an article.
    my $jp   = "\xc6\xfc\xcb\xdc\xb8\xec";
    my $head = _header("Subject: $jp");
    my $got  = $head->get('Subject');
    chomp $got;

    is($got, $jp, 'the bytes come back as the bytes that went in')
	or diag(sprintf("in %s, out %s", unpack("H*", $jp), unpack("H*", $got)));

    # And an encoded-word that was folded onto two lines is still two
    # encoded-words afterwards, not one run-together string.
    my $folded = _header("Subject: =?ISO-2022-JP?B?GyRCJUYlOSVIGyhC?=\n"
			 . " =?ISO-2022-JP?B?GyRCJUYlOSVIGyhC?=");
    my $count = () = $folded->get('Subject') =~ /=\?ISO/g;
    is($count, 2, 'both encoded-words survive the unfolding');
};


subtest 'addresses that are legal but unusual' => sub {
    my %case = (
	'a@[192.0.2.1]' => 'a@[192.0.2.1]',   # domain literal
	'"a b"@x.jp'    => '"a b"@x.jp',      # quoted local part
    );

    for my $in (sort keys %case) {
	my @p = Mail::Address->parse($in);
	is(scalar(@p), 1, "$in: one address");
	is($p[0]->address, $case{$in}, "$in: kept as written");
    }

    # An empty element between two commas is not an address.
    my @p = Mail::Address->parse('a@x.jp, , b@y.jp');
    is(scalar(@p), 2, 'an empty list element is skipped, not counted');

    # The empty angle pair is the null return path, and has no address.
    my @null = Mail::Address->parse('<>');
    is(scalar(@null), 0, '<> yields no address at all');
};


# Descriptions: build a Mail::Header from a string of header lines.
#    Arguments: STR($text)
# Side Effects: none
# Return Value: OBJ
sub _header
{
    my ($text) = @_;
    my $head = Mail::Header->new;

    $head->extract([ map { "$_\n" } split(/\n/, $text) ]);

    return $head;
}


done_testing();
