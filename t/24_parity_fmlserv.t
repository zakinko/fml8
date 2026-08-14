#-*- perl -*-
#
# fmlserv: the listserv emulation.
#
# fml4 shipped libexec/fmlserv.pl, a virtual mailing list that answered
# commands about other lists -- "which" told a sender which lists they
# were on, "lists" named the lists on the host.  fml8 has no such
# program.
#
# That is worth a test of its own rather than a line in t/21, because
# fmlserv is the one part of fml4 whose absence a site notices from the
# outside: mail sent to the fmlserv address stops being answered.  If
# fml8 ever grows an equivalent these TODOs turn green and the ratchet
# says so.
#
# The two defects fml4 has here are recorded in fml4's own tree, in the
# commit "Record the defects whose repair would change what fml4 does".
# Neither is reproduced in fml8, since fml8 has nothing to reproduce
# them in; that is asserted below so the claim does not rot.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);
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

my @FMLSERV = @{ ParityFML4::fml4_fmlserv_commands() };
my %USER    = map { $_ => 1 } @{ ParityFML4::fml8_user_commands()  };
my %ADMIN   = map { $_ => 1 } @{ ParityFML4::fml8_admin_commands() };


# ---------------------------------------------------------------------
# 1. fml4 really has it
# ---------------------------------------------------------------------
subtest 'fml4 ships fmlserv' => sub {
    ok(-f "$FML4/libexec/fmlserv.pl", 'libexec/fmlserv.pl exists');

    cmp_ok(scalar(@FMLSERV), '>=', 2,
	   'fmlserv commands: ' . join(' ', @FMLSERV));

    my %c = map { $_ => 1 } @FMLSERV;
    ok($c{ 'which' }, 'which is one of them');
    ok($c{ 'lists' }, 'lists is one of them');
};


# ---------------------------------------------------------------------
# 2. fml8 does not
# ---------------------------------------------------------------------
subtest 'fml8 has no fmlserv equivalent' => sub {
    for my $c (@FMLSERV) {
	local $TODO = "fml8 has no fmlserv, so \"$c\" cannot be asked";
	ok($USER{ $c } || $ADMIN{ $c }, "fml8 answers to $c");
    }

    # makefml had an "fmlserv" subcommand to drive it; that is gone too.
    ok(!$ADMIN{ 'fmlserv' }, 'no Admin/fmlserv.pm either');
};


# ---------------------------------------------------------------------
# 3. fml4's fmlserv defects are not carried into fml8
#
# fml4 gates "lists" on the "which" flag, and undef's the bare key
# 'which' where %Procedure is keyed "fmlserv:*", so neither command is
# ever actually disabled.  Both are left in place in fml4 on purpose.
# There is nothing in fml8 to inherit them, and this says so.
# ---------------------------------------------------------------------
subtest 'the fml4 fmlserv defects have no fml8 counterpart' => sub {
    my @hits = ();

    for my $dir ('fml/lib') {
	next unless -d $dir;
	my @files = split(/\n/, `find $dir -name '*.pm' 2>/dev/null`);
	for my $f (@files) {
	    open(my $fh, '<', $f) or next;
	    while (my $line = <$fh>) {
		next if $line =~ /^\s*#/;
		push @hits, "$f: $line"
		    if $line =~ /PERMIT_WHICH_COMMAND|PERMIT_LISTS_COMMAND/;
	    }
	    close($fh);
	}
    }

    is_deeply(\@hits, [],
	      'fml8 has no FMLSERV_PERMIT_*_COMMAND flag to get wrong')
	or diag(@hits);
};


# ---------------------------------------------------------------------
# 4. the ratchet
# ---------------------------------------------------------------------
subtest 'fmlserv parity has not changed unnoticed' => sub {
    my @answered = grep { $USER{ $_ } || $ADMIN{ $_ } } @FMLSERV;

    is(scalar(@answered), 0,
       'still nothing; update this test when fmlserv is reimplemented')
	or diag("fml8 now answers to: @answered");

    note(sprintf("fmlserv commands: %d, answered by fml8: %d",
		 scalar(@FMLSERV), scalar(@answered)));
};

done_testing();
