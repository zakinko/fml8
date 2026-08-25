#-*- perl -*-
#
# Which addresses each generation accepts.
#
# fml4 guards command arguments with __SecureP() in kern/libkernsubr.pl:
# one character class, and anything outside it is not merely refused but
# mailed to the maintainer as a security alert.  fml8 replaced that with
# FML::Restriction::Base, which names a regexp per kind of data.
#
# fml4 cannot be loaded to ask it directly -- it wants its whole kernel
# in place -- so the class is read out of its source and applied here.
# That is the same predicate, not a paraphrase of it.
#
# The two do not agree, and the disagreement is deliberate: fml4 leaves
# "+" out of the class, so plus addressing is refused and reported as an
# attack.  fml8 includes it.  That difference is recorded rather than
# smoothed over, because fml4 is not being changed -- see the fml4
# commit "Record the defects whose repair would change what fml4 does".
#

use strict;
use warnings;
use Test::More;
use lib 't';

# cpan/lib and img/lib go on the end of @INC, so that a module the host
# has installed wins over the bundled copy.  It used to matter more than
# that: cpan/lib carried File::Spec 0.7, which lacks splitdir() and
# splitpath(), and putting it first broke fml8 and prove(1) alike.  That
# copy is gone now, but the order is still the right way round.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use ParityFML4;
use FML::Restriction::Base;

plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless ParityFML4::fml4_dir();

my $CLASS = ParityFML4::fml4_secure_class();
plan skip_all => "could not read fml4's __SecureP() character class"
    unless length($CLASS);

my $FML4_RE = qr/^[$CLASS]+$/;
my $SAFE    = new FML::Restriction::Base;


# Descriptions: would fml4's __SecureP() accept this string?
#               only the character class is applied; the ";" and "|"
#               branch below it only decides which complaint is logged.
#    Arguments: STR($s)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub fml4_accepts
{
    my ($s) = @_;

    return $s =~ $FML4_RE ? 1 : 0;
}


# Descriptions: would fml8 accept this as an address?
#    Arguments: STR($s)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub fml8_accepts
{
    my ($s) = @_;

    return $SAFE->regexp_match('address', $s) ? 1 : 0;
}


# ---------------------------------------------------------------------
# 1. ordinary addresses: both must accept
# ---------------------------------------------------------------------
subtest 'plain addresses are accepted by both' => sub {
    my @ok = (
	'user@example.jp',
	'taro@example.co.jp',
	'a.b@example.jp',
	'a-b@example.jp',
	'a_b@example.jp',
	'user123@example123.jp',
	'UPPER@EXAMPLE.JP',
    );

    for my $a (@ok) {
	ok(fml4_accepts($a), "fml4 accepts $a");
	ok(fml8_accepts($a), "fml8 accepts $a");
    }
};


# ---------------------------------------------------------------------
# 2. shell metacharacters: both must refuse
#
# This is what the guard is for.  fml8 refusing something fml4 refused
# is the property that must never regress.
# ---------------------------------------------------------------------
subtest 'dangerous input is refused by both' => sub {
    my @bad = (
	'user@example.jp; rm -rf /',
	'user@example.jp | cat',
	'user@example.jp`id`',
	'user@example.jp$(id)',
	'user@example.jp&whoami',
	'user@example.jp > /tmp/x',
	'../../etc/passwd',
	'user@example.jp\'',
	'user@example.jp"',
    );

    for my $a (@bad) {
	my $shown = $a; $shown =~ s/\n/\\n/g;
	ok(!fml4_accepts($a), "fml4 refuses $shown");
	ok(!fml8_accepts($a), "fml8 refuses $shown");
    }
};


# ---------------------------------------------------------------------
# 3. the plus form: the one deliberate disagreement
# ---------------------------------------------------------------------
subtest 'plus addressing: fml8 accepts what fml4 refuses' => sub {
    my @plus = (
	'user+tag@example.jp',
	'user+ml@example.co.jp',
	'a+b+c@example.jp',
    );

    for my $a (@plus) {
	ok(!fml4_accepts($a),
	   "fml4 refuses $a, and mails the maintainer a security alert");
	ok(fml8_accepts($a), "fml8 accepts $a");
    }

    # Stated as a property so it fails if fml4 is quietly changed.
    unlike($CLASS, qr/\\\+/,
	   'fml4\'s class still has no "+", as its XXX-TODO says');
};


# ---------------------------------------------------------------------
# 4. fml8 must not have become more permissive than fml4 anywhere else
#
# The plus form above is the only difference that is allowed.  Anything
# else fml8 accepts and fml4 refuses is a widening nobody decided on.
# ---------------------------------------------------------------------
subtest 'no other widening of what is accepted' => sub {
    my @corpus = (
	'user@example.jp', 'a.b@example.jp', 'a-b@example.jp',
	'a_b@example.jp',  'user+tag@example.jp',
	'user%example.jp@relay.jp',
	'user!example.jp',
	'user@[192.0.2.1]',
	'user@example.jp,other@example.jp',
	'"quoted user"@example.jp',
	'user(comment)@example.jp',
	'user@exa mple.jp',
	'user@example.jp/../etc',
	'user@@example.jp',
	'@example.jp',
	'user@',
	'',
    );

    my @widened = ();
    for my $a (@corpus) {
	push @widened, $a if fml8_accepts($a) && !fml4_accepts($a);
    }

    is_deeply(\@widened, [ 'user+tag@example.jp' ],
	      'the plus form is the only thing fml8 accepts and fml4 does not')
	or diag("also widened: @widened");
};


# ---------------------------------------------------------------------
# 5. fml8 is stricter where it should be
#
# fml4's class is a single blunt test applied to whole command lines, so
# it lets through plenty that is not an address at all: it has to, since
# the same predicate guards "mget 100,last:10".  fml8 asks a narrower
# question and should refuse those.
# ---------------------------------------------------------------------
subtest 'fml8 is narrower where fml4 had to be broad' => sub {
    my @not_an_address = (
	'mget 100,last:10',
	'100.tar.gz',
	'# command',
	'subscribe Taro Yamada',
	'help',
    );

    for my $s (@not_an_address) {
	ok(fml4_accepts($s),
	   "fml4's class accepts \"$s\", since it guards command lines too");
	ok(!fml8_accepts($s),
	   "fml8 refuses \"$s\" as an address");
    }
};


# ---------------------------------------------------------------------
# 6. fml8's other data kinds are distinct from address
#
# fml8 gained the ability fml4 lacked: asking about a command name or a
# file name separately.  If those regexps were all the same the gain
# would be nominal.
# ---------------------------------------------------------------------
subtest 'fml8 distinguishes the kinds of data fml4 could not' => sub {
    ok($SAFE->regexp_match('command', 'subscribe'), 'command: subscribe');
    ok(!$SAFE->regexp_match('command', 'user@example.jp'),
       'command: an address is not a command name');

    ok($SAFE->regexp_match('address', 'user@example.jp'), 'address: ok');
    ok(!$SAFE->regexp_match('address', 'subscribe'),
       'address: a bare word is not an address');

    ok($SAFE->regexp_match('article_id', '100'),   'article_id: 100');
    ok(!$SAFE->regexp_match('article_id', '100a'), 'article_id: not 100a');

    ok($SAFE->regexp_match('file', 'summary'), 'file: summary');
    ok(!$SAFE->regexp_match('file', '../etc/passwd'),
       'file: no traversal');
};


# ---------------------------------------------------------------------
# 7. whitespace, and what fml4's class lets through with it
#
# fml4's class contains \s, which in perl includes the newline, and the
# anchors are ^ and $ rather than \A and \z.  A string with an embedded
# newline therefore satisfies it, and so does anything on the lines
# after the first as long as it stays inside the class.
#
# In practice fml4 splits a command mail into lines before this guard
# sees it, so nothing is claimed here about whether that is reachable.
# What matters for parity is the direction: fml8 refuses these, so
# migrating cannot loosen anything.  That is worth pinning, because
# "fml8 is at least as strict" is the property the rest of this file
# rests on.
# ---------------------------------------------------------------------
subtest 'embedded newlines: fml4 admits them, fml8 does not' => sub {
    my @multiline = (
	"user\@example.jp\nBcc: attacker\@example.com",
	"user\@example.jp\nuser2\@example.jp",
	"a\nb",
    );

    for my $s (@multiline) {
	my $shown = $s; $shown =~ s/\n/\\n/g;
	ok(fml4_accepts($s),
	   "fml4's class admits \"$shown\", since \\s covers the newline");
	ok(!fml8_accepts($s), "fml8 refuses \"$shown\"");
    }

    # The mechanism, stated so that a change to fml4 is noticed.
    like($CLASS, qr/\\s/, 'fml4\'s class really does contain \\s');
};

done_testing();
