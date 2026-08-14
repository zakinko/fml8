#-*- perl -*-
#
# Command aliases on both sides.
#
# fml4 accepted several spellings of the same request -- "bye", "quit",
# "unsubscribe" and so on -- by pointing them at one handler in
# %Procedure.  fml8 gives each spelling its own module whose POD says
# which command it stands for.
#
# Two things can go wrong with that arrangement and neither shows up in
# a compile check: an alias module can name a target that does not
# exist, and an alias can drift away from its target so that the two
# spellings no longer do the same thing.  Both are checked here.
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

plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless ParityFML4::fml4_dir();

my $ALIAS = ParityFML4::fml8_user_aliases();
my %USER  = map { $_ => 1 } @{ ParityFML4::fml8_user_commands() };


# ---------------------------------------------------------------------
# 1. every declared alias points somewhere real
# ---------------------------------------------------------------------
subtest 'each fml8 alias names a command that exists' => sub {
    cmp_ok(scalar(keys %$ALIAS), '>=', 6,
	   'aliases found: ' . join(' ', sort keys %$ALIAS));

    for my $a (sort keys %$ALIAS) {
	my $target = $ALIAS->{ $a };
	ok($USER{ $target }, "$a -> $target, and $target is a command");
	ok(-f "fml/lib/FML/Command/User/$target.pm",
	   "User/$target.pm exists");
    }
};


# ---------------------------------------------------------------------
# 2. an alias must not point at another alias
#
# fml8's own style note says to keep inheritance shallow.  A chain also
# makes the POD lie about what actually runs.
# ---------------------------------------------------------------------
subtest 'no alias points at another alias' => sub {
    for my $a (sort keys %$ALIAS) {
	my $target = $ALIAS->{ $a };
	ok(!exists $ALIAS->{ $target },
	   "$a -> $target, and $target is not itself an alias");
    }
};


# ---------------------------------------------------------------------
# 3. the alias really delegates
#
# Declaring the alias in POD is not enough: the module has to reach the
# target's implementation, which fml8 does through @ISA.  A module that
# says "alias of X" but implements its own process() has quietly become
# a second implementation.
# ---------------------------------------------------------------------
subtest 'an alias inherits from the command it stands for' => sub {
    for my $a (sort keys %$ALIAS) {
	my $target = $ALIAS->{ $a };
	my $pkg    = "FML::Command::User::$a";
	my $tpkg   = "FML::Command::User::$target";

	my $ok = eval "require $pkg; 1";
	ok($ok, "$pkg loads") or do { diag($@); next };

	no strict 'refs';
	my @isa = @{ "${pkg}::ISA" };
	use strict 'refs';

	ok($pkg->isa($tpkg), "$a isa $target")
	    or diag("$a \@ISA = @isa");
    }
};


# ---------------------------------------------------------------------
# 4. fml4's spellings of "leave the list" all reach fml8
#
# This is the group a subscriber is most likely to type from memory, and
# the one where a missing spelling is silently read as an unknown
# command and bounced back.
# ---------------------------------------------------------------------
subtest 'the ways to leave a list' => sub {
    # fml4 pointed all of these at ProcUnSubscribe.
    my @fml4_leave = qw(bye unsubscribe);
    my %f4 = map { $_ => 1 } @{ ParityFML4::fml4_user_commands() };

    for my $c (@fml4_leave) {
	ok($f4{ $c }, "fml4 accepted \"$c\"");
	ok($USER{ $c }, "fml8 accepts \"$c\" too");
    }

    # fml8 adds more spellings than fml4 had, which is fine; check they
    # all land on unsubscribe rather than on each other.
    my @to_unsub = sort grep { $ALIAS->{ $_ } eq 'unsubscribe' } keys %$ALIAS;
    cmp_ok(scalar(@to_unsub), '>=', 3,
	   'spellings that mean unsubscribe: ' . join(' ', @to_unsub));
};


# ---------------------------------------------------------------------
# 5. fml4's alias prefixes are accounted for
#
# %Procedure carries l#, r#, d#, confirm#, r2a# and dbd# variants of a
# command name.  They are not commands, and t/21 strips them; make sure
# that stripping did not throw away a name that only ever appears with a
# prefix, which would hide it from the parity count.
# ---------------------------------------------------------------------
subtest 'prefixed entries all refer to a real fml4 command' => sub {
    my $prefix = ParityFML4::fml4_command_prefixes();
    my %f4     = map { $_ => 1 } @{ ParityFML4::fml4_user_commands() };

    # r# is attached to plenty of names that are commands in their own
    # right; the ones that are not are what we want to see.
    my %orphan = ();
    for my $p (sort keys %$prefix) {
	for my $name (@{ $prefix->{ $p } }) {
	    $orphan{ $name } = $p unless $f4{ $name };
	}
    }

    # "subscribe" is fml4's canonical name for joining and appears only
    # as r#subscribe in the table, because joining is not a command: it
    # is what an unknown sender's mail triggers.
    delete $orphan{ 'subscribe' };

    is_deeply([ sort keys %orphan ], [],
	      'no prefixed entry names a command the parity count missed')
	or diag(join(", ", map { "$_ (via $orphan{$_}#)" } sort keys %orphan));
};

done_testing();
