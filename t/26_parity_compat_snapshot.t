#-*- perl -*-
#
# fml8's copy of fml4's defaults, against fml4 itself.
#
# fml8 ships fml/etc/compat/fml4/default_config.ph, a snapshot of what
# fml4's settings default to.  FML::Merge uses it to work out which
# values in a site's config.ph were actually changed: anything equal to
# the default can be dropped rather than converted.
#
# A snapshot is only useful while it matches.  If fml4 defaults a
# setting to one value and the snapshot says another, migration reads a
# deliberate choice as an untouched default and throws it away -- or
# keeps a value the site never set.  Nothing checks that today, and the
# two files live in different repositories, so nothing would notice.
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

my $FML4 = ParityFML4::fml4_dir();
plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless $FML4;

my $COMPAT_PH = 'fml/etc/compat/fml4/default_config.ph';


# Descriptions: slurp a file as raw octets, or return the empty string.
#               fml4 and the snapshot both carry EUC-JP comments.
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

my $SNAP = slurp($COMPAT_PH);

# every variable the snapshot assigns
my @SNAP_VAR = ();
{
    my %seen = ();
    while ($SNAP =~ /^\$([A-Z][A-Z0-9_]+)/mg) { $seen{ $1 } = 1 }
    @SNAP_VAR = sort keys %seen;
}

# the whole of fml4's runtime, as one string to search
my $FML4_SRC = '';
for my $dir (qw(kern proc libexec bin sbin)) {
    next unless -d "$FML4/$dir";
    opendir(my $dh, "$FML4/$dir") or next;
    for my $f (sort readdir($dh)) {
	next unless $f =~ /\.(pl|ph)$/ || $f eq 'makefml';
	$FML4_SRC .= slurp("$FML4/$dir/$f");
    }
    closedir($dh);
}


# ---------------------------------------------------------------------
# 1. the snapshot is there and is not empty
# ---------------------------------------------------------------------
subtest 'the bundled fml4 defaults exist' => sub {
    ok(-f $COMPAT_PH, "$COMPAT_PH exists");
    cmp_ok(length($SNAP), '>', 10_000, 'it has substance');
    cmp_ok(scalar(@SNAP_VAR), '>=', 250,
	   scalar(@SNAP_VAR) . ' variables assigned in it');

    cmp_ok(length($FML4_SRC), '>', 500_000,
	   'fml4 sources were read for comparison');
};


# ---------------------------------------------------------------------
# 2. every variable in the snapshot is one fml4 actually has
#
# A name here that fml4 never mentions is either a typo or a leftover
# from an fml4 that no longer exists; either way migration would carry a
# default for a setting that does nothing.
# ---------------------------------------------------------------------
subtest 'the snapshot invents no variables' => sub {
    my @orphan = ();

    for my $v (@SNAP_VAR) {
	push @orphan, $v unless $FML4_SRC =~ /\$\Q$v\E\b/;
    }

    # These ten are in the snapshot and nowhere in this fml4 checkout,
    # which says the snapshot was taken from a different fml4 -- a
    # later or a branched one -- rather than from the tree fml8 is being
    # compared against here.  $MTI_BURST_HARD_LIMIT is also one of the
    # settings Rules.pm marks not_yet_implemented, so fml8 carries a
    # default and a conversion rule for a variable this fml4 does not
    # have.
    #
    # Worth knowing, not worth failing over: which fml4 the snapshot
    # should track is the maintainer's call.
    my @KNOWN_ORPHAN = qw(
	ADMIN_ENCRYPT_KEYRING_DIR
	BZIP2
	CFV
	DIST_AUTH_KEYRING_DIR
	MODERATOR_MEMBER_LIST
	MSEND_DEFAULT_SUBJECT
	MTI_BURST_HARD_LIMIT
	PGP5
	REMOTE_ADMINISTRATION_REQUIRE_PASSWORD
	USE_WHOIS
    );

    my %known = map { $_ => 1 } @KNOWN_ORPHAN;
    my %found = map { $_ => 1 } @orphan;

    for my $v (@KNOWN_ORPHAN) {
	local $TODO = "\$$v is in fml8's snapshot but not in this fml4";
	ok($found{ $v } ? 0 : 1, "\$$v exists in fml4");
    }

    my @new = sort grep { !$known{ $_ } } @orphan;
    is_deeply(\@new, [],
	      'no new variable has appeared in the snapshot alone')
	or diag("new orphans: @new");

    my @gone = sort grep { !$found{ $_ } } @KNOWN_ORPHAN;
    is(scalar(@gone), 0, 'the known list is still accurate')
	or diag("now present in fml4, remove from \@KNOWN_ORPHAN: @gone");

    note(sprintf("snapshot variables: %d, absent from fml4: %d",
		 scalar(@SNAP_VAR), scalar(@orphan)));
};


# ---------------------------------------------------------------------
# 3. the snapshot is plain ASCII
#
# fml4's own sources carry EUC-JP comments; this snapshot does not, and
# that is worth pinning.  A file that is pure ASCII cannot be damaged by
# an editor that guesses an encoding, and this one is regenerated from
# fml4 by hand from time to time -- exactly the operation that has
# mangled EUC-JP files in this tree before.
# ---------------------------------------------------------------------
subtest 'the snapshot is plain ASCII, so re-taking it is safe' => sub {
    my @high = ($SNAP =~ /([\x80-\xff])/g);

    is(scalar(@high), 0, 'no high-bit octets at all')
	or diag(sprintf("%d high-bit octets found", scalar(@high)));

    # U+FFFD, what a failed transcode leaves behind, and the EUC-JP and
    # UTF-8 shapes it would have been made from.
    unlike($SNAP, qr/\xef\xbf\xbd/,        'no replacement characters');
    unlike($SNAP, qr/[\xa1-\xfe]{2}/,      'no EUC-JP pairs');
    unlike($SNAP, qr/[\xe3-\xe9][\x80-\xbf]{2}/, 'no UTF-8 sequences');

    # fml4 itself is not ASCII, so this is a property of the snapshot,
    # not of the material it was taken from.
    my @f4_high = ($FML4_SRC =~ /([\x80-\xff])/g);
    cmp_ok(scalar(@f4_high), '>', 1000,
	   'fml4 itself does carry high-bit octets, as expected');
};


# ---------------------------------------------------------------------
# 4. the snapshot is loadable perl
#
# FML::Merge reads it by evaluating it.  A syntax error would be found
# only when a site tried to migrate, which is the worst moment.
# ---------------------------------------------------------------------
subtest 'the snapshot compiles' => sub {
    my $out = `perl -c $COMPAT_PH 2>&1`;
    my $rc  = $?;

    is($rc, 0, "perl -c $COMPAT_PH") or diag($out);
    like($out, qr/syntax OK/, 'perl says syntax OK');

    # It must not have picked up anything that would run on load.
    unlike($SNAP, qr/^\s*(system|exec|unlink|open)\s*\(/m,
	   'nothing in it acts when evaluated');
};


# ---------------------------------------------------------------------
# 5. fml8's two statements about fml4 agree with each other
#
# Rules.pm says how to convert a variable; the snapshot says what its
# fml4 default was.  Conversion needs both: without a default there is
# no way to tell a value the site chose from one it merely inherited,
# and FML::Merge then converts settings nobody ever set.
#
# This is a check of fml8 against itself, so it holds whatever fml4 the
# snapshot was taken from.
# ---------------------------------------------------------------------
subtest 'every variable the converter handles has a recorded default' => sub {
    my $rules = slurp('fml/lib/FML/Merge/FML4/Rules.pm');
    plan skip_all => 'Rules.pm not found' unless length($rules);

    my %in_rules = ();
    $in_rules{ $1 } = 1 while $rules =~ /\$key eq .([A-Z][A-Z0-9_]+)./g;

    cmp_ok(scalar(keys %in_rules), '>=', 300,
	   scalar(keys %in_rules) . ' variables have a conversion rule');

    my %in_snap = map { $_ => 1 } @SNAP_VAR;
    my @no_default = sort grep { !$in_snap{ $_ } } keys %in_rules;

    # A handful convert without a default because fml4 computes them
    # rather than assigning a literal; the number is small and must stay
    # small, or the snapshot has fallen behind the converter.
    cmp_ok(scalar(@no_default), '<=', 60,
	   scalar(@no_default) . ' convert with no recorded fml4 default');
    note("no recorded default: @no_default") if @no_default;

    # And the other way: a default nobody converts is dead weight, but
    # harmless, so only report it.
    my @no_rule = sort grep { !$in_rules{ $_ } } @SNAP_VAR;
    note(sprintf("%d defaults have no conversion rule", scalar(@no_rule)));
};

done_testing();
