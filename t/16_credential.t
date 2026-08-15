#-*- perl -*-
#
# FML::Credential: whether two addresses are the same person.
#
# This is the routine that decides who is a member.  Say yes too easily
# and a stranger posts to a closed list; say no too easily and a
# subscriber's own mail is refused because their provider started
# writing the domain differently.  It had no tests.
#
# The comparison is deliberately not string equality.  is_same_address()
# compares the user part (case sensitively or not, by configuration) and
# then walks the domain from the right, matching up to
# $address_compare_function_domain_matching_level components, so that
# "a@sub.example.jp" and "a@example.jp" can be the same subscriber.  How
# far it walks is a policy dial, and a test that fixed it at one value
# would hide the dial; each level is exercised here.
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Credential;


# A configuration with only what FML::Credential reads.  It is a blessed
# hash because the module uses both $config->{ key } and $config->yes().
{
    package t::Config;

    sub new
    {
	my ($self, $args) = @_;
	return bless { %{ $args || {} } }, $self;
    }

    sub yes
    {
	my ($self, $key) = @_;
	my $v = $self->{ $key };
	return (defined $v && $v eq 'yes') ? 1 : 0;
    }

    sub get { return $_[0]->{ $_[1] } }
}

{
    package t::Curproc;

    sub new    { return bless { _config => $_[1] }, $_[0] }
    sub config { return $_[0]->{ _config } }
    sub log      { return 1 }
    sub logdebug { return 1 }
    sub logerror { return 1 }
}


# Descriptions: a credential object configured as given.
#    Arguments: HASH_REF($args)
# Side Effects: FML::Credential keeps its data in a package global, so
#               this reconfigures the one object rather than making a
#               new one.  See the subtest that pins that.
# Return Value: OBJ
sub credential
{
    my ($args) = @_;

    my %config = (
	use_address_compare_function                 => 'yes',
	address_compare_function_type                => 'user_part_case_insensitive',
	address_compare_function_domain_matching_level => 3,
	%{ $args || {} },
    );

    my $curproc = t::Curproc->new(t::Config->new(\%config));

    return new FML::Credential $curproc;
}


# ---------------------------------------------------------------------
# 1. the same address is the same address
# ---------------------------------------------------------------------
subtest 'an address matches itself' => sub {
    my $c = credential();

    for my $a ('taro@example.jp', 'taro.yamada@example.co.jp',
	       'taro+ml@example.jp', 'a@b.c.d.example.jp') {
	is($c->is_same_address($a, $a), 1, "$a matches itself");
    }
};


# ---------------------------------------------------------------------
# 2. a different user is a different person
#
# The direction that must never go wrong: this is the one that keeps a
# stranger off a closed list.
# ---------------------------------------------------------------------
subtest 'a different user part never matches' => sub {
    my $c = credential();

    my @pair = (
	[ 'taro@example.jp',  'hanako@example.jp' ],
	[ 'taro@example.jp',  'taro2@example.jp'  ],
	[ 'taro@example.jp',  'tar@example.jp'    ],
	[ 'taro@example.jp',  'taroo@example.jp'  ],
	[ 'taro@example.jp',  'taro+ml@example.jp' ],
	[ 'a@example.jp',     'b@example.jp'      ],
    );

    for my $p (@pair) {
	is($c->is_same_address(@$p), 0, "$p->[0] is not $p->[1]");
    }
};


# ---------------------------------------------------------------------
# 3. case in the user part is a configuration choice
#
# RFC 5321 says the local part is case sensitive and every real mailer
# treats it otherwise.  fml8 has a dial; both positions are pinned.
# ---------------------------------------------------------------------
subtest 'the user part case follows the configuration' => sub {
    my $ci = credential({
	address_compare_function_type => 'user_part_case_insensitive' });

    is($ci->is_same_address('Taro@example.jp', 'taro@example.jp'), 1,
       'case insensitive: Taro is taro');
    is($ci->is_user_part_case_sensitive(), 0, 'and it says so');

    my $cs = credential({
	address_compare_function_type => 'user_part_case_sensitive' });

    is($cs->is_same_address('Taro@example.jp', 'taro@example.jp'), 0,
       'case sensitive: Taro is not taro');
    is($cs->is_user_part_case_sensitive(), 1, 'and it says so');

    # An unknown value falls back to insensitive, for compatibility with
    # fml4.  Worth pinning: a typo in main.cf must not silently make the
    # comparison stricter than the administrator meant.
    my $junk = credential({
	address_compare_function_type => 'no_such_setting' });
    is($junk->is_same_address('Taro@example.jp', 'taro@example.jp'), 1,
       'an unknown setting falls back to case insensitive');
};


# ---------------------------------------------------------------------
# 4. the domain is always case insensitive
#
# Domains are, per RFC 1035, and no dial changes that.
# ---------------------------------------------------------------------
subtest 'the domain part is case insensitive' => sub {
    my $c = credential({
	address_compare_function_type => 'user_part_case_sensitive' });

    is($c->is_same_address('taro@Example.JP', 'taro@example.jp'), 1,
       'even when the user part is case sensitive');

    is($c->is_same_domain('EXAMPLE.JP', 'example.jp'), 1, 'is_same_domain');
    is($c->is_same_domain('example.jp', 'example.com'), 0,
       'and it still tells them apart');
};


# ---------------------------------------------------------------------
# 5. how far up the domain it walks
#
# The dial.  Two domains that are not equal are split into labels,
# reversed, and compared from the top down; the number that match has to
# reach the configured level.  Equal domains never get that far -- rule 2
# returns before it -- so the dial only decides how generous the
# comparison is about subdomains.
#
# The loop runs "for (my $i = 0; $i < $#xdomain; $i++)", so the leftmost
# label of the first address is never compared.  That is what lets
# "sub.example.jp" reach "example.jp" at all, and it means the count can
# never exceed the label count minus one.  With the default level of 3,
# a two label domain like example.jp can therefore only ever match
# exactly.  Measured rather than assumed: this is the sort of arithmetic
# that reads as though it does something else.
# ---------------------------------------------------------------------
subtest 'the domain matching level decides how far it reaches' => sub {
    my %expect = (
	# level => [ [ x, y, same? ], ... ]
	1 => [
	    [ 'a@example.jp',           'a@example.jp',       1 ],
	    [ 'a@sub.example.jp',       'a@example.jp',       1 ],
	    [ 'a@example.jp',           'a@example.com',      0 ],
	    [ 'a@example.jp',           'a@other.jp',         1 ],
	],
	2 => [
	    [ 'a@example.jp',           'a@example.jp',       1 ],
	    [ 'a@sub.example.jp',       'a@example.jp',       1 ],
	    [ 'a@example.jp',           'a@other.jp',         0 ],
	    [ 'a@example.jp',           'a@example.com',      0 ],
	],
	3 => [
	    [ 'a@example.jp',           'a@example.jp',       1 ],
	    [ 'a@x.sub.example.jp',     'a@y.sub.example.jp', 1 ],
	    [ 'a@sub.example.jp',       'a@example.jp',       0 ],
	    [ 'a@example.jp',           'a@example.com',      0 ],
	    [ 'a@example.jp',           'a@other.jp',         0 ],
	],
    );

    for my $level (sort keys %expect) {
	my $c = credential({
	    address_compare_function_domain_matching_level => $level });

	is($c->get_compare_level(), $level, "level $level is in force");

	for my $case (@{ $expect{ $level } }) {
	    my ($x, $y, $want) = @$case;
	    is($c->is_same_address($x, $y), $want,
	       "level $level: $x vs $y");
	}
    }
};


# ---------------------------------------------------------------------
# 5a. what a low level costs
#
# Level 1 is one matching label, and the top label of a domain is the
# TLD.  So at level 1 every .jp address is the same person as every
# other .jp address with the same user part.  That is a real setting
# with a real consequence, and it should be visible rather than left to
# be discovered on a closed list.
# ---------------------------------------------------------------------
subtest 'a low matching level matches on the TLD alone' => sub {
    my $c = credential({
	address_compare_function_domain_matching_level => 1 });

    is($c->is_same_address('taro@example.jp', 'taro@totally-unrelated.jp'), 1,
       'level 1: two unrelated .jp domains are the same subscriber');
    is($c->is_same_address('taro@example.jp', 'taro@example.com'), 0,
       'but a different TLD is not');

    # The default is 3, which does not do this.
    my $d = credential();
    is($d->get_compare_level(), 3, 'the default level is 3');
    is($d->is_same_address('taro@example.jp', 'taro@totally-unrelated.jp'), 0,
       'and at the default they are different subscribers');
};


# ---------------------------------------------------------------------
# 6. an address that is not an address
#
# is_same_address() splits on "@" and compares the halves, so input with
# no "@", or two, or none of it, has to come out as "not the same"
# rather than as a warning or a match.
# ---------------------------------------------------------------------
subtest 'malformed input does not match anything' => sub {
    my $c = credential();

    my @warn = ();
    local $SIG{__WARN__} = sub { push @warn, $_[0] };

    my @pair = (
	[ 'taro@example.jp', ''                 ],
	[ 'taro@example.jp', 'taro'             ],
	[ 'taro@example.jp', '@example.jp'      ],
	[ 'taro@example.jp', 'taro@'            ],
	[ '',                ''                 ],
	[ 'taro',            'taro'             ],
    );

    for my $p (@pair) {
	my $shown = join(' vs ', map { $_ eq '' ? '(empty)' : $_ } @$p);
	my $r = $c->is_same_address(@$p);
	ok(defined $r, "$shown: answered something");
    }

    # "taro" and "taro" have the same user part and no domain at all, so
    # they do compare equal.  Recorded rather than judged: nothing in
    # fml8 asks this question without an "@".
    is($c->is_same_address('taro', 'taro'), 1,
       'two bare user names with no domain compare equal');

    is(scalar(@warn), 0, 'and nothing warned about an undefined value')
	or diag("warnings: @warn");
};


# ---------------------------------------------------------------------
# 7. undef is not a match
#
# The guard at the top of is_same_address(). A missing From: must not
# make somebody a member.
# ---------------------------------------------------------------------
subtest 'undef never matches' => sub {
    my $c = credential();

    is($c->is_same_address(undef, 'taro@example.jp'), 0, 'undef vs address');
    is($c->is_same_address('taro@example.jp', undef), 0, 'address vs undef');
    is($c->is_same_address(undef, undef),             0, 'undef vs undef');
};


# ---------------------------------------------------------------------
# 8. the comparison can be turned off entirely
#
# use_address_compare_function = no makes everything the same address.
# That is a real setting, and it is worth seeing what it does, because
# "everything matches" is indistinguishable from "the check works" in
# any test that only feeds it addresses that should match.
# ---------------------------------------------------------------------
subtest 'disabling the comparison makes everything match' => sub {
    my $c = credential({ use_address_compare_function => 'no' });

    is($c->is_same_address('taro@example.jp', 'hanako@example.com'), 1,
       'with the comparison off, two strangers are the same person');

    # And with it on, they are not.  The same objects, so this also
    # shows the setting is read per call rather than cached at new().
    my $on = credential({ use_address_compare_function => 'yes' });
    is($on->is_same_address('taro@example.jp', 'hanako@example.com'), 0,
       'and with it on, they are not');
};


# ---------------------------------------------------------------------
# 9. FML::Credential is process-wide
#
# new() returns a blessed reference to the package global %Credential,
# so there is one credential per process however many times it is
# constructed.  Pinned because it makes the order of construction
# matter, which is invisible at the call site -- and because it is why
# credential() above reconfigures rather than isolating.
# ---------------------------------------------------------------------
subtest 'FML::Credential shares one pool, by design' => sub {
    my $a = credential({ address_compare_function_domain_matching_level => 2 });
    my $b = credential({ address_compare_function_domain_matching_level => 5 });

    is($a->get_compare_level(), $b->get_compare_level(),
       'the second construction reconfigured the first object too');
    is($a->get_compare_level(), 5, 'and the later setting is the one in force');
};


# ---------------------------------------------------------------------
# 10. the level can be set directly
# ---------------------------------------------------------------------
subtest 'set_compare_level() takes effect' => sub {
    my $c = credential();

    $c->set_compare_level(1);
    is($c->get_compare_level(), 1, 'the level was set');
    is($c->is_same_address('a@sub.example.jp', 'a@example.jp'), 1,
       'and a shallow level matches across a subdomain');

    $c->set_compare_level(3);
    is($c->get_compare_level(), 3, 'and set back');
};

done_testing();
