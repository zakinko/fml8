#-*- perl -*-
#
# FML::Crypt, now that the pure perl DES came out of cpan/lib.
#
# fml8 bundled Crypt::UnixCrypt and called it in preference to the
# built-in, with a comment saying to always use that one.  The two were
# compared over all 4096 salts against five passwords, then 3000 random
# passwords of length 0 to 19, then non-ASCII input -- 23492 answers,
# no difference -- so the module was there for portability rather than
# because crypt(3) was wrong, and it is gone.
#
# What is left to hold is the shape of the answers and the behaviour
# when the host cannot give them.  The vectors below are the answers
# DES crypt has returned since 1979; they belong to no particular
# implementation, which is what makes them worth keeping past the one
# they were written for.
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

use FML::Crypt;

my $obj = new FML::Crypt;


# ---------------------------------------------------------------------
# 1. this host answers for DES at all
#
# Everything below assumes it does.  Say so once, here, rather than
# letting eleven tests fail with no explanation between them.
# ---------------------------------------------------------------------
my $des = (defined(eval { crypt("fml", "ab") })
	   && crypt("fml", "ab") eq 'abElTpU575Od6') ? 1 : 0;

ok($des, 'crypt(3) on this host does classic DES')
    or diag("crypt('fml','ab') gave: " . (crypt("fml","ab") // 'undef'));

plan skip_all => "crypt(3) here is not DES; nothing below applies"
    unless $des;


# ---------------------------------------------------------------------
# 2. the vectors
# ---------------------------------------------------------------------
subtest 'the answers DES crypt has always given' => sub {
    my @v = (
	[ 'fml',      'ab', 'abElTpU575Od6' ],
	[ '',         'ab', 'abmF1QH4PEr.E' ],
	[ 'password', 'ab', 'abJnggxhB/yWI' ],
	[ 'a',        'zz', 'zzJZ5PtvFqi9o' ],
	[ 'fml',      'zz', 'zzTahN6.JlZqk' ],
    );

    for my $t (@v) {
	my ($text, $salt, $want) = @$t;
	is($obj->unix_crypt($text, $salt), $want,
	   "crypt('$text', '$salt')");
    }
};


# ---------------------------------------------------------------------
# 3. the shape FML::Command::Auth uses
#
# It crypts with $$ as salt to store, then crypts the candidate with
# the stored value as salt to check.  That round trip is the whole of
# the password check, so it is the thing to hold.
# ---------------------------------------------------------------------
subtest 'crypt with the stored value as salt round trips' => sub {
    my $stored = $obj->unix_crypt('himitsu', 'ab');

    is($obj->unix_crypt('himitsu', $stored), $stored,
       'the right password crypts to the stored value');
    isnt($obj->unix_crypt('chigau', $stored), $stored,
	 'a wrong password does not');
};


# ---------------------------------------------------------------------
# 4. what the bundled module used to answer
#
# Hashes made by Crypt::UnixCrypt are in the maps of every running
# installation.  They have to keep verifying after the module is gone,
# which is the only thing that made removing it safe.
# ---------------------------------------------------------------------
subtest 'hashes made by the module that was removed still verify' => sub {
    # made by Crypt::UnixCrypt 1.0 before it was deleted
    my %old = (
	'fml'      => 'abElTpU575Od6',
	'password' => 'abJnggxhB/yWI',
	'fml8'     => 'abmfi7AdHg/6U',
    );

    for my $text (sort keys %old) {
	is($obj->unix_crypt($text, $old{ $text }), $old{ $text },
	   "'$text' still verifies against its old hash");
    }
};


# ---------------------------------------------------------------------
# 5. eight characters, which is not new and is not fixed here
#
# DES crypt reads eight characters and drops the rest.  The module did
# the same, so this branch changes nothing about it -- but a defect
# that no test names is one nobody finds again.
# ---------------------------------------------------------------------
subtest 'DES crypt still stops at eight characters' => sub {
    my $a = $obj->unix_crypt('abcdefgh',  'ab');
    my $b = $obj->unix_crypt('abcdefghX', 'ab');

    {
	local $TODO = 'DES truncation: a longer password is not a stronger one';
	isnt($a, $b, 'a ninth character makes a difference');
    }

    is($a, $b, 'and until it does, these are one password')
	or diag("this host does not truncate; the TODO above can go");
};


# ---------------------------------------------------------------------
# 6. the guard
#
# On a libc without classic DES -- libxcrypt --disable-obsolete-api --
# crypt() cannot reproduce what a stored password was made with, and
# every password in the map stops matching at once.  That must say so
# rather than look like everybody mistyping.
# ---------------------------------------------------------------------
subtest 'a host that cannot do DES is told, not guessed at' => sub {
    my $answer = 0;

    no warnings 'redefine';
    no strict 'refs';
    my $real = \&FML::Crypt::_libc_does_des;
    local *FML::Crypt::_libc_does_des = sub { return $answer };

    my $got = eval { $obj->unix_crypt('fml', 'ab') };
    ok(!defined($got), 'unix_crypt() returns nothing');
    like($@, qr/cannot do DES/, 'and says why');

    $answer = 1;
    is($obj->unix_crypt('fml', 'ab'), 'abElTpU575Od6',
       'and answers again once the guard passes');
};


done_testing();

1;
