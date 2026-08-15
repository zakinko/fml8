#-*- perl -*-
#
# Password hashing, and whether the bundled crypt can be dropped.
#
# FML::Crypt::unix_crypt() calls Crypt::UnixCrypt, a pure perl
# implementation of traditional DES crypt(3), and its comment says
# "always use this module's crypt" -- so passing over perl's builtin
# crypt() was a decision rather than an oversight.
#
# The reason is worth stating, because the bundle otherwise looks like
# another module the core has made redundant.  The builtin calls the
# host's crypt(3), and what that does is not the same everywhere: glibc
# and libxcrypt have been narrowing DES support for years and some
# builds refuse it outright, while others return a different result for
# the same input.  A pure perl implementation answers identically on
# every host, which is what a stored password hash needs -- it has to
# verify on the machine the list was moved to, not just the one it was
# set on.
#
# So this does two things.  It pins Crypt::UnixCrypt against fixed
# vectors, so that swapping the implementation is caught here rather
# than by subscribers who can no longer log in.  And it compares the
# two implementations and reports what it finds, without failing: on a
# host where they agree the bundle could go, on one where they do not
# it must stay, and the answer is a property of the host rather than of
# fml8.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

# cpan/lib and img/lib go on the end of @INC, so that a module the host
# has installed wins over the bundled copy.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use Crypt::UnixCrypt;
use FML::Crypt;

# Traditional DES crypt(3), which has one answer and has had it since
# 1979.  Taken from the implementation under test and checked against
# perl's builtin on a host that still does DES; they are here so that a
# change of implementation has something to fail against.
my @VECTOR = (
    [ 'password', 'ab', 'abJnggxhB/yWI' ],
    [ 'secret',   'xy', 'xy/gRonXQz8UE' ],
    [ 'fml8',     'Zz', 'Zz9GUwvAQLkvs' ],
    [ 'a',        'aa', 'aafKPWZb/dLAs' ],
);


# ---------------------------------------------------------------------
# 1. the bundled implementation is the one we think it is
# ---------------------------------------------------------------------
subtest 'Crypt::UnixCrypt answers the fixed vectors' => sub {
    for my $v (@VECTOR) {
	my ($text, $salt, $want) = @$v;
	is(Crypt::UnixCrypt::crypt($text, $salt), $want,
	   "crypt('$text', '$salt') = $want");
    }

    # The salt is the first two characters of the result, which is how
    # a stored hash carries its own salt.
    for my $v (@VECTOR) {
	my ($text, $salt, $want) = @$v;
	is(substr($want, 0, 2), $salt, "$want carries its salt");
    }
};


# ---------------------------------------------------------------------
# 2. FML::Crypt hands through to it unchanged
#
# FML::Crypt is described as an adapter, so it must not be quietly
# doing something else.
# ---------------------------------------------------------------------
subtest 'FML::Crypt::unix_crypt() is that implementation' => sub {
    my $crypt = new FML::Crypt;

    ok(defined $crypt, 'FML::Crypt constructs');
    can_ok($crypt, 'unix_crypt');

    for my $v (@VECTOR) {
	my ($text, $salt, $want) = @$v;
	is($crypt->unix_crypt($text, $salt), $want,
	   "FML::Crypt->unix_crypt('$text', '$salt')");
    }
};


# ---------------------------------------------------------------------
# 3. verification works, which is the only thing this is for
# ---------------------------------------------------------------------
subtest 'a stored hash verifies, and a wrong password does not' => sub {
    my $crypt = new FML::Crypt;

    for my $v (@VECTOR) {
	my ($text, undef, $stored) = @$v;

	# Verification re-runs crypt with the stored hash as the salt.
	is($crypt->unix_crypt($text, $stored), $stored,
	   "'$text' verifies against $stored");

	# A wrong password has to differ within the first eight
	# characters to be a wrong password at all; see below.
	my $wrong = 'X' . substr($text, 1);
	isnt($crypt->unix_crypt($wrong, $stored), $stored,
	     "'$wrong' does not");
    }

    # Non-ASCII goes through as octets rather than being rejected: a
    # password is whatever the subscriber typed.
    my $jp = "\xc6\xfc\xcb\xdc\xb8\xec";
    my $h  = $crypt->unix_crypt($jp, 'jp');
    like($h, qr/^jp\S+$/, "a non-ASCII password hashes to $h");
    is($crypt->unix_crypt($jp, $h), $h, 'and verifies');
};


# ---------------------------------------------------------------------
# 4. eight characters, and no more
#
# Traditional DES crypt(3) hashes the first eight characters of the
# password and discards the rest.  That is not a defect in
# Crypt::UnixCrypt -- it is what the algorithm is -- but it is a
# property of fml8's stored passwords that nothing states anywhere, and
# it is the kind of thing a maintainer should know before telling
# subscribers to pick a long one.
#
# This is why the storage scheme had to change rather than merely
# gaining a longer salt, and it is still the behaviour of every password
# an existing installation is carrying.  Those keep verifying -- see
# subtest 8 -- so a subscriber who set a long password before the change
# can still log in with the first eight characters of it, until the
# password is changed and re-stored under the new scheme.
# ---------------------------------------------------------------------
subtest 'the old scheme counted only the first eight characters' => sub {
    my $crypt = new FML::Crypt;

    my $eight = 'abcdefgh';
    my $more  = $eight . 'ijklmnop';

    is($crypt->unix_crypt($more,  'ab'), $crypt->unix_crypt($eight, 'ab'),
       "'$more' and '$eight' hash the same");

    # So a subscriber who set a long password can log in with the first
    # eight characters of it.
    my $stored = $crypt->unix_crypt($more, 'ab');
    is($crypt->unix_crypt($eight, $stored), $stored,
       'the truncation verifies against the full password');

    # A difference inside the first eight is a different password.
    isnt($crypt->unix_crypt('abcdefgX', 'ab'), $crypt->unix_crypt($eight, 'ab'),
	 'a change within the first eight does change the hash');

    # And the new scheme does not do this, which is the point.
    my $h = $crypt->hash($more);
    ok($crypt->verify($more,  $h), 'the new scheme verifies the long one');
    ok(!$crypt->verify($eight, $h),
       'and refuses its first eight characters');

    local $TODO = 'passwords stored before this change are still eight long';
    isnt($crypt->unix_crypt($more, 'ab'), $crypt->unix_crypt($eight, 'ab'),
	 'an existing stored password uses more than eight characters');
};


# ---------------------------------------------------------------------
# 5. what the host's own crypt(3) would say
#
# Reported, not asserted.  If every host CI runs on agrees, the bundle
# is redundant and can go; if any disagrees or refuses, it has to stay,
# and this says which.
# ---------------------------------------------------------------------
subtest "the host's builtin crypt(), for comparison" => sub {
    my $builtin_works = 1;
    my $why           = '';

    my $probe = eval { crypt('password', 'ab') };
    if ($@ || !defined $probe || $probe eq '') {
	$builtin_works = 0;
	$why = $@ || 'returned nothing';
	$why =~ s/\s+$//;
    }

    note("builtin crypt('password','ab') = " .
	 (defined $probe ? "'$probe'" : 'undef'));

    unless ($builtin_works) {
	note("this host has no usable DES crypt(3): $why");
	note("the bundled Crypt::UnixCrypt is doing real work here");
	ok(1, 'recorded');
	return;
    }

    my $agree = 0;
    for my $v (@VECTOR) {
	my ($text, $salt, $want) = @$v;
	my $got = crypt($text, $salt);
	$got = '(undef)' unless defined $got;

	if ($got eq $want) {
	    $agree++;
	    note("agrees on '$text': $got");
	}
	else {
	    note("DIFFERS on '$text': builtin $got, bundled $want");
	}
    }

    note(sprintf("builtin agrees with the bundle on %d of %d vectors",
		 $agree, scalar(@VECTOR)));

    # Stated as a TODO so that the day every host agrees is visible in
    # the run, rather than something someone has to go and check.
    local $TODO = "the bundle stays until every host CI runs on agrees";
    is($agree, scalar(@VECTOR),
       'the host crypt(3) could replace Crypt::UnixCrypt here');
};

# ---------------------------------------------------------------------
# 6. the scheme new passwords are stored with
#
# NIST SP 800-63B requires that a verifier "SHALL request the password
# to be provided in full ... and SHALL verify the entire submitted
# password (e.g., not truncate it)", that the salt "SHALL be at least
# 32 bits in length", and that the password be hashed with a suitable
# password hashing scheme.  Traditional crypt(3) failed all three, and
# fml8 made the salt worse by taking it from the process id.
# ---------------------------------------------------------------------
subtest 'hash() meets the storage requirements' => sub {
    my $crypt = new FML::Crypt;

    my $pw = 'correct horse battery staple';
    my $h  = $crypt->hash($pw);

    like($h, qr/^\$pbkdf2-sha256\$\d+\$[^\$]+\$.+$/,
	 "stored as a self-identifying string: $h");

    my (undef, undef, $rounds, $salt_b64, $dk_b64) = split(/\$/, $h);

    cmp_ok($rounds, '>=', 100_000, "iteration count $rounds");

    use MIME::Base64 ();
    my $salt = MIME::Base64::decode_base64($salt_b64);
    cmp_ok(length($salt) * 8, '>=', 32,
	   sprintf("salt is %d bits, at least 32", length($salt) * 8));

    my $dk = MIME::Base64::decode_base64($dk_b64);
    is(length($dk), 32, 'the derived key is a full SHA-256 block');

    # The salt is random, so the same password stored twice differs.
    isnt($crypt->hash($pw), $h, 'two hashes of one password differ');
    ok($crypt->verify($pw, $crypt->hash($pw)), 'and both verify');
};


# ---------------------------------------------------------------------
# 7. the whole password counts now
#
# This is the requirement traditional crypt(3) could not meet, and the
# reason the scheme had to change rather than merely gaining a longer
# salt.
# ---------------------------------------------------------------------
subtest 'the entire password is verified, however long' => sub {
    my $crypt = new FML::Crypt;

    my $pw = 'abcdefgh';
    my $h  = $crypt->hash($pw);

    ok(!$crypt->verify('abcdefghX',  $h), 'a ninth character is noticed');
    ok(!$crypt->verify('abcdefg',    $h), 'a shorter one is not accepted');
    ok($crypt->verify($pw, $h),           'and the password itself is');

    # SP 800-63B: verifiers SHOULD permit at least 64 characters.
    my $long = 'x' x 200;
    my $lh   = $crypt->hash($long);
    ok($crypt->verify($long, $lh), '200 characters verify');
    ok(!$crypt->verify(('x' x 199), $lh), 'and 199 do not');

    # A password is whatever the subscriber typed, including spaces and
    # octets outside ASCII.
    for my $p ('with spaces in it', "\xc6\xfc\xcb\xdc\xb8\xec", 'ends with ') {
	my $ph = $crypt->hash($p);
	ok($crypt->verify($p, $ph), "verifies: '" . $p . "'");
    }
};


# ---------------------------------------------------------------------
# 8. an installation keeps its existing passwords
#
# The migration has to be invisible: a list moved to this version must
# authenticate its administrators with the passwords they already have,
# and only start using the new scheme as those are changed.
# ---------------------------------------------------------------------
subtest 'passwords stored by earlier versions still verify' => sub {
    my $crypt = new FML::Crypt;

    for my $v (@VECTOR) {
	my ($text, undef, $stored) = @$v;

	ok($crypt->verify($text, $stored),
	   "the old hash $stored still verifies '$text'");
	ok($crypt->is_legacy($stored), "and is recognised as old");

	# A wrong password against an old hash is still wrong.
	ok(!$crypt->verify('X' . substr($text, 1), $stored),
	   'a wrong password against an old hash is refused');
    }

    my $new = $crypt->hash('whatever');
    ok(!$crypt->is_legacy($new), 'a new hash is not called old');

    # is_legacy() is what a caller uses to decide to store the password
    # again after a successful check, which is how a list migrates
    # without asking anyone to choose a new password.
    ok($crypt->verify('password', 'abJnggxhB/yWI'), 'old verifies');
    my $upgraded = $crypt->hash('password');
    ok($crypt->verify('password', $upgraded), 'and re-storing it works');
    ok(!$crypt->is_legacy($upgraded), 'leaving it on the new scheme');
};


# ---------------------------------------------------------------------
# 9. rubbish in the password file does not authenticate anybody
# ---------------------------------------------------------------------
subtest 'malformed stored entries are refused' => sub {
    my $crypt = new FML::Crypt;

    my @junk = (
	'',
	'$pbkdf2-sha256$',
	'$pbkdf2-sha256$600000$',
	'$pbkdf2-sha256$600000$notbase64$notbase64',
	'$unknown-scheme$1$a$b',
	'*',
	'!',
    );

    for my $j (@junk) {
	my $shown = $j eq '' ? '(empty)' : $j;
	ok(!$crypt->verify('password', $j), "refused: $shown");
	ok(!$crypt->verify('',         $j), "refused with empty password: $shown");
    }

    ok(!$crypt->verify(undef, 'abJnggxhB/yWI'), 'undef password refused');
    ok(!$crypt->verify('password', undef),      'undef entry refused');
};


# ---------------------------------------------------------------------
# 10. what it costs
#
# SP 800-63B asks for a cost factor "as high as practical without
# negatively impacting verifier performance".  Recorded rather than
# asserted, because what is practical depends on the host, and this
# runs on whatever CI was given.
# ---------------------------------------------------------------------
subtest 'the cost of one verification' => sub {
    my $crypt = new FML::Crypt;

    my $t0 = time;
    my $h  = $crypt->hash('password');
    my $t1 = time;
    ok($crypt->verify('password', $h), 'verified');
    my $t2 = time;

    note(sprintf("hash %d s, verify %d s on this host", $t1 - $t0, $t2 - $t1));

    # Slow is the point, but not so slow that a list stops answering.
    cmp_ok($t2 - $t1, '<', 10, 'one verification takes under ten seconds');
};

# ---------------------------------------------------------------------
# 11. the length remark, and that it is only a remark
#
# SP 800-63B requires 15 characters for a password used as a single
# factor, which an fml8 administrator password is.  fml8 tells the
# owner rather than refusing: the command interface is mail, so there
# is nothing to answer, and refusing would break whatever already calls
# makefml changepassword.
# ---------------------------------------------------------------------
subtest 'the two length lines, and what each one does' => sub {
    my $crypt = new FML::Crypt;

    is($crypt->password_length_hard_limit(),  10,
       'below ten is refused, which is where NISC puts the safe range');
    is($crypt->password_length_lower_limit(), 15,
       'below fifteen is remarked on, which SP 800-63B asks of a single factor');

    # refused
    ok($crypt->is_too_short('short'),        '5 characters is too short');
    ok($crypt->is_too_short('abcdefgh'),     '8 is too short');
    ok($crypt->is_too_short('abcdefghi'),    '9 is too short');
    ok(!$crypt->is_too_short('abcdefghij'),  '10 is not');
    ok($crypt->is_too_short(undef),          'no password at all is too short');
    ok($crypt->is_too_short(''),             'nor is an empty one accepted');

    # Ten rather than eight, because the old scheme stopped at eight:
    # an eight character password is exactly what changing it was
    # supposed to move away from.
    cmp_ok($crypt->password_length_hard_limit(), '>', 8,
	   'and the line is above what the old scheme could hold');

    # remarked on
    ok($crypt->is_short('abcdefghij'),        '10 is worth a remark');
    ok($crypt->is_short('abcdefghijklmn'),    '14 is');
    ok(!$crypt->is_short('abcdefghijklmno'),  '15 is not');
    ok(!$crypt->is_short('a' x 200),          'and neither is 200');

    # The middle band is stored, which is the point of it being a
    # remark rather than a refusal.
    my $ten = 'abcdefghij';
    my $h   = $crypt->hash($ten);
    ok($crypt->verify($ten, $h), 'a ten character password still works');
    ok(!$crypt->is_legacy($h),   'and is stored in the new scheme');

    # No composition rule: SP 800-63B says a verifier SHALL NOT impose
    # one, so length is the only thing asked about.
    for my $p ('aaaaaaaaaaaaaaa', '123456789012345', '               ') {
	ok(!$crypt->is_too_short($p), "accepted whatever it is made of");
    }
};


# ---------------------------------------------------------------------
# 12. the old scheme is never migrated behind the owner's back
#
# Tempting, and wrong.  Verification against an old hash passes on the
# first eight characters, so someone who guessed those and no more
# would have their guess re-stored as the password, locking out whoever
# set it.  is_legacy() exists to prompt a change, not to perform one.
# ---------------------------------------------------------------------
subtest 'guessing eight characters must not become the password' => sub {
    my $crypt = new FML::Crypt;

    my $real  = 'abcdefghijklmnop';           # what the owner set
    my $eight = substr($real, 0, 8);          # what an attacker guesses
    my $old   = $crypt->unix_crypt($real, 'ab');

    # The old scheme cannot tell them apart; that is the whole problem.
    ok($crypt->verify($eight, $old), 'the guess passes against the old hash');
    ok($crypt->verify($real,  $old), 'so does the real password');
    ok($crypt->is_legacy($old),      'and the hash is flagged as old');

    # Had it been re-stored from the guess, the owner would be locked
    # out.  Show what that would have cost.
    my $would_have_been = $crypt->hash($eight);
    ok(!$crypt->verify($real, $would_have_been),
       'auto-migrating the guess would have locked the owner out');

    # Whereas migrating through a password the owner supplied is fine.
    my $migrated = $crypt->hash($real);
    ok($crypt->verify($real, $migrated),   'the owner can still get in');
    ok(!$crypt->verify($eight, $migrated), 'and the guess no longer works');
};

# ---------------------------------------------------------------------
# 13. the blocklist
#
# SP 800-63B: a verifier "SHALL compare the prospective secret against a
# blocklist that contains known commonly used, expected, or compromised
# passwords".  Three kinds, checked cheapest first.
#
# The network one is not exercised here; see the subtest after this.
# ---------------------------------------------------------------------
subtest 'expected and commonly used passwords are refused' => sub {
    my $crypt = new FML::Crypt;

    # "expected": anything printed in every message the list sends.
    my $terms = [ 'elena', 'example.jp', 'taro' ];

    for my $p ('elena', 'elena2026', 'MyTaroPassword', 'x-example.jp-x') {
	ok($crypt->blocklist_reason($p, { terms => $terms }),
	   "refused: $p");
    }

    for my $p ('quiet lamp orbit tuesday', 'zzzz9999zzzz') {
	is($crypt->blocklist_reason($p, { terms => $terms }), '',
	   "accepted: $p");
    }

    # Case does not make it a secret.
    ok($crypt->blocklist_reason('ELENA-forever', { terms => $terms }),
       'the comparison is case insensitive');

    # A term too short to mean anything is ignored, or every password
    # with an "a" in it would be refused.
    is($crypt->blocklist_reason('a password', { terms => [ 'a', 'ml' ] }), '',
       'terms under three characters are not used');

    # "commonly used": the site's own file.
    my $file = "/tmp/fml8-blocklist.$$";
    open(my $fh, '>', $file) or do { fail("cannot write $file"); return };
    print $fh "# lines beginning with # are comments\n";
    print $fh "P\@ssw0rd123\n";
    print $fh "letmein12345\n";
    print $fh "\n";
    close($fh);

    ok($crypt->blocklist_reason('P@ssw0rd123', { file => $file }),
       'refused: in the file');
    ok($crypt->blocklist_reason('p@ssw0rd123', { file => $file }),
       'and case does not help');
    is($crypt->blocklist_reason('# lines beginning with # are comments',
				{ file => $file }), '',
       'a comment line is not a password');
    is($crypt->blocklist_reason('not in the file at all', { file => $file }),
       '', 'accepted: not in the file');

    unlink($file);

    # A file that is not there is not an error.
    is($crypt->blocklist_reason('anything', { file => '/nonexistent' }), '',
       'a missing file is not an obstacle');

    # And nothing configured means nothing objected.
    is($crypt->blocklist_reason('anything', {}), '', 'no checks, no refusal');
    is($crypt->blocklist_reason('', {}), '', 'an empty password is not for this to judge');
};


# ---------------------------------------------------------------------
# 14. the breach service, and what it does when it cannot be reached
#
# fml8 asks it by default; FML::Crypt does not, since a library should
# not reach the network merely because it was called.  Both halves are
# checked: that the flag is what decides, and that a service which is
# not there stops nothing.
# ---------------------------------------------------------------------
subtest 'the breach lookup is asked for, and fails open' => sub {
    my $crypt = new FML::Crypt;

    # The library itself does not go out unless told to.  "password" is
    # the most breached string there is, and without use_service nothing
    # asks about it.
    is($crypt->blocklist_reason('password', {}), '',
       'the library does not reach the network unasked');

    # unreachable must not stop a password being changed.
    my $r = $crypt->blocklist_reason('password', {
	use_service => 1,
	service_url => 'https://127.0.0.1:1/range',
	timeout     => 2,
    });
    is($r, '', 'an unreachable service accepts rather than blocks');

    # The real thing, when there is a network to reach it over.
    my $live = $crypt->blocklist_reason('password', {
	use_service => 1,
	timeout     => 10,
    });

  SKIP: {
	skip("no network, or the service did not answer", 2) unless $live;

	like($live, qr/breach/, "refused: $live");
	like($live, qr/\d/,     'and says how often it has been seen');
    }

    # Something nobody has ever used should not be in breach data.  If
    # it is, that is worth knowing rather than worth failing over.
    my $unique = 'fml8-' . join('-', map { $_ * 7919 } (1 .. 6));
    my $u = $crypt->blocklist_reason($unique, {
	use_service => 1,
	timeout     => 10,
    });
    is($u, '', "not in breach data: $unique");

    # And how fml8 itself decides.  A configuration setting wins;
    # otherwise the answer given at a terminal; otherwise it does not
    # ask the service at all.  Nothing turns it on by defaulting.
    my $file = 'fml/lib/FML/Command/Admin/changepassword.pm';
    open(my $fh, '<', $file) or do { fail("cannot read $file"); return };
    local $/ = undef;
    my $src = <$fh>;
    close($fh);

    like($src, qr/_use_blocklist_service/,
	 'the decision is made in one place');

    my ($sub) = $src =~ /(sub _use_blocklist_service.*?\n\})/s;
    ok($sub, 'found it');

    like($sub || '', qr/return 1 if \$set eq 'yes'/,  'a config yes wins');
    like($sub || '', qr/return 0 if \$set eq 'no'/,   'and a config no wins');
    like($sub || '', qr/blocklist_service_decision/,
	 'otherwise the answer given at a terminal decides');
    unlike($sub || '', qr/\|\|\s*'yes'/,
	   'and nothing turns it on merely by defaulting');
};


# ---------------------------------------------------------------------
# 15. the length checks alone would not have been enough
#
# The reason the blocklist is on by default, stated as a test rather
# than as an assertion in a commit message.
# ---------------------------------------------------------------------
subtest 'a long password can still be one everybody has used' => sub {
    my $crypt = new FML::Crypt;

    my $famous = 'correct horse battery staple';

    cmp_ok(length($famous), '>', $crypt->password_length_lower_limit(),
	   sprintf("%d characters, past both length lines", length($famous)));
    ok(!$crypt->is_too_short($famous), 'so it is not refused for length');
    ok(!$crypt->is_short($famous),     'nor even remarked on');

    my $r = $crypt->blocklist_reason($famous, {
	use_service => 1,
	timeout     => 10,
    });

  SKIP: {
	skip("no network, or the service did not answer", 1) unless $r;
	like($r, qr/breach/, "and yet: $r");
    }
};

# ---------------------------------------------------------------------
# 16. the one question fml asks
#
# The breach lookup is the only thing here that leaves the host, so it
# is not turned on by a default.  The question is put once, at a
# terminal, the first time a command line tool runs after this release
# is installed, and the answer is kept.  Mail arrives without a
# terminal, so nothing is ever asked while handling a message, and an
# installation nobody has answered for does not use the service.
# ---------------------------------------------------------------------
subtest 'the breach lookup is asked about before it is used' => sub {
    my $crypt = new FML::Crypt;

    my $dir = "/tmp/fml8-crypt-decision.$$";
    mkdir($dir) or do { fail("cannot make $dir"); return };

    my $file = "$dir/password_blocklist_service";

    is($crypt->blocklist_service_decision($dir), '',
       'nobody has been asked yet');

    # With no terminal and no handle to read from, nothing is asked and
    # nothing is written.  This is the path mail takes.
    is($crypt->ask_blocklist_service($dir), '', 'no terminal, no question');
    ok(!-f $file, 'and nothing was recorded');

    # The answers it takes.  Return on its own is the default, which is
    # yes; turning it off has to be said.
    for my $t ([ "\n",    'yes' ], [ "   \n", 'yes' ],
	       [ "yes\n", 'yes' ], [ "y\n",   'yes' ],
	       [ "no\n",  'no'  ], [ "N\n",   'no'  ],
	       [ "NO\n",  'no'  ]) {
	my ($input, $want) = @$t;

	unlink($file);
	open(my $in, '<', \$input) or next;

	# The prompt itself is not what is under test.
	open(my $null, '>', '/dev/null') or next;
	my $old = select($null);
	my $got = $crypt->ask_blocklist_service($dir, $in);
	select($old);
	close($null);

	(my $shown = $input) =~ s/\n/\\n/g;
	is($got, $want, "answered \"$shown\" -> $want");
	is($crypt->blocklist_service_decision($dir), $want, 'and remembered');
    }

    # Once answered it is not asked again, whatever is on the handle.
    {
	my $input = "no\n";
	open(my $in, '<', \$input);
	is($crypt->ask_blocklist_service($dir, $in), 'no',
	   'the recorded answer is returned without asking');
    }

    # Nothing usable said: not recorded, so the question comes back.
    unlink($file);
    for my $input ("maybe\nperhaps\nwho knows\n", "") {
	open(my $in, '<', \$input) or next;
	open(my $null, '>', '/dev/null') or next;
	my $old = select($null);
	my $got = $crypt->ask_blocklist_service($dir, $in);
	select($old);
	close($null);

	is($got, '', 'no usable answer, so none recorded');
	ok(!-f $file, 'and the file was not created');
    }

    # Only yes and no can be written.
    ok(!$crypt->record_blocklist_service_decision($dir, 'maybe'),
       'a decision that is neither is refused');
    ok($crypt->record_blocklist_service_decision($dir, 'yes'), 'yes is kept');
    is($crypt->blocklist_service_decision($dir), 'yes', 'and read back');

    # A file with something unreadable in it counts as undecided rather
    # than as permission.
    if (open(my $fh, '>', $file)) {
	print $fh "# comment only\n";
	close($fh);
    }
    is($crypt->blocklist_service_decision($dir), '',
       'a file that says nothing is not a yes');

    unlink($file);
    rmdir($dir);

    is($crypt->blocklist_service_decision('/nonexistent'), '',
       'no config directory, no decision');
    is($crypt->blocklist_service_decision(undef), '', 'and undef is safe');

    # The config directory usually belongs to root or to the fml owner,
    # and whoever runs makefml may be neither.  The answer still holds
    # for this run; what cannot happen is it being lost silently.
  SKIP: {
	skip("running as root, so everything is writable", 3) if $> == 0;

	my $ro = "/tmp/fml8-crypt-readonly.$$";
	mkdir($ro) or skip("cannot make $ro", 3);
	chmod(0500, $ro) or do { rmdir($ro); skip("cannot chmod $ro", 3) };

	my $input = "yes\n";
	open(my $in, '<', \$input) or do { rmdir($ro); skip("no handle", 3) };
	open(my $null, '>', '/dev/null') or do { rmdir($ro); skip("no null", 3) };
	my $old = select($null);
	my $got = $crypt->ask_blocklist_service($ro, $in);
	select($old);
	close($null);

	is($got, 'yes', 'the answer is honoured for this run');
	ok(!-f "$ro/password_blocklist_service", 'but could not be written');
	is($crypt->blocklist_service_decision($ro), '',
	   'so the question comes back rather than being assumed');

	chmod(0700, $ro);
	rmdir($ro);
    }
};


# ---------------------------------------------------------------------
# 17. and the question is only ever put at a terminal
#
# Asking during mail handling would hang the process holding somebody's
# message.  Both halves of the guard are in the source rather than
# reachable from here, so this reads them.
# ---------------------------------------------------------------------
subtest 'nothing asks while a message is being handled' => sub {
    my $file = 'fml/lib/FML/Process/Switch.pm';
    ok(-f $file, "$file exists");

    open(my $fh, '<', $file) or do { fail("cannot read $file"); return };
    local $/ = undef;
    my $src = <$fh>;
    close($fh);

    like($src, qr/ask_blocklist_service/, 'the question is put at startup');
    like($src, qr/-t STDIN && -t STDOUT/,  'only when there is a terminal');
    like($src, qr/myname eq 'makefml' \|\| \$myname eq 'fml'/,
	 'and only from the command line tools');

    # The mail paths are named "command" and "fml.pl"; neither may
    # appear in the condition that decides whether to ask.
    my ($guard) = $src =~ /(if \(\(\$myname eq 'makefml'.*?\)\s*\{)/s;
    ok($guard, 'found the condition');
    unlike($guard || '', qr/'command'|'fml\.pl'/,
	   'the mail paths are not in it');
    like($guard || '', qr/_is_usage_request/,
	 'and asking for usage is not the moment either');
};

done_testing();
