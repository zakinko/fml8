#-*- perl -*-
#
# The address guard, executed rather than read.
#
# t/27 compares fml4's __SecureP() by lifting its character class out of
# the source.  This one calls the routine.  That matters for two reasons.
#
# The class is not the whole predicate: there are hooks above it
# (%SECURE_REGEXP, %INSECURE_REGEXP) and a branch below it, and reading
# only the middle would miss either.
#
# And __SecureP() does not merely return false.  It logs, and it mails
# the maintainer a message headed "Security Alert".  A subscriber whose
# address fml4 does not like therefore looks like an attack in the
# maintainer's mailbox.  That is an observable behaviour, and running
# the routine is the only way to observe it.
#
# fml4 runs in a process of its own; see ParityFML4::run_in_fml4, which
# replaces Log() and WarnE() with recorders.
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
use FML::Restriction::Base;

plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless ParityFML4::fml4_dir();
plan skip_all => "fml4 will not run here"
    unless ParityFML4::fml4_is_runnable();

# fml4 as published does not compile on a perl newer than 5.30, so this
# comparison can only be made against a tree that has been made to.  The
# modernize-perl branch is exactly that and changes nothing else.
my $LOAD_ERROR = ParityFML4::fml4_load_error("kern/libkernsubr.pl");
plan skip_all => $LOAD_ERROR if $LOAD_ERROR;

my $SAFE = new FML::Restriction::Base;


# Descriptions: call fml4's __SecureP() on $s and report the verdict
#               together with how many log lines and alert mails it
#               produced.  $s crosses as hex so nothing can touch it.
#    Arguments: STR($s) STR($mode)
# Side Effects: forks a perl(1).
# Return Value: HASH_REF
sub fml4_securep
{
    my ($s, $mode) = @_;
    $mode = '' unless defined $mode;

    my $hex = unpack("H*", $s);
    my $out = ParityFML4::run_in_fml4(qq{
	require "./kern/libkernsubr.pl";
	my \$s = pack("H*", "$hex");
	my \$r = &main::__SecureP(\$s, "$mode");
	printf "%d\\t%d\\t%d\\n", (\$r ? 1 : 0),
	    scalar(\@main::FML4_LOG), scalar(\@main::FML4_WARN);
    });

    chomp($out);
    my ($ok, $log, $warn) = split(/\t/, $out);

    return {
	accept => (defined $ok   && $ok   ? 1 : 0),
	log    => (defined $log  ? $log  : -1),
	alert  => (defined $warn ? $warn : -1),
    };
}


# Descriptions: fml8's answer for the same string, as an address.
#    Arguments: STR($s)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub fml8_accepts
{
    my ($s) = @_;

    return $SAFE->regexp_match('address', $s) ? 1 : 0;
}


# ---------------------------------------------------------------------
# 1. the routine really runs
# ---------------------------------------------------------------------
subtest "fml4's __SecureP() runs" => sub {
    my $r = fml4_securep('user@example.jp');

    isnt($r->{ log }, -1, 'fml4 answered');
    is($r->{ accept }, 1, 'a plain address is accepted');
    is($r->{ log },    0, 'and nothing is logged');
    is($r->{ alert },  0, 'and no alert is mailed');
};


# ---------------------------------------------------------------------
# 2. ordinary addresses: both accept, quietly
# ---------------------------------------------------------------------
subtest 'plain addresses are accepted by both, silently' => sub {
    for my $a ('user@example.jp', 'a.b@example.co.jp', 'a-b_c@example.jp') {
	my $r = fml4_securep($a);

	is($r->{ accept }, 1, "fml4 accepts $a");
	is($r->{ alert },  0, "fml4 mails nobody about $a");
	is(fml8_accepts($a), 1, "fml8 accepts $a");
    }
};


# ---------------------------------------------------------------------
# 3. dangerous input: both refuse
#
# This is the direction that must never regress.
# ---------------------------------------------------------------------
subtest 'shell metacharacters are refused by both' => sub {
    for my $a ('user@example.jp; rm -rf /',
	       'user@example.jp | cat',
	       'user@example.jp`id`',
	       'user@example.jp$(id)') {
	my $r = fml4_securep($a, 'command');

	is($r->{ accept }, 0, "fml4 refuses $a");
	is(fml8_accepts($a), 0, "fml8 refuses $a");
    }
};


# ---------------------------------------------------------------------
# 4. the plus form, and the alert it triggers
#
# fml4 refuses plus addressing and reports it to the maintainer as an
# attack.  fml8 accepts it.  fml4 is deliberately not being changed --
# see its commit "Record the defects whose repair would change what fml4
# does" -- so the difference is asserted here, side effect and all.
# ---------------------------------------------------------------------
subtest 'plus addressing: refused by fml4, and reported as an attack' => sub {
    for my $a ('user+tag@example.jp', 'a+b@example.co.jp') {
	my $r = fml4_securep($a);

	is($r->{ accept }, 0, "fml4 refuses $a");
	cmp_ok($r->{ log },   '>=', 1, "fml4 logs it");
	cmp_ok($r->{ alert }, '>=', 1,
	       "fml4 mails the maintainer a Security Alert about $a");

	is(fml8_accepts($a), 1, "fml8 accepts $a and says nothing");
    }
};


# ---------------------------------------------------------------------
# 5. admin mode strips the plus part before judging
#
# __SecureP() has a branch for it: in admin mode it removes
# "+ext@domain" from the string first, calling the hack ugly in its own
# comment.  So the same address fares differently depending on which
# mode the command arrived in -- worth pinning, because it is the sort
# of thing a rewrite drops.
# ---------------------------------------------------------------------
subtest 'admin mode treats the plus form differently' => sub {
    my $a = 'subscribe user+tag@example.jp';

    my $user  = fml4_securep($a, '');
    my $admin = fml4_securep($a, 'admin');

    is($user->{ accept },  0, 'in user mode fml4 refuses it');
    is($admin->{ accept }, 1, 'in admin mode fml4 accepts it');
    is($admin->{ alert },  0, 'and mails nobody');

    # fml8 asks a narrower question, so the whole command line is not an
    # address in either mode; the point is that fml8 has no such split.
    is(fml8_accepts($a), 0, 'fml8 does not read a command line as an address');
};


# ---------------------------------------------------------------------
# 6. no widening anywhere else
#
# Everything fml8 accepts and fml4 refuses, over a corpus, must be the
# plus form and nothing else.
# ---------------------------------------------------------------------
subtest 'the plus form is the only widening' => sub {
    my @corpus = (
	'user@example.jp',       'a.b@example.jp',
	'a-b@example.jp',        'a_b@example.jp',
	'user+tag@example.jp',   'user%relay.jp@example.jp',
	'user!example.jp',       'user@[192.0.2.1]',
	'"quoted"@example.jp',   'user(c)@example.jp',
	'user@exa mple.jp',      'user@@example.jp',
	'@example.jp',           'user@',
    );

    my @widened = ();
    for my $a (@corpus) {
	my $r = fml4_securep($a);
	push @widened, $a if fml8_accepts($a) && !$r->{ accept };
    }

    is_deeply(\@widened, [ 'user+tag@example.jp' ],
	      'only the plus form is accepted by fml8 and not by fml4')
	or diag("also widened: @widened");
};


# ---------------------------------------------------------------------
# 7. what the alert costs
#
# One refused address is one mail to the maintainer.  A sender who
# retries -- which a mail client does on its own -- multiplies it.  This
# is not a claim about fml4 being wrong; it is the measurement that
# makes the case for fml8 having fixed it.
# ---------------------------------------------------------------------
subtest 'each refusal is one more mail to the maintainer' => sub {
    my $total = 0;

    for my $i (1 .. 3) {
	my $r = fml4_securep("user+tag$i\@example.jp");
	$total += $r->{ alert };
    }

    is($total, 3, 'three attempts, three Security Alert mails');

    # fml8 accepts all three and mails nobody.
    for my $i (1 .. 3) {
	is(fml8_accepts("user+tag$i\@example.jp"), 1,
	   "fml8 accepts user+tag$i\@example.jp");
    }
};

done_testing();
