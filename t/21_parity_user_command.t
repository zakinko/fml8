#-*- perl -*-
#
# Can fml8 be asked everything fml4 could be asked?
#
# fml8 is a rewrite, so every command a subscriber could put in a mail to
# an fml4 list should still work against fml8.  fml4 keeps its commands in
# one flat table, %Procedure in proc/libfml.pl; fml8 keeps one module per
# command under FML/Command/User.  This walks fml4's table and asks fml8
# for each name.
#
# Three outcomes, and they are treated differently on purpose.
#
#   - fml8 has a module of the same name.  Asserted.
#   - fml8 has it under another name, and says so itself.  Asserted
#     against the module that fml8's own POD names.
#   - fml8 has nothing.  Reported as TODO, so it shows in the run and
#     nobody has to remember it, and counted, so a new gap fails.
#
# The counted list is the point.  Without it a command quietly dropped in
# a later refactor looks exactly like a command that was never there.
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

my %USER  = map { $_ => 1 } @{ ParityFML4::fml8_user_commands()  };
my %ADMIN = map { $_ => 1 } @{ ParityFML4::fml8_admin_commands() };
my @FML4  = @{ ParityFML4::fml4_user_commands() };

# fml4 names that fml8 serves under a different module.  Each entry has
# to be defensible from fml8's own source, not from a guess about what
# the name probably meant.
my %MAPPED = (
    # FML::Command::Admin::list is "show the content of specified map(s)"
    # and its process() is _show_list(): that is what all of fml4's
    # roster commands asked for, at the privilege fml8 now requires.
    'who'              => [ 'Admin', 'list' ],
    'whois'            => [ 'Admin', 'list' ],
    'member'           => [ 'Admin', 'list' ],
    'members'          => [ 'Admin', 'list' ],
    'active'           => [ 'Admin', 'list' ],
    'actives'          => [ 'Admin', 'list' ],
    'dump_member_list' => [ 'Admin', 'list' ],
    'dump_active_list' => [ 'Admin', 'list' ],

    # fml4's "passwd" sets the administrator password; fml8 keeps a
    # module of that name on the admin side.
    'passwd'           => [ 'Admin', 'passwd' ],

    # moderation moved to the admin side as well.
    'moderator'        => [ 'Admin', 'moderate' ],
);

# fml4 commands with no fml8 counterpart today.  Sorted, and compared as
# a set below: a name leaving this list is good news that the list needs
# editing, a name arriving in it is a regression.
my @KNOWN_GAP = qw(
    ack
    addr
    approve
    chaddr-confirm
    change
    change-address
    end
    exit
    getfile
    iam
    index
    library
    matome
    mget2
    mget3
    mode
    msend
    msg
    noskip
    quit
    sendfile
    set
    skip
    stat
    status
    traffic
    undigest
    unmatome
    unsubscribe-confirm
);


# Descriptions: does fml8 answer to this fml4 command name?
#               returns the module that answers, or undef.
#    Arguments: STR($name)
# Side Effects: none
# Return Value: ARRAY_REF or undef
sub fml8_answers
{
    my ($name) = @_;

    return [ 'User',  $name ] if $USER{  $name };
    return $MAPPED{ $name }   if $MAPPED{ $name };
    return undef;
}


# ---------------------------------------------------------------------
# 1. same name on both sides
# ---------------------------------------------------------------------
subtest 'fml4 commands fml8 kept the name of' => sub {
    my @same = grep { $USER{ $_ } } @FML4;

    cmp_ok(scalar(@same), '>=', 14, scalar(@same) . ' names carried over');

    for my $c (@same) {
	ok(-f "fml/lib/FML/Command/User/$c.pm", "User/$c.pm exists");
    }
};


# ---------------------------------------------------------------------
# 2. renamed, and the new home really is there
# ---------------------------------------------------------------------
subtest 'fml4 commands fml8 serves under another name' => sub {
    for my $c (sort keys %MAPPED) {
	my ($class, $mod) = @{ $MAPPED{ $c } };
	ok(-f "fml/lib/FML/Command/$class/$mod.pm",
	   "$c -> $class/$mod.pm");
    }

    # A mapping is only worth having if fml4 actually had the command.
    my %f4 = map { $_ => 1 } @FML4;
    for my $c (sort keys %MAPPED) {
	ok($f4{ $c }, "$c really is an fml4 command");
    }
};


# ---------------------------------------------------------------------
# 3. every mapped module can be loaded and can process()
#
# A module that exists but cannot run is not parity.
# ---------------------------------------------------------------------
subtest 'the answering modules load and can process()' => sub {
    my %target = ();
    $target{ "User::$_" } = 1 for grep { $USER{ $_ } } @FML4;
    for my $c (keys %MAPPED) {
	my ($class, $mod) = @{ $MAPPED{ $c } };
	$target{ "${class}::${mod}" } = 1;
    }

    for my $t (sort keys %target) {
	my $pkg = "FML::Command::$t";
	my $ok  = eval "require $pkg; 1";
	ok($ok, "$pkg loads") or do { diag($@); next };
	can_ok($pkg, 'new');
	can_ok($pkg, 'process');
    }
};


# ---------------------------------------------------------------------
# 4. the gaps, named out loud
# ---------------------------------------------------------------------
subtest 'fml4 commands fml8 does not answer to' => sub {
    for my $c (@KNOWN_GAP) {
	local $TODO = "fml8 has no counterpart for fml4's \"$c\"";
	ok(fml8_answers($c), "fml8 answers to $c");
    }
};


# ---------------------------------------------------------------------
# 5. the ratchet
#
# Recompute the gap from the two trees and compare it with the list
# above.  This is the assertion that actually protects parity; the TODOs
# only make it readable.
# ---------------------------------------------------------------------
subtest 'the set of gaps has not grown' => sub {
    my @gap   = sort grep { !fml8_answers($_) } @FML4;
    my %known = map { $_ => 1 } @KNOWN_GAP;
    my %found = map { $_ => 1 } @gap;

    my @new   = grep { !$known{ $_ } } @gap;
    my @fixed = grep { !$found{ $_ } } @KNOWN_GAP;

    is_deeply(\@new, [],
	      'no fml4 command has newly lost its fml8 counterpart')
	or diag("new gaps: @new");

    is(scalar(@fixed), 0,
       'nothing in @KNOWN_GAP has been implemented without updating the list')
	or diag("now implemented, please remove from \@KNOWN_GAP: @fixed");

    note(sprintf("fml4 commands: %d, answered by fml8: %d, gap: %d",
		 scalar(@FML4), scalar(@FML4) - scalar(@gap), scalar(@gap)));
};

done_testing();
