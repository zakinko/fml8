#-*- perl -*-
#
# The command name is user supplied, and it used to reach eval().
#
# FML::Command built "FML::Command::${mode}::${comname}" by
# interpolation and then ran
#
#	eval qq{ use $pkg; \$command = new $pkg;};
#
# $comname comes out of the incoming mail.  The user path is covered by
# the allowed-commands list, but the admin path only checks that the
# sender is privileged, so a remote administrator could put arbitrary
# perl in a command name and have it compiled and run.
#
# _command_package() is the guard.  Two things have to hold, and the
# second is the one a security fix usually gets wrong: it must refuse
# what an attacker sends, AND it must still accept every command fml8
# really has.  A guard that quietly refuses "add2member" turns a fixed
# hole into a broken mailing list.
#

use strict;
use warnings;
use Test::More;

# cpan/lib and img/lib go on the end of @INC, so that a module the host
# has installed wins over the bundled copy.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Command;
use FML::Context::Command;


# ---------------------------------------------------------------------
# 1. the shape of the answer
# ---------------------------------------------------------------------
subtest '_command_package() builds the package name' => sub {
    is(FML::Command->_command_package('User', 'subscribe'),
       'FML::Command::User::subscribe', 'user mode');
    is(FML::Command->_command_package('Admin', 'add'),
       'FML::Command::Admin::add', 'admin mode');
};


# ---------------------------------------------------------------------
# 2. every command fml8 actually ships must survive the guard
#
# Read the names off disk rather than listing them here, so a command
# added later is covered without anyone remembering to.
# ---------------------------------------------------------------------
subtest 'no real command is refused by the guard' => sub {
    my $n = 0;

    for my $mode (qw(User Admin)) {
	my @pm = glob("fml/lib/FML/Command/$mode/*.pm");
	cmp_ok(scalar(@pm), '>', 0, "$mode: found command modules");

	for my $path (@pm) {
	    my ($name) = $path =~ m{/([^/]+)\.pm$};
	    is(FML::Command->_command_package($mode, $name),
	       "FML::Command::${mode}::${name}", "$mode: $name");
	    $n++;
	}
    }

    cmp_ok($n, '>=', 90, "checked every command module ($n of them)");
};


# ---------------------------------------------------------------------
# 3. the mode really does arrive in the form the guard demands
#
# The guard matches /^(?:User|Admin)$/, capital letter and all, while
# the documentation for get_mode() says "admin" or "user".  What saves
# it is FML::Context::Command::get_mode(), which normalises to "Admin"
# or "User" before returning.  That coupling is invisible at the call
# site and silent when broken -- _command_package() would return undef
# for everything and every command would stop working -- so assert it
# rather than trusting it.
# ---------------------------------------------------------------------
subtest 'get_mode() answers in the form the guard accepts' => sub {
    my $ctx = new FML::Context::Command;

    for my $set ('Admin', 'admin', 'ADMIN') {
	$ctx->set_mode($set);
	my $mode = $ctx->get_mode();
	is($mode, 'Admin', "set_mode($set) reads back as Admin");
	ok(defined FML::Command->_command_package($mode, 'add'),
	   "and the guard accepts it");
    }

    for my $set ('User', 'user', '', undef) {
	$ctx->set_mode($set);
	my $mode = $ctx->get_mode();
	is($mode, 'User',
	   sprintf("set_mode(%s) reads back as User",
		   defined $set ? "'$set'" : 'undef'));
	ok(defined FML::Command->_command_package($mode, 'subscribe'),
	   "and the guard accepts it");
    }

    # Anything else is treated as user mode, never passed through.
    $ctx->set_mode('Wizard');
    is($ctx->get_mode(), 'User', 'an unknown mode falls back to User');
};


# ---------------------------------------------------------------------
# 4. what the guard exists to refuse
# ---------------------------------------------------------------------
subtest 'an injected command name is refused' => sub {
    my @evil = (
	'subscribe;system("id");1;#',
	'subscribe; unlink "/etc/passwd"; #',
	'x; die "boom"',
	'subscribe`id`',
	'subscribe$(id)',
	'subscribe|cat',
	'subscribe && id',
	'BEGIN{die}',
	'x;print STDERR "leak";',
    );

    for my $name (@evil) {
	is(FML::Command->_command_package('User', $name), undef,
	   "refused: $name");
	is(FML::Command->_command_package('Admin', $name), undef,
	   "refused in admin mode too: $name");
    }
};


# ---------------------------------------------------------------------
# 5. the other ways a name can be wrong
#
# Separate from the injection cases: these are not attacks, they are
# names that must not be allowed to name a package either -- "::" would
# reach outside FML::Command, a path would reach outside the tree, and a
# newline is how a one-line guard gets stepped over.
# ---------------------------------------------------------------------
subtest 'a name that is not a bare word is refused' => sub {
    my @bad = (
	'',                     # nothing at all
	' ',                    # whitespace only
	'sub scribe',           # a space in the middle
	'FML::Command::User::subscribe', # colons: a package path
	'User::subscribe',
	'..',
	'../../etc/passwd',
	'/etc/passwd',
	'subscribe.pm',         # a file name rather than a command
	"subscribe\n",          # trailing newline
	"subscribe\nid",        # a second line
	"subscribe\0",          # NUL
	'subscribe ',           # trailing space
	' subscribe',           # leading space
	'サブスクライブ',       # non-ASCII (raw octets)
    );

    for my $name (@bad) {
	my $shown = $name;
	$shown =~ s/([^\x20-\x7e])/sprintf("\\x%02x", ord($1))/ge;
	is(FML::Command->_command_package('User', $name), undef,
	   "refused: [$shown]");
    }

    is(FML::Command->_command_package('User', undef), undef,
       'undef is refused rather than warned about');
};


# ---------------------------------------------------------------------
# 6. the mode is guarded as well
#
# The mode is not user supplied today, but it is interpolated into the
# same string, so it gets the same treatment.
# ---------------------------------------------------------------------
subtest 'only the two real modes are accepted' => sub {
    for my $mode ('user', 'admin', 'USER', 'Anonymous', '',
		  'User;system("id")', 'User::x', "User\n", undef) {
	is(FML::Command->_command_package($mode, 'subscribe'), undef,
	   sprintf("mode refused: %s",
		   defined $mode ? "'$mode'" : 'undef'));
    }
};


# ---------------------------------------------------------------------
# 7. the hole was real
#
# A guard is only worth having if what it stops would otherwise have
# happened.  Build the very string FML::Command used to build and run it
# the same way, with a payload that sets a flag instead of doing damage.
# If this ever stops setting the flag, perl has changed and the guard is
# no longer the thing keeping us safe -- which is worth knowing too.
# ---------------------------------------------------------------------
subtest 'the unguarded eval really would have run the payload' => sub {
    our $PAYLOAD_RAN = 0;

    my $comname = 'subscribe; $main::PAYLOAD_RAN = 1; package Nowhere; #';
    my $mode    = 'User';

    # This is the old line, verbatim.
    my $pkg = "FML::Command::${mode}::${comname}";
    my $command = undef;
    eval qq{ use $pkg; \$command = new $pkg;};

    is($PAYLOAD_RAN, 1, 'the injected statement was executed');

    # And the guard would never have produced that string.
    is(FML::Command->_command_package($mode, $comname), undef,
       'the guard refuses the same name');
};


# ---------------------------------------------------------------------
# 8. the admin subcommand path uses the same guard
#
# "admin <subcommand>" arrives in user mode and dispatches into
# FML::Command::Admin::*, so it is a second door into the same eval.
# It calls FML::Command->_command_package() as a class method, which is
# a different calling convention from the rest of the module; check it
# answers there too.
# ---------------------------------------------------------------------
subtest 'the admin subcommand path is guarded as well' => sub {
    require FML::Command::User::admin;

    my $src = '';
    {
	open(my $fh, '<', 'fml/lib/FML/Command/User/admin.pm')
	    or die "cannot read admin.pm: $!";
	local $/ = undef;
	$src = <$fh>;
	close($fh);
    }

    # Strip comments: the XXX notes explain the guard and name the thing
    # they are guarding against.
    my $code = join("\n", grep { !/^\s*#/ } split(/\n/, $src));

    unlike($code, qr/\$pkg\s*=\s*"FML::Command::Admin::\$\{?comname/,
	   'the subcommand name is not interpolated straight into $pkg');
    like($code, qr/_command_package/,
	 'it goes through the guard instead');

    is(FML::Command->_command_package('Admin', 'add'),
       'FML::Command::Admin::add',
       'called as a class method, a real subcommand still resolves');
    is(FML::Command->_command_package('Admin', 'add;system("id")'), undef,
       'called as a class method, an injected one does not');
};

done_testing();
