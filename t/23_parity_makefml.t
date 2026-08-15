#-*- perl -*-
#
# The administrator's side: makefml against FML/Command/Admin.
#
# fml4 gave the maintainer one program, makefml, with its subcommands in
# %MakeFmlProc.  fml8 turned each into a module under FML/Command/Admin.
# The same question as t/21 applies -- can fml8 be asked everything fml4
# could be asked -- but the answer is messier here, because a good half
# of makefml is installation and CGI plumbing that fml8 rebuilt rather
# than reimplemented.
#
# So this separates the two.  Subcommands that manage a running list are
# expected to have a home; subcommands that install fml, drive PGP or
# write a CGI are recorded as gaps without pretending they are bugs.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);
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

plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless ParityFML4::fml4_dir();

my %ADMIN = map { $_ => 1 } @{ ParityFML4::fml8_admin_commands() };
my @MF    = @{ ParityFML4::fml4_makefml_subcommands() };
my $HAND  = ParityFML4::fml4_makefml_handlers();

# makefml subcommands fml8 serves under another name.  Only entries that
# can be defended from one of the two trees are here.
my %MAPPED = (
    # makefml maps both 'new' and 'newml' to do_newml.
    'new'         => 'newml',

    # the inverse of newml; fml8 spells it rmml, and also keeps
    # rmcopml/rmdomain for the other two things destructml could remove.
    'destructml'  => 'rmml',

    # showconf, showconfig and show all print configuration; fml8's
    # config module does that.
    'show'        => 'config',
    'showconf'    => 'config',
    'showconfig'  => 'config',

    # update-config and config-update are the same operation spelled two
    # ways; fml8 folds both into config.
    'config-update' => 'config',
    'update-config' => 'config',

    # removing a subscriber, which fml8 spells the same as the user side.
    'byeuser'     => 'bye',
);

# Subcommands that are not list management: installing fml, generating a
# CGI, driving PGP or GnuPG, emulating another mailing list manager.
# fml8 addressed all of these differently, so their absence from
# FML/Command/Admin is a design decision rather than a missing feature.
my @NOT_LIST_MANAGEMENT = qw(
    admin-auth admin-encrypt admin.cgi bug-report-template
    config-template create-doc-template dist-auth dist-encrypt
    edit-template gpg html_cgiadmin_passwd html_config html_config_set
    html_passwd htpasswd install listserv majordomo mead ml-admin.cgi
    mladmin.cgi pgp pgp2 pgpe pgpk pgps pgpv pop_passwd popfml
    qmail-setup recollect-aliases resend send-pr update-config.ph upgrade
);

# List management that fml8 has no home for yet.
my @KNOWN_GAP = qw(
    command
    conv
    delivery_mode
    fmlserv
    help
    info
    lock
    matome
    setq
    skip
    tail
    test
    update
);


# Descriptions: the fml8 admin module answering to this makefml name.
#    Arguments: STR($name)
# Side Effects: none
# Return Value: STR or undef
sub fml8_answers
{
    my ($name) = @_;

    return $name             if $ADMIN{ $name };
    return $MAPPED{ $name }  if $MAPPED{ $name } && $ADMIN{ $MAPPED{ $name } };
    return undef;
}


# ---------------------------------------------------------------------
# 1. names fml8 kept
# ---------------------------------------------------------------------
subtest 'makefml subcommands fml8 kept the name of' => sub {
    my @same = grep { $ADMIN{ $_ } } @MF;

    cmp_ok(scalar(@same), '>=', 20, scalar(@same) . ' names carried over');

    for my $c (@same) {
	ok(-f "fml/lib/FML/Command/Admin/$c.pm", "Admin/$c.pm exists");
    }
};


# ---------------------------------------------------------------------
# 2. names fml8 changed
# ---------------------------------------------------------------------
subtest 'makefml subcommands fml8 renamed' => sub {
    my %mf = map { $_ => 1 } @MF;

    for my $c (sort keys %MAPPED) {
	ok($mf{ $c }, "makefml really has \"$c\"");
	ok($ADMIN{ $MAPPED{ $c } },
	   "$c -> Admin/$MAPPED{$c}.pm");
    }
};


# ---------------------------------------------------------------------
# 3. makefml's own synonyms agree with ours
#
# Two subcommands sharing a handler are the same command.  Where fml8
# kept one of the pair, the other should map to it rather than be
# counted as a gap.
# ---------------------------------------------------------------------
subtest "makefml's own synonyms are reflected" => sub {
    my %by_handler = ();
    for my $c (sort keys %$HAND) {
	push @{ $by_handler{ $HAND->{ $c } } }, $c;
    }

    my $groups = 0;
    for my $h (sort keys %by_handler) {
	my @names = @{ $by_handler{ $h } };
	next if scalar(@names) < 2;
	$groups++;

	# If fml8 answers to any name in the group, it should answer to
	# all of them, or the rest should be mapped onto the one it kept.
	my @answered = grep { fml8_answers($_) } @names;
	next unless @answered;

	# A spelling already recorded as a gap stays a TODO here rather
	# than failing twice; these are the cheapest ones to close, since
	# fml8 already implements the command under its other name.
	my %excused = map { $_ => 1 } (@NOT_LIST_MANAGEMENT, @KNOWN_GAP);

	for my $n (@names) {
	    local $TODO = $excused{ $n }
		? "\"$n\" is the same command as \"$answered[0]\", which fml8 has"
		: undef;
	    ok(fml8_answers($n),
	       "$h: \"$n\" is reachable, as \"$answered[0]\" is");
	}
    }

    cmp_ok($groups, '>=', 3, "$groups handlers have more than one name");
};


# ---------------------------------------------------------------------
# 4. the answering modules load
# ---------------------------------------------------------------------
subtest 'the answering admin modules load and can process()' => sub {
    my %target = map { $_ => 1 } grep { defined } map { fml8_answers($_) } @MF;

    for my $m (sort keys %target) {
	my $pkg = "FML::Command::Admin::$m";
	my $ok  = eval "require $pkg; 1";
	ok($ok, "$pkg loads") or do { diag($@); next };
	can_ok($pkg, 'process');
    }
};


# ---------------------------------------------------------------------
# 5. what fml8 rebuilt rather than reimplemented
# ---------------------------------------------------------------------
subtest 'installation, CGI and crypto subcommands are out of scope' => sub {
    my %mf = map { $_ => 1 } @MF;

    for my $c (@NOT_LIST_MANAGEMENT) {
	ok($mf{ $c }, "makefml has \"$c\"");
    }

    # These really should not have quietly acquired an Admin module; if
    # one appears, the classification above needs revisiting.
    my @surprise = grep { $ADMIN{ $_ } } @NOT_LIST_MANAGEMENT;
    is_deeply(\@surprise, [],
	      'none of them has an Admin module after all')
	or diag("now implemented: @surprise");
};


# ---------------------------------------------------------------------
# 6. the gaps, named out loud
# ---------------------------------------------------------------------
subtest 'list management makefml could do and fml8 cannot' => sub {
    for my $c (@KNOWN_GAP) {
	local $TODO = "fml8 has no admin command for makefml's \"$c\"";
	ok(fml8_answers($c), "fml8 answers to $c");
    }
};


# ---------------------------------------------------------------------
# 7. the ratchet
# ---------------------------------------------------------------------
subtest 'the set of admin gaps has not grown' => sub {
    my %excused = map { $_ => 1 } (@NOT_LIST_MANAGEMENT, @KNOWN_GAP);
    my @gap     = sort grep { !fml8_answers($_) && !$excused{ $_ } } @MF;

    is_deeply(\@gap, [],
	      'no makefml subcommand is unaccounted for')
	or diag("unaccounted: @gap");

    my @fixed = sort grep { fml8_answers($_) } @KNOWN_GAP;
    is(scalar(@fixed), 0,
       'nothing in @KNOWN_GAP has been implemented without updating the list')
	or diag("now implemented, please remove from \@KNOWN_GAP: @fixed");

    note(sprintf("makefml subcommands: %d, answered: %d, out of scope: %d, gap: %d",
		 scalar(@MF),
		 scalar(grep { fml8_answers($_) } @MF),
		 scalar(@NOT_LIST_MANAGEMENT),
		 scalar(@KNOWN_GAP)));
};

done_testing();
