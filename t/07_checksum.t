#-*- perl -*-
#
# Mail::Message::Checksum.
#
# cksum2() opened its argument like this:
#
#	if (open($file, $file)) {
#
# $file is the path, a plain string, so perl read the first argument as
# a symbolic filehandle reference and the method died outright under
# "use strict refs" -- every call, not some of them.  The routine could
# therefore never have run since strict was turned on in this file.
#
# The two-argument open() is the second half of it: a path beginning
# with ">" or "|" is read as a mode there, so a file called ">x" would
# have been truncated rather than checksummed.  The three-argument form
# cannot be talked into that.
#
# md5() is the part of this module that is actually used (article
# checksums, duplicate detection), so it is pinned here as well: it has
# two implementations, an internal one through Digest::MD5 and an
# external one shelling out to md5(1), and they have to agree.
#

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Digest::MD5 ();

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Message::Checksum;

my $TMPDIR = tempdir(CLEANUP => 1);
my $CK     = new Mail::Message::Checksum;


# Descriptions: write $data to $path and return $path.
#    Arguments: STR($path) STR($data)
# Side Effects: creates a file.
# Return Value: STR
sub spew
{
    my ($path, $data) = @_;

    open(my $wh, '>', $path) or die "cannot write $path: $!";
    binmode($wh);
    print $wh $data;
    close($wh);

    return $path;
}


# Descriptions: the System V 32 bit checksum of $data, computed here so
#               that cksum2() is compared against the algorithm rather
#               than against its own previous answer.
#    Arguments: STR($data)
# Side Effects: none
# Return Value: ARRAY(NUM, NUM)
sub reference_cksum2
{
    my ($data) = @_;
    my $crc    = 0;

    $crc += ord($_) for split(//, $data);
    $crc = ($crc & 0xffff) + ($crc >> 16);
    $crc = ($crc & 0xffff) + ($crc >> 16);

    return ($crc, length($data));
}


# ---------------------------------------------------------------------
# 1. the object exists and knows how it will compute md5
# ---------------------------------------------------------------------
subtest 'the constructor picks an implementation' => sub {
    ok(defined $CK, 'new() returns an object');
    like($CK->get_mode(), qr/^(?:internal|external)$/,
	 'mode is one of the two real ones, not "unknown"');

    # Digest::MD5 has been in the core since 5.8, so the internal path
    # is the one that should be taken here.
    is($CK->get_mode(), 'internal', 'Digest::MD5 is used');
};


# ---------------------------------------------------------------------
# 2. md5 of a string
# ---------------------------------------------------------------------
subtest 'md5() agrees with Digest::MD5' => sub {
    my %case = (
	'empty'         => '',
	'ascii'         => "hello, world\n",
	'a mail body'   => "From: a\@example.jp\n\nbody\n",
	# Mail is octets.  A checksum that decoded first would differ.
	'euc-jp octets' => "\xc6\xfc\xcb\xdc\xb8\xec",
	'utf-8 octets'  => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e",
	'binary'        => join('', map { chr($_) } 0 .. 255),
    );

    for my $name (sort keys %case) {
	my $s    = $case{ $name };
	my $want = Digest::MD5::md5_hex($s);

	is($CK->md5(\$s),         $want, "md5(): $name");
	is($CK->md5_str_ref(\$s), $want, "md5_str_ref(): $name");
    }
};


# ---------------------------------------------------------------------
# 3. the same string must always give the same sum
#
# This is what the duplicate check relies on.
# ---------------------------------------------------------------------
subtest 'md5() is stable and distinguishes' => sub {
    my $a = "the same body\n";
    my $b = "the same body\n";
    my $c = "a different body\n";

    is($CK->md5(\$a), $CK->md5(\$b), 'equal strings, equal sums');
    isnt($CK->md5(\$a), $CK->md5(\$c), 'different strings, different sums');

    # One octet apart, which is what a forwarded copy looks like.
    my $d = "the same body";
    isnt($CK->md5(\$a), $CK->md5(\$d), 'a trailing newline changes the sum');
};


# ---------------------------------------------------------------------
# 4. cksum2() runs at all
#
# It could not before: open($file, $file) is a symbolic reference.
# ---------------------------------------------------------------------
subtest 'cksum2() returns a checksum instead of dying' => sub {
    my $data = "hello, world\n";
    my $path = spew("$TMPDIR/plain", $data);

    my @got = eval { $CK->cksum2($path) };
    ok(!$@, 'cksum2() does not die') or diag($@);

    is(scalar(@got), 2, 'it returns two values');

    my @want = reference_cksum2($data);
    is($got[0], $want[0], 'the checksum is the System V one');
    is($got[1], $want[1], 'the byte count is the file size');
};


# ---------------------------------------------------------------------
# 5. it counts octets, not characters
# ---------------------------------------------------------------------
subtest 'cksum2() works on octets' => sub {
    my %case = (
	'empty'    => '',
	'euc-jp'   => "\xc6\xfc\xcb\xdc\xb8\xec",
	'utf-8'    => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e",
	'high bit' => "\xff" x 100,
	# Longer than the 1024 byte read buffer, so the loop runs more
	# than once and the running total has to survive.
	'long'     => "0123456789" x 500,
    );

    for my $name (sort keys %case) {
	my $data = $case{ $name };
	my $path = spew("$TMPDIR/oct.$name", $data);

	my @got  = $CK->cksum2($path);
	my @want = reference_cksum2($data);

	is_deeply(\@got, \@want, "cksum2(): $name");
    }
};


# ---------------------------------------------------------------------
# 6. a file name is a file name, not a mode
#
# With the two-argument open() a name beginning with ">" opened the file
# for writing and truncated it; one beginning with "|" ran it.  Neither
# is reachable through the three-argument form.
# ---------------------------------------------------------------------
subtest 'a name that looks like a mode is still just a name' => sub {
    my $data = "do not truncate me\n";

    for my $name ('>gt', '>>gtgt', '<lt', '| pipe', '+<plus') {
	my $path = "$TMPDIR/$name";
	spew($path, $data);

	my @got = eval { $CK->cksum2($path) };
	ok(!$@, "cksum2() reads [$name]") or diag($@);

	is_deeply(\@got, [ reference_cksum2($data) ],
		  "[$name]: checksummed rather than opened as a mode");

	# And it is still there, with its contents.
	ok(-s $path == length($data), "[$name]: the file was not truncated");
    }
};


# ---------------------------------------------------------------------
# 7. a missing file is an error, not a zero
#
# Returning (0, 0) for a file that is not there would make an unreadable
# article look like an empty one.
# ---------------------------------------------------------------------
subtest 'cksum2() croaks on a file it cannot open' => sub {
    my @got = eval { $CK->cksum2("$TMPDIR/no-such-file") };

    ok($@, 'it dies');
    like($@, qr/no such file/i, 'and says which file');
};


# ---------------------------------------------------------------------
# 8. the bug was real
#
# open($file, $file) with a string in the first slot is a symbolic
# reference.  Under "use strict refs", which this module has at the top,
# that is fatal.  Demonstrated here so the fix is not mistaken for
# tidying.
# ---------------------------------------------------------------------
subtest 'the old open() form is fatal under strict refs' => sub {
    my $path = spew("$TMPDIR/strict-refs", "x\n");

    my $err = '';
    {
	use strict 'refs';
	my $file = $path;
	eval { open($file, $file) or die "open failed: $!" };
	$err = $@;
    }

    ok($err, 'the old form dies');
    like($err, qr/strict refs|symbolic ref/i,
	 'and it dies as a symbolic reference, not as a missing file');

    # The new form reads the same file without complaint.
    my @got = eval { $CK->cksum2($path) };
    ok(!$@, 'the current code reads it') or diag($@);
    is($got[1], 2, 'two octets');
};

done_testing();
