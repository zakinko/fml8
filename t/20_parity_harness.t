#-*- perl -*-
#
# The parity harness itself.
#
# t/2*_parity_*.t compare fml8 against tables parsed out of an fml4
# checkout.  A parser that quietly returns nothing would make every one
# of those tests pass while comparing against an empty set, so check
# here that each table has plausible content before anything relies on
# it.
#

use strict;
use warnings;
use Test::More;
use lib 't';

# cpan/lib and img/lib must be APPENDED, never prepended: cpan/lib ships
# File::Spec 0.7, which lacks splitdir()/splitpath()/rel2abs() that both
# fml8 and prove(1) call.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use ParityFML4;

my $FML4 = ParityFML4::fml4_dir();
plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless $FML4;


# ---------------------------------------------------------------------
# 1. the checkout really is fml4
# ---------------------------------------------------------------------
subtest 'the tree we found is an fml4 tree' => sub {
    ok(-d $FML4,                        "$FML4 is a directory");
    ok(-f "$FML4/proc/libfml.pl",       'proc/libfml.pl is there');
    ok(-f "$FML4/kern/libkernsubr.pl",  'kern/libkernsubr.pl is there');
    ok(-f "$FML4/sbin/makefml",         'sbin/makefml is there');
    ok(-f "$FML4/libexec/fmlserv.pl",   'libexec/fmlserv.pl is there');
};


# ---------------------------------------------------------------------
# 2. every table parses to something
#
# The counts below are floors, not exact numbers: fml4 is finished
# software, so they only ever move if the parser breaks.
# ---------------------------------------------------------------------
subtest 'each fml4 table has plausible content' => sub {
    my %floor = (
	'user commands'      => [ scalar @{ ParityFML4::fml4_user_commands() },      40 ],
	'makefml subcommands'=> [ scalar @{ ParityFML4::fml4_makefml_subcommands() }, 50 ],
	'fmlserv commands'   => [ scalar @{ ParityFML4::fml4_fmlserv_commands() },     2 ],
	'config variables'   => [ scalar @{ ParityFML4::fml4_config_variables() },   150 ],
	'subject tag modes'  => [ scalar @{ ParityFML4::fml4_subject_tag_modes() },    5 ],
    );

    for my $name (sort keys %floor) {
	my ($got, $floor) = @{ $floor{ $name } };
	cmp_ok($got, '>=', $floor, "$name: $got found (at least $floor)");
    }

    my $prefix = ParityFML4::fml4_command_prefixes();
    ok(exists $prefix->{ 'l' }, 'the l# request-limit prefix was seen');
    ok(exists $prefix->{ 'r' }, 'the r# report prefix was seen');

    my $alias = ParityFML4::fml4_makefml_aliases();
    ok(scalar(keys %$alias) >= 4, 'makefml aliases were seen');
};


# ---------------------------------------------------------------------
# 3. the address guard was located
#
# fml4 is not loadable as a library -- it wants its whole kernel -- so
# t/27 compares the character class __SecureP() accepts, read out of the
# source.  If that read fails the class is empty, which would match
# nothing and make the comparison meaningless.
# ---------------------------------------------------------------------
subtest '__SecureP() character class was extracted' => sub {
    my $class = ParityFML4::fml4_secure_class();

    ok(length($class) > 0, 'a character class came back');
    like($class, qr/\\w/,  'it contains \\w, as fml4 writes it');
    like($class, qr/\\\@/, 'it contains an escaped @, so addresses can pass');

    # The class is used as [...] in a regexp; make sure it compiles.
    my $re = eval { qr/^[$class]+$/ };
    ok($re, 'the class compiles as a regexp') or diag($@);
    like('user@example.jp', $re, 'a plain address is accepted by it');
};


# ---------------------------------------------------------------------
# 4. fml8's own side is readable
# ---------------------------------------------------------------------
subtest 'fml8 command modules are enumerable' => sub {
    my $user  = ParityFML4::fml8_user_commands();
    my $admin = ParityFML4::fml8_admin_commands();

    cmp_ok(scalar(@$user),  '>=', 20, 'user commands found: ' . scalar(@$user));
    cmp_ok(scalar(@$admin), '>=', 60, 'admin commands found: ' . scalar(@$admin));

    my %u = map { $_ => 1 } @$user;
    ok($u{ 'subscribe' },   'subscribe is among them');
    ok($u{ 'unsubscribe' }, 'unsubscribe is among them');

    my $alias = ParityFML4::fml8_user_aliases();
    cmp_ok(scalar(keys %$alias), '>=', 6,
	   'aliases declared in POD: ' . join(' ', sort keys %$alias));
};

done_testing();
