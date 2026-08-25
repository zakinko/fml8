#-*- perl -*-
#
# The last resort log, which is what explains a failed bootstrap.
#
# FML::Process::Switch::__log() is the only place that can record why
# fml8 failed before there is a process object to log through.  It built
# its file name like this:
#
#	my $dir  = $main_cf->{ ml_home_prefix };
#	my $logf = File::Spec->catfile($dir, '@log.crit@');
#
# main.cf defines $default_ml_home_prefix and $ml_home_prefix_maps.  It
# does not define $ml_home_prefix, and at bootstrap no ML has been
# selected in any case, so that key was always undef.  catfile() then
# warned "Use of uninitialized value in subroutine entry" and returned
# "/@log.crit@", which is on a read-only filesystem, so the open failed
# inside the eval and the message was dropped.
#
# The one place meant to explain a failed bootstrap was therefore
# silent, which is how a broken start ends up looking like an empty page
# with no reason given.
#
# Everything here happens under a temporary directory, so nothing is
# written where an installation would keep its logs.
#

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Process::Switch;

my $TMPDIR   = tempdir(CLEANUP => 1);
my $LOG_NAME = '@log.crit@';


# Descriptions: call __log() with warnings collected, and report both
#               what it wrote and what it complained about.
#    Arguments: HASH_REF($main_cf) STR($message)
# Side Effects: may create a file under $main_cf's prefix.
# Return Value: ARRAY_REF
sub run_log
{
    my ($main_cf, $message) = @_;
    my @warn = ();

    local $SIG{__WARN__} = sub { push @warn, $_[0] };
    eval { FML::Process::Switch::__log($main_cf, $message) };

    return { warn => \@warn, died => $@ };
}


# Descriptions: the contents of the crit log under $dir, or ''.
#    Arguments: STR($dir)
# Side Effects: none
# Return Value: STR
sub crit_log
{
    my ($dir) = @_;
    my $path  = File::Spec->catfile($dir, $LOG_NAME);

    return '' unless -f $path;

    open(my $fh, '<', $path) or return '';
    local $/ = undef;
    my $buf = <$fh>;
    close($fh);

    return defined $buf ? $buf : '';
}


# Descriptions: a fresh directory to log into.
#    Arguments: STR($name)
# Side Effects: creates a directory.
# Return Value: STR
sub fresh_dir
{
    my ($name) = @_;
    my $dir    = "$TMPDIR/$name";

    mkdir($dir) or die "cannot mkdir $dir: $!";

    return $dir;
}


# ---------------------------------------------------------------------
# 1. the key main.cf really defines
#
# This is the whole bug: the code read a key that is not there.
# ---------------------------------------------------------------------
subtest 'the fallback key is the one main.cf defines' => sub {
    my $dir = fresh_dir('default_only');

    # Exactly what bootstrap has: default_ml_home_prefix and nothing
    # named ml_home_prefix.
    my $r = run_log({ default_ml_home_prefix => $dir }, "bootstrap failed");

    is($r->{ died }, '', '__log() does not die') or diag($r->{ died });
    is(scalar(@{ $r->{ warn } }), 0, 'and warns about nothing')
	or diag("warnings: @{ $r->{ warn } }");

    my $got = crit_log($dir);
    ok($got, 'the message was written') or diag("nothing in $dir/$LOG_NAME");
    like($got, qr/\bbootstrap failed$/m, 'and it is the message given');
    like($got, qr/^\d+\t/m, 'prefixed with a timestamp and a tab');
};


# ---------------------------------------------------------------------
# 2. ml_home_prefix still wins when there is one
#
# The fallback must not have replaced the original key: once an ML has
# been selected, its own directory is where the message belongs.
# ---------------------------------------------------------------------
subtest 'ml_home_prefix is preferred when it is set' => sub {
    my $chosen  = fresh_dir('chosen');
    my $default = fresh_dir('default');

    my $r = run_log({
	ml_home_prefix         => $chosen,
	default_ml_home_prefix => $default,
    }, "ml is chosen");

    is(scalar(@{ $r->{ warn } }), 0, 'nothing warned')
	or diag("warnings: @{ $r->{ warn } }");

    like(crit_log($chosen), qr/ml is chosen/, 'written under ml_home_prefix');
    is(crit_log($default), '', 'and not under the default');
};


# ---------------------------------------------------------------------
# 3. neither key at all
#
# The old code built "/@log.crit@" here and tried to open it.  It has to
# be quiet: this routine runs while something else is already going
# wrong, and a warning out of the error path is noise on top of an
# error.
# ---------------------------------------------------------------------
subtest 'no prefix at all is quiet rather than noisy' => sub {
    for my $cf ({}, { ml_home_prefix => undef },
		{ ml_home_prefix => '', default_ml_home_prefix => '' }) {
	my $r = run_log($cf, "nowhere to write");

	is($r->{ died }, '', 'does not die') or diag($r->{ died });
	is(scalar(@{ $r->{ warn } }), 0, 'and does not warn')
	    or diag("warnings: @{ $r->{ warn } }");
    }

    # And specifically not the "uninitialized value" warning that
    # catfile() produced.
    my $r = run_log({}, "nowhere to write");
    my @uninit = grep { /uninitialized/i } @{ $r->{ warn } };
    is(scalar(@uninit), 0, 'no "Use of uninitialized value" from catfile()');
};


# ---------------------------------------------------------------------
# 4. what the old code computed
#
# Written out so that "the key was always undef" is a measurement rather
# than a claim.  catfile(undef, ...) is where the warning came from and
# "/@log.crit@" is where it tried to write.
# ---------------------------------------------------------------------
subtest 'the old expression produced an unwritable path' => sub {
    my $main_cf = { default_ml_home_prefix => '/var/spool/ml' };

    is($main_cf->{ ml_home_prefix }, undef,
       'ml_home_prefix is not a key main.cf sets');

    my @warn = ();
    my $path;
    {
	local $SIG{__WARN__} = sub { push @warn, $_[0] };
	no warnings 'uninitialized';
	$path = File::Spec->catfile($main_cf->{ ml_home_prefix }, $LOG_NAME);
    }

    is($path, "/$LOG_NAME", 'catfile(undef, ...) gives a path at the root');
    ok(!-w '/', 'and the root is not writable, so the open failed')
	unless $> == 0;
};


# ---------------------------------------------------------------------
# 5. it appends
#
# Several messages can come out of one failed bootstrap, and the first
# one is usually the one that matters.  Truncating would keep the last.
# ---------------------------------------------------------------------
subtest 'messages accumulate rather than overwrite' => sub {
    my $dir = fresh_dir('append');
    my $cf  = { default_ml_home_prefix => $dir };

    run_log($cf, "first");
    run_log($cf, "second");
    run_log($cf, "third");

    my $got = crit_log($dir);
    my @line = grep { /\S/ } split(/\n/, $got);

    is(scalar(@line), 3, 'three messages, three lines');
    like($got, qr/first/,  'the first is still there');
    like($got, qr/second/, 'and the second');
    like($got, qr/third/,  'and the third');
};


# ---------------------------------------------------------------------
# 6. a prefix that is not a usable directory
#
# The routine is wrapped in an eval, so it must survive these; the point
# is that it survives without saying anything either.
# ---------------------------------------------------------------------
subtest 'an unusable prefix is survived quietly' => sub {
    my %case = (
	'a directory that does not exist' => "$TMPDIR/no-such-dir",
	'a path that is a file'           => do {
	    my $f = "$TMPDIR/a-file";
	    open(my $wh, '>', $f) or die $!;
	    print $wh "x\n";
	    close($wh);
	    $f;
	},
    );

    for my $name (sort keys %case) {
	my $r = run_log({ default_ml_home_prefix => $case{ $name } },
			"unusable");

	is($r->{ died }, '', "$name: does not die") or diag($r->{ died });
	is(scalar(@{ $r->{ warn } }), 0, "$name: does not warn")
	    or diag("warnings: @{ $r->{ warn } }");
    }
};


# ---------------------------------------------------------------------
# 7. the message survives whatever is in it
#
# A bootstrap failure message is an error string, which may hold
# anything -- newlines out of a croak(), octets out of a path.
# ---------------------------------------------------------------------
subtest 'the message is written as given' => sub {
    my $dir = fresh_dir('messages');
    my $cf  = { default_ml_home_prefix => $dir };

    my %case = (
	'plain'          => "cannot load config",
	'with a colon'   => "cannot open /etc/fml/main.cf: No such file",
	'euc-jp octets'  => "\xc6\xfc\xcb\xdc\xb8\xec",
	'utf-8 octets'   => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e",
	'a long one'     => ('x' x 500),
    );

    for my $name (sort keys %case) {
	my $r = run_log($cf, $case{ $name });
	is($r->{ died }, '', "$name: does not die") or diag($r->{ died });
    }

    my $got = crit_log($dir);
    for my $name (sort keys %case) {
	ok(index($got, $case{ $name }) >= 0, "$name: written verbatim");
    }
};

done_testing();
