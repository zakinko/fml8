#-*- perl -*-
#
# Can an fml4 site's configuration be carried into fml8?
#
# fml4 has no single defaults file.  Its settings are globals assigned
# across kern/, proc/ and libexec/, and a site's config.ph overrides
# whichever ones it cares about.  fml8 replaced that with named
# configuration and provides FML::Merge::FML4::Rules to convert an fml4
# config.ph, plus a copy of fml4's defaults under
# fml/etc/compat/fml4/default_config.ph.
#
# A variable those two do not know about is not converted and not
# defaulted: a site that had set it loses the setting, silently, during
# migration.  That is what this counts.
#
# The extraction is deliberately generous -- it takes every all-caps
# global fml4 assigns -- so the list includes internal state such as
# $DIR and $EXEC as well as real settings.  The ratchet is therefore on
# the number, not on a claim that every name is a setting; the value is
# that coverage cannot quietly shrink.
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

plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless ParityFML4::fml4_dir();

my $RULES_PM  = 'fml/lib/FML/Merge/FML4/Rules.pm';
my $COMPAT_PH = 'fml/etc/compat/fml4/default_config.ph';


# Descriptions: slurp a file, or return the empty string.
#    Arguments: STR($file)
# Side Effects: none
# Return Value: STR
sub slurp
{
    my ($file) = @_;

    open(my $fh, '<', $file) or return '';
    binmode($fh);
    local $/ = undef;
    my $s = <$fh>;
    close($fh);
    return defined $s ? $s : '';
}

my @FML4 = @{ ParityFML4::fml4_config_variables() };

# Names Rules.pm tests for by hand, one branch per variable.
my %IN_RULES = ();
{
    my $src = slurp($RULES_PM);
    $IN_RULES{ $1 } = 1 while $src =~ /\$key eq .([A-Z][A-Z0-9_]+)./g;
}

# Names the bundled copy of fml4's defaults carries.
my %IN_COMPAT = ();
{
    my $src = slurp($COMPAT_PH);
    $IN_COMPAT{ $1 } = 1 while $src =~ /^\$([A-Z][A-Z0-9_]+)/mg;
}


# Descriptions: is this fml4 variable visible to fml8's migration?
#    Arguments: STR($name)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub known_to_fml8
{
    my ($name) = @_;

    return 1 if $IN_RULES{  $name };
    return 1 if $IN_COMPAT{ $name };
    return 0;
}

# The number of fml4 globals fml8's migration does not mention.  It may
# fall freely; it may not rise.
my $MAX_UNKNOWN = 74;

# Names that look like settings by fml4's own conventions and are still
# unknown.  These are the ones worth closing first, because a site is
# more likely to have set them than to have touched $DIR.
my @LOOKS_LIKE_A_SETTING = qw(
    ADD_URL_INFO
    CHADDR_CONFIRMATION_KEYWORD
    CONFIRMATION_RESET_KEYWORD
    DEAD_ADDR_HINT_FILE
    ERROR_ADDR_HINT_FILE
);


# ---------------------------------------------------------------------
# 1. both sides of the comparison exist
# ---------------------------------------------------------------------
subtest 'fml8 ships the migration machinery this test reads' => sub {
    ok(-f $RULES_PM,  "$RULES_PM exists");
    ok(-f $COMPAT_PH, "$COMPAT_PH exists");

    cmp_ok(scalar(keys %IN_RULES),  '>=', 300,
	   scalar(keys %IN_RULES) . ' variables named in Rules.pm');
    cmp_ok(scalar(keys %IN_COMPAT), '>=', 250,
	   scalar(keys %IN_COMPAT) . ' variables in the bundled defaults');
    cmp_ok(scalar(@FML4), '>=', 150,
	   scalar(@FML4) . ' variables found in the fml4 tree');
};


# ---------------------------------------------------------------------
# 2. the coverage, and the ratchet on it
# ---------------------------------------------------------------------
subtest 'fml4 configuration is visible to fml8' => sub {
    my @unknown = sort grep { !known_to_fml8($_) } @FML4;
    my $known   = scalar(@FML4) - scalar(@unknown);

    note(sprintf("fml4 globals: %d, known to fml8: %d, unknown: %d",
		 scalar(@FML4), $known, scalar(@unknown)));

    cmp_ok(scalar(@unknown), '<=', $MAX_UNKNOWN,
	   sprintf("unknown variables: %d (ceiling %d)",
		   scalar(@unknown), $MAX_UNKNOWN))
	or diag("unknown: @unknown");

    # If the number drops, the ceiling should come down with it, or the
    # next regression hides under the slack.
    cmp_ok(scalar(@unknown), '>=', $MAX_UNKNOWN - 5,
	   'the ceiling is still close to the real number')
	or diag(sprintf("coverage improved: lower \$MAX_UNKNOWN to %d",
			scalar(@unknown)));
};


# ---------------------------------------------------------------------
# 3. Rules.pm and the bundled defaults should mostly agree
#
# They are two independent statements of the same thing.  A variable in
# Rules.pm but not in the defaults means the converter handles a setting
# whose fml4 default nobody recorded.
# ---------------------------------------------------------------------
subtest 'the converter and the bundled defaults cover the same ground' => sub {
    my @rules_only  = sort grep { $IN_RULES{ $_ } && !$IN_COMPAT{ $_ } } @FML4;
    my @compat_only = sort grep { $IN_COMPAT{ $_ } && !$IN_RULES{ $_ } } @FML4;

    note("in Rules.pm only: @rules_only")   if @rules_only;
    note("in defaults only: @compat_only")  if @compat_only;

    cmp_ok(scalar(@rules_only), '<=', 10,
	   scalar(@rules_only) . ' converted without a recorded default');
    cmp_ok(scalar(@compat_only), '<=', 10,
	   scalar(@compat_only) . ' defaulted without a conversion rule');
};


# ---------------------------------------------------------------------
# 4. the ones that plainly are settings
# ---------------------------------------------------------------------
subtest 'settings a site is likely to have changed' => sub {
    my %f4 = map { $_ => 1 } @FML4;

    for my $v (@LOOKS_LIKE_A_SETTING) {
	ok($f4{ $v }, "fml4 really has \$$v");

	local $TODO = "fml8's migration does not mention \$$v";
	ok(known_to_fml8($v), "\$$v survives migration");
    }
};


# ---------------------------------------------------------------------
# 5. what fml8 says about itself
#
# Rules.pm decides each variable with one of five verbs: ignore it,
# convert it, prefer fml8's value, prefer fml4's, or -- the interesting
# one -- not_yet_implemented.  That last is fml8 stating in its own
# source that a setting has no home yet, which is a better list of gaps
# than anything guessed from outside.
#
# Reading it here turns that admission into something CI reports.
# ---------------------------------------------------------------------
subtest "the migration's own account of what it cannot do" => sub {
    my $src = slurp($RULES_PM);

    my %verb = ();
    $verb{ $1 }++ while $src =~ /(fp_rule_[a-z_0-9]+)/g;

    for my $v (qw(fp_rule_ignore fp_rule_convert fp_rule_prefer_fml8_value
		  fp_rule_not_yet_implemented)) {
	ok($verb{ $v }, "$v is used ($verb{$v} times)");
    }

    # Pair each not_yet_implemented with the variable it decides.  The
    # branch names the key just above the call.
    my @pending = ();
    while ($src =~ /\$key eq '([A-Z][A-Z0-9_]+)'(.{0,400}?)fp_rule_not_yet_implemented/gs) {
	my ($key, $between) = ($1, $2);
	# do not reach past the next branch
	next if $between =~ /\$key eq '/;
	push @pending, $key;
    }

    my %seen = ();
    @pending = sort grep { !$seen{ $_ }++ } @pending;

    cmp_ok(scalar(@pending), '>=', 10,
	   scalar(@pending) . ' settings fml8 marks not_yet_implemented');
    note("not yet implemented: @pending");

    for my $k (@pending) {
	local $TODO = "fml8's own migration marks \$$k not_yet_implemented";
	ok(0, "\$$k is migrated");
    }
};

done_testing();
