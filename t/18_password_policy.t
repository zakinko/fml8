#-*- perl -*-
#
# What fml8 requires of a password, and what it does with one it is
# handed.
#
# t/40 covers the hashing: that PBKDF2 is what gets stored, that the
# whole password is verified rather than the first eight characters, and
# that what earlier versions wrote still verifies.  This file is about
# the two things either side of that.
#
# Before storage: the length policy.  Ten characters is a refusal and
# fifteen is a remark, and the reasoning is written out in FML::Crypt --
# NIST SP 800-63B says fifteen for a password used on its own, NISC's
# handbook says ten is the safe range, and ten rather than eight for the
# refusal because everything an existing installation holds was hashed
# by a scheme that only looked at eight, so a line drawn at eight would
# let somebody "change" their password and gain nothing.  Numbers with
# reasons behind them are worth pinning; they get rounded off otherwise.
#
# After it arrives: the masking.  A password comes in as plain text in
# the body of a mail, and the command buffer it arrives in is written to
# the log and quoted back in the reply.  rewrite_prompt() is what blanks
# it first.  That makes it a security control rather than a nicety, and
# a security control that works on most of its input is worth measuring
# exactly.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Crypt;

my $CRYPT = new FML::Crypt;

# The commands that take a password, and which of them sets one as
# opposed to supplying one for authentication.
my @PASSWORD_COMMAND = qw(password pass changepassword chpass passwd initpass);
my @SETS_A_PASSWORD  = qw(changepassword chpass passwd initpass);


# Descriptions: run $command's rewrite_prompt() over $buf and return
#               what it leaves behind.
#    Arguments: STR($command) STR($buf)
# Side Effects: none
# Return Value: STR
sub masked
{
    my ($command, $buf) = @_;
    my $pkg = "FML::Command::Admin::$command";

    eval "require $pkg";
    return $buf if $@;

    my $obj = $pkg->new();
    return $buf unless $obj->can('rewrite_prompt');

    my $copy = $buf;
    $obj->rewrite_prompt(undef, undef, \$copy);

    return $copy;
}


# ---------------------------------------------------------------------
# 1. the two limits
# ---------------------------------------------------------------------
subtest 'the length limits are the documented ones' => sub {
    is($CRYPT->password_length_hard_limit(),  10,
       'ten characters is the refusal');
    is($CRYPT->password_length_lower_limit(), 15,
       'fifteen is the remark');

    # The refusal has to be above eight, or a subscriber told to change
    # an eight character password could set another one and be no better
    # off: the old scheme hashed eight characters and discarded the rest.
    cmp_ok($CRYPT->password_length_hard_limit(), '>', 8,
	   'and the refusal is above what the old scheme could hash');

    cmp_ok($CRYPT->password_length_lower_limit(), '>=',
	   $CRYPT->password_length_hard_limit(),
	   'the remark is not below the refusal');
};


# ---------------------------------------------------------------------
# 2. the boundaries, exactly
#
# An off-by-one here is a whole character of password strength, and it
# is the kind of thing that reads correctly whichever way it is written.
# ---------------------------------------------------------------------
subtest 'is_too_short() draws the line where it says' => sub {
    my $hard = $CRYPT->password_length_hard_limit();

    is($CRYPT->is_too_short('x' x ($hard - 1)), 1,
       sprintf("%d characters is too short", $hard - 1));
    is($CRYPT->is_too_short('x' x $hard), 0,
       sprintf("%d characters is not", $hard));
    is($CRYPT->is_too_short('x' x ($hard + 1)), 0,
       sprintf("%d characters is not either", $hard + 1));
};


subtest 'is_short() draws its line where it says' => sub {
    my $low = $CRYPT->password_length_lower_limit();

    is($CRYPT->is_short('x' x ($low - 1)), 1,
       sprintf("%d characters is worth remarking on", $low - 1));
    is($CRYPT->is_short('x' x $low), 0,
       sprintf("%d characters is not", $low));
    is($CRYPT->is_short('x' x ($low + 1)), 0,
       sprintf("%d characters is not either", $low + 1));

    # Between the two lines: stored, but remarked on.
    my $between = 'x' x 12;
    is($CRYPT->is_too_short($between), 0, 'twelve characters is stored');
    is($CRYPT->is_short($between),     1, 'and remarked on');
};


# ---------------------------------------------------------------------
# 3. nothing at all
#
# A missing password must be too short rather than an exception or a
# quiet pass.  This is the shape of input that arrives when somebody
# sends "changepassword" with no argument.
# ---------------------------------------------------------------------
subtest 'an absent password is too short' => sub {
    my @warn = ();
    local $SIG{__WARN__} = sub { push @warn, $_[0] };

    is($CRYPT->is_too_short(undef), 1, 'undef is too short');
    is($CRYPT->is_too_short(''),    1, 'the empty string is too short');
    is($CRYPT->is_short(undef),     1, 'undef is short');
    is($CRYPT->is_short(''),        1, 'the empty string is short');

    is(scalar(@warn), 0, 'and nothing warned about an undefined value')
	or diag("warnings: @warn");
};


# ---------------------------------------------------------------------
# 4. length is the only rule
#
# SP 800-63B: a verifier "SHALL NOT impose other composition rules".  A
# long passphrase of nothing but lowercase letters and spaces is a good
# password, and a rule demanding a digit and a symbol makes it a worse
# one by pushing people towards Pa55word!.  So the absence of such a
# rule is a property worth asserting rather than an omission.
# ---------------------------------------------------------------------
subtest 'no composition rule is imposed' => sub {
    my %ok = (
	'a passphrase'        => 'correct horse battery staple',
	'all lowercase'       => 'abcdefghijklmnopqrst',
	'all digits'          => '01234567890123456789',
	'spaces only'         => (' ' x 20),
	'repeated character'  => ('a' x 20),
	'punctuation'         => '!!!!!!!!!!!!!!!!!!!!',
	'euc-jp octets'       => ("\xc6\xfc\xcb\xdc\xb8\xec" x 4),
	'utf-8 octets'        => ("\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e" x 3),
    );

    for my $name (sort keys %ok) {
	my $p = $ok{ $name };

	is($CRYPT->is_too_short($p), 0, "$name: accepted");

	# And it really can be stored and read back.
	my $stored = $CRYPT->hash($p);
	is($CRYPT->verify($p, $stored), 1, "$name: verifies");
    }
};


# ---------------------------------------------------------------------
# 5. the policy is enforced somewhere
#
# The limits are only a policy if something consults them.  hash() does
# not: it hashes whatever it is given and only croaks on undef, which is
# right -- it is the storage layer.  The command that sets a password is
# where the refusal belongs, and it is the only place that needs it,
# since "password" and "pass" supply a password for authentication
# rather than setting one.
# ---------------------------------------------------------------------
subtest 'the command that sets a password consults the limits' => sub {
    for my $command (@SETS_A_PASSWORD) {
	my $path = "fml/lib/FML/Command/Admin/$command.pm";
	ok(-f $path, "$command exists");

	# Follow @ISA: chpass, passwd and initpass are all thin wrappers.
	my $pkg = "FML::Command::Admin::$command";
	eval "require $pkg";
	is($@, '', "$command loads") or next;

	my @src = ($path);
	{
	    no strict 'refs';
	    for my $parent (@{ "${pkg}::ISA" }) {
		(my $f = $parent) =~ s{::}{/}g;
		push @src, "fml/lib/$f.pm" if -f "fml/lib/$f.pm";
	    }
	}

	my $found = 0;
	for my $f (@src) {
	    open(my $fh, '<', $f) or next;
	    local $/ = undef;
	    my $s = <$fh>;
	    close($fh);
	    $found = 1 if $s =~ /is_too_short/;
	}

	ok($found, "$command reaches is_too_short(), itself or through \@ISA");
    }

    # hash() itself does not refuse, and should not: it is storage.
    my $short = 'x';
    my $stored = eval { $CRYPT->hash($short) };
    is($@, '', 'hash() stores a short password without complaint');
    is($CRYPT->verify($short, $stored), 1, 'and it verifies');
};


# ---------------------------------------------------------------------
# 6. the password never survives the masking
#
# The command buffer goes into the log and into the reply.  Every
# command that carries a password has to blank it, and every one of them
# resolves rewrite_prompt(), directly or through @ISA.
# ---------------------------------------------------------------------
subtest 'every password command masks the secret' => sub {
    my $secret = 'SECRETPASSPHRASE1234';

    for my $command (@PASSWORD_COMMAND) {
	my $pkg = "FML::Command::Admin::$command";
	eval "require $pkg";
	is($@, '', "$command loads") or next;

	can_ok($pkg, 'rewrite_prompt');

	my $buf = "$command taro\@example.jp $secret";
	my $out = masked($command, $buf);

	unlike($out, qr/\Q$secret\E/, "$command: the secret is gone");
	like($out, qr/\*{4}/,         "$command: and something replaced it");
    }
};


# ---------------------------------------------------------------------
# 7. the forms the buffer really arrives in
#
# process() documents two, and they have different shapes:
#
#     command mail:  admin changepassword [$USER] $PASSWORD
#     command line:  makefml changepassword $ML $ADDR $PASSWORD
#
# The address is optional in the first, because a command mail already
# has a From: to take it from.  So the word after the keyword is the
# address in one form and the password itself in the other, and the
# masking has to tell them apart.
#
# It did not.  It kept the word after the keyword unconditionally, on
# the assumption that it was an address, so "admin changepassword
# PASSPHRASE" was written out in full -- and the " ********" appended
# after it then satisfied the guard that was there to catch exactly this,
# so the safe pattern never ran.  The buffer went to the log looking
# masked.
# ---------------------------------------------------------------------
subtest 'the masking covers the forms a command arrives in' => sub {
    my $secret = 'SECRETPASSPHRASE1234';
    my $old    = 'OLDPASSPHRASE0987654';

    my %case = (
	# The command mail form with no address: the one that leaked.
	'no address'          => "changepassword $secret",
	'admin, no address'   => "admin changepassword $secret",
	'password, no address' => "password $secret",
	'admin password'      => "admin password $secret",
	# And the forms that always worked, which must keep working.
	'with an address'     => "changepassword taro\@example.jp $secret",
	'admin changepass'    => "admin changepassword taro\@example.jp $secret",
	'old and new'         => "changepassword taro\@example.jp $old $secret",
	'trailing space'      => "password $secret   ",
	'extra whitespace'    => "password    $secret",
    );

    for my $name (sort keys %case) {
	my $buf = $case{ $name };
	my $out = masked('changepassword', $buf);

	unlike($out, qr/\Q$secret\E/, "$name: the new password is gone");
	unlike($out, qr/\Q$old\E/,    "$name: and the old one too");
	like($out, qr/\*{8}/,         "$name: and something replaced it");
    }
};


# ---------------------------------------------------------------------
# 7a. the address is still readable
#
# The masking is only useful if the log still says who the command was
# about.  Blanking the whole line would hide the password and the
# subscriber together, and the log exists to answer "who did what".
# ---------------------------------------------------------------------
subtest 'the address survives the masking' => sub {
    my $secret = 'SECRETPASSPHRASE1234';

    for my $command (qw(changepassword chpass passwd initpass)) {
	my $out = masked($command,
			 "$command taro\@example.jp $secret");

	like($out, qr/taro\@example\.jp/, "$command: the address is kept");
	unlike($out, qr/\Q$secret\E/,     "$command: the password is not");
    }
};


# ---------------------------------------------------------------------
# 8. where an unmasked buffer ends up
#
# Worth stating, because it is what makes the gaps below matter rather
# than being untidy.  get_masked_command() is read in two places and
# both of them are logerror(): FML::Command when a command fails its
# syntax check, and FML::Command::User::admin when authentication fails.
#
# Those are the failure paths -- which is to say, the paths somebody
# hits when they have just mistyped a command carrying their password.
# ---------------------------------------------------------------------
subtest 'the masked buffer is what gets logged' => sub {
    my %site = (
	'fml/lib/FML/Command.pm'            => qr/logerror\("insecure command/,
	'fml/lib/FML/Command/User/admin.pm' => qr/logerror\(.*masked_command/,
    );

    for my $path (sort keys %site) {
	open(my $fh, '<', $path) or do { fail("cannot read $path"); next };
	local $/ = undef;
	my $src = <$fh>;
	close($fh);

	like($src, qr/get_masked_command/, "$path reads the masked buffer");
	like($src, $site{ $path },         "$path logs it");
    }
};


# ---------------------------------------------------------------------
# 9. the masking is case sensitive, and the command name is not cooked
#
# rewrite_prompt() matches /(password|pass)/ with no /i.  The command
# name is not lowercased anywhere before it -- FML::Command::DataCheck
# has an XXX-TODO saying it should be -- so a mail saying
# "PASSWORD taro@example.jp secret" reaches the masking with its case
# intact, matches nothing, and is written to the log in full.
#
# That command does not run: the dispatcher builds
# FML::Command::Admin::PASSWORD, which is not a module.  So it fails,
# and failing is exactly the path that logs the buffer.
# ---------------------------------------------------------------------
subtest 'a password command in the wrong case is not masked' => sub {
    my $secret = 'SECRETPASSPHRASE1234';

    for my $written (qw(PASSWORD Password PASS ChangePassword)) {
	my $buf = "$written taro\@example.jp $secret";
	my $out = masked('changepassword', $buf);

	local $TODO = 'rewrite_prompt() matches (password|pass) without /i';
	unlike($out, qr/\Q$secret\E/, "$written: the secret is gone");
    }

    # The lowercase form of the same input is masked, so this is the
    # case and nothing else.
    my $lower = masked('changepassword',
		       "password taro\@example.jp $secret");
    unlike($lower, qr/\Q$secret\E/, 'the lowercase form is masked');
};


# ---------------------------------------------------------------------
# 10. the masking stops at the first line
#
# The pattern is anchored with ^ and has no /m, and "." does not match a
# newline, so a buffer whose first line is not the password command is
# left alone entirely.  A command mail carries several commands, one per
# line.
#
# Whether a multi-line buffer ever reaches rewrite_prompt() depends on
# the caller -- FML::Process::Command hands it one command at a time --
# so this is recorded as the property of the routine rather than as a
# live leak.
# ---------------------------------------------------------------------
subtest 'the masking only looks at the first line' => sub {
    my $secret = 'SECRETPASSPHRASE1234';
    my $buf    = "help\npassword taro\@example.jp $secret\n";

    my $out = masked('changepassword', $buf);

    {
	local $TODO = 'the pattern is anchored with ^ and has no /m';
	unlike($out, qr/\Q$secret\E/,
	       'a password on the second line is masked');
    }

    # What happens instead, so the behaviour is at least known.
    like($out, qr/\Q$secret\E/,
	 'today the whole buffer is passed through untouched');
};


# ---------------------------------------------------------------------
# 11. two hashes of one password differ
#
# The salt is what makes that true, and it is why two administrators who
# choose the same password do not look the same in the file.  The old
# scheme took its salt from the process id, so they often did.
# ---------------------------------------------------------------------
subtest 'the same password hashes differently every time' => sub {
    my $p = 'correct horse battery staple';

    my %seen = ();
    for (1 .. 5) {
	my $h = $CRYPT->hash($p);
	$seen{ $h }++;
	is($CRYPT->verify($p, $h), 1, 'each hash verifies');
    }

    is(scalar(keys %seen), 5, 'five hashes, five different strings');
};


# ---------------------------------------------------------------------
# 12. verify() answers rather than dying
#
# It is reached with whatever arrived in the mail on one side and
# whatever is in the password file on the other, and neither is trusted.
# ---------------------------------------------------------------------
subtest 'verify() is total' => sub {
    my $good = $CRYPT->hash('correct horse battery staple');

    my @case = (
	[ undef,      $good, 'undef password'   ],
	[ '',         $good, 'empty password'   ],
	[ 'wrong',    $good, 'wrong password'   ],
	[ 'x',        undef, 'undef stored'     ],
	[ 'x',        '',    'empty stored'     ],
	[ 'x',        'garbage', 'stored garbage' ],
	[ 'x',        '$pbkdf2$', 'a truncated stored entry' ],
	[ 'x',        '$pbkdf2$notanumber$a$b', 'a malformed one' ],
    );

    for my $c (@case) {
	my ($p, $s, $name) = @$c;
	my $r = eval { $CRYPT->verify($p, $s) };

	is($@, '', "$name: does not die") or diag($@);
	is($r, 0,  "$name: does not verify");
    }

    # And the one that should.
    is($CRYPT->verify('correct horse battery staple', $good), 1,
       'the right password still verifies');
};

done_testing();
