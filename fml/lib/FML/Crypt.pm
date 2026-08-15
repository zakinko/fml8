#-*- perl -*-
#
#  Copyright (C) 2003,2004 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#
# $FML: Crypt.pm,v 1.5 2004/01/02 16:08:37 fukachan Exp $
#

package FML::Crypt;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;
use Digest::SHA qw(hmac_sha256);
use MIME::Base64 qw(encode_base64 decode_base64);

# The scheme new passwords are stored with, and the shape of the string
# they are stored as:
#
#     $pbkdf2-sha256$<iterations>$<salt>$<hash>
#
# with salt and hash in base64.  Traditional crypt(3) output is thirteen
# characters and never contains "$", so which scheme a stored password
# uses can be read off the stored password itself, which is what lets
# both live in one file during a migration.
my $PBKDF2_PREFIX  = 'pbkdf2-sha256';
my $PBKDF2_ROUNDS  = 600_000;
my $PBKDF2_SALTLEN = 16;    # 128 bits; SP 800-63B asks for at least 32
my $PBKDF2_DKLEN   = 32;    # one SHA-256 block

=head1 NAME

FML::Crypt - password hashing and verification.

=head1 SYNOPSIS

    use FML::Crypt;
    my $crypt = new FML::Crypt;

    my $stored = $crypt->hash($password);
    if ($crypt->verify($password, $stored)) { ... }

and, for reading passwords stored by earlier versions,

    my $p_input = $crypt->unix_crypt($text, $salt)

=head1 DESCRIPTION

FML::Crypt stores a password and answers whether a given password
matches one that was stored.

New passwords are hashed with PBKDF2-HMAC-SHA256 over a random salt.
Passwords stored by earlier versions of fml8 used the traditional DES
crypt(3), through Crypt::UnixCrypt, and are still read: verify() picks
the scheme from the stored string rather than being told, so an
installation keeps working with the passwords it already has and gains
the new scheme as they are changed.

=head2 Why the scheme changed

Traditional crypt(3) hashes the first eight characters of a password
and discards the rest, so a password of any length was worth eight
characters.  Its salt is two characters, twelve bits, and fml8 took
those from the process id.  NIST SP 800-63B requires that a verifier
"SHALL request the password to be provided in full ... and SHALL verify
the entire submitted password (e.g., not truncate it)", that the salt
"SHALL be at least 32 bits in length", and that passwords be hashed
with a suitable password hashing scheme.  None of the three held.

=head2 Why not the crypt(3) the host provides

perl's builtin crypt() calls the host's, and what that does is not the
same everywhere: some builds no longer answer for DES at all, and a
stored password has to verify on the machine a list was moved to, not
only the one it was set on.  Digest::SHA is in the perl core and gives
the same answer on every host, so the bundled Crypt::UnixCrypt stays
for reading old passwords and nothing new depends on the platform.

=head1 METHODS

=head2 new()

construcotor.

=cut


# Descriptions: construcotor.
#    Arguments: OBJ($self)
# Side Effects: one
# Return Value: OBJ
sub new
{
    my ($self) = @_;
    my ($type) = ref($self) || $self;
    my $me     = {};
    return bless $me, $type;
}


# XXX-TODO: hmm, strange object framework ?
# XXX-TODO: $str = FML::String; $str->unix_crypt(); ???


# Descriptions: raw level unix crypt(3) interface.
#               Kept for reading passwords stored by earlier versions;
#               hash() is what new passwords go through.
#    Arguments: OBJ($self) STR($text) STR($salt)
# Side Effects: none
# Return Value: STR
sub unix_crypt
{
    my ($self, $text, $salt) = @_;

    # always use this module's crypt: the host's own answers differently
    # from one machine to the next, and some no longer answer at all.
    use Crypt::UnixCrypt;
    return Crypt::UnixCrypt::crypt($text, $salt);
}


=head2 hash($password)

hash $password for storage, and return the string to store.  A fresh
random salt is used, so hashing the same password twice gives two
different answers; both verify.

=cut


# Descriptions: hash $password for storage.
#    Arguments: OBJ($self) STR($password)
# Side Effects: none
# Return Value: STR
sub hash
{
    my ($self, $password) = @_;

    croak("FML::Crypt: no password given") unless defined $password;

    my $salt = $self->_random_salt($PBKDF2_SALTLEN);
    my $dk   = _pbkdf2($password, $salt, $PBKDF2_ROUNDS, $PBKDF2_DKLEN);

    return sprintf('$%s$%d$%s$%s',
		   $PBKDF2_PREFIX, $PBKDF2_ROUNDS,
		   _b64($salt), _b64($dk));
}


=head2 verify($password, $stored)

is $password the password that $stored was made from?

The scheme is read from $stored, so this answers for both what hash()
writes now and what earlier versions of fml8 wrote.

=cut


# Descriptions: does $password match $stored?
#    Arguments: OBJ($self) STR($password) STR($stored)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub verify
{
    my ($self, $password, $stored) = @_;

    return 0 unless defined $password && defined $stored;
    return 0 unless length $stored;

    if ($stored =~ /^\$\Q$PBKDF2_PREFIX\E\$(\d+)\$([^\$]+)\$(.+)$/) {
	my ($rounds, $salt_b64, $want_b64) = ($1, $2, $3);

	my $salt = decode_base64($salt_b64);
	my $want = decode_base64($want_b64);
	my $got  = _pbkdf2($password, $salt, $rounds, length($want));

	return _eq_const($got, $want);
    }

    # XXX anything else is taken to be traditional crypt(3), which is
    # XXX what every fml8 before this wrote.  Verification there is to
    # XXX re-run crypt with the stored string as the salt -- crypt takes
    # XXX the first two characters and ignores the rest -- and compare.
    my $got = $self->unix_crypt($password, $stored);

    return _eq_const($got, $stored);
}


=head2 is_legacy($stored)

was $stored written by the old scheme?

Use it to tell the owner of the password that it should be changed.  Do
B<not> use it to re-store the password automatically after a successful
check, tempting as that is: the old scheme verifies on the first eight
characters, so a caller who guessed those and no more would pass, and
re-storing what they typed would set the account's password to the
guess and lock the real owner out.  Migration has to go through a
password the owner chose, in full.

=cut


# Descriptions: was $stored written by the old scheme?
#    Arguments: OBJ($self) STR($stored)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub is_legacy
{
    my ($self, $stored) = @_;

    return 0 unless defined $stored && length $stored;
    return $stored =~ /^\$\Q$PBKDF2_PREFIX\E\$/ ? 0 : 1;
}


# Descriptions: PBKDF2-HMAC-SHA256, RFC 8018 section 5.2.
#               Digest::SHA is in the perl core, so this needs nothing
#               bundled and answers the same on every host.
#    Arguments: STR($password) STR($salt) NUM($rounds) NUM($dklen)
# Side Effects: none
# Return Value: STR (octets)
sub _pbkdf2
{
    my ($password, $salt, $rounds, $dklen) = @_;

    my $out   = '';
    my $block = 1;

    while (length($out) < $dklen) {
	my $u = hmac_sha256($salt . pack('N', $block), $password);
	my $t = $u;

	for (my $i = 1; $i < $rounds; $i++) {
	    $u = hmac_sha256($u, $password);
	    $t ^= $u;
	}

	$out .= $t;
	$block++;
    }

    return substr($out, 0, $dklen);
}


# Descriptions: $n octets of salt, from the kernel where there is one.
#    Arguments: OBJ($self) NUM($n)
# Side Effects: none
# Return Value: STR (octets)
sub _random_salt
{
    my ($self, $n) = @_;
    my $buf = '';

    if (open(my $fh, '<', '/dev/urandom')) {
	binmode($fh);
	my $got = read($fh, $buf, $n);
	close($fh);
	return $buf if defined $got && $got == $n;
    }

    # XXX no /dev/urandom.  rand() is not a source of secrets, so say so
    # XXX rather than quietly producing a weak salt: a caller that
    # XXX cannot get randomness should fail, not store something that
    # XXX looks the same as a good one.
    croak("FML::Crypt: cannot read /dev/urandom for a salt");
}


# Descriptions: base64 with no line ending, which is what belongs in a
#               single-line password entry.
#    Arguments: STR($s)
# Side Effects: none
# Return Value: STR
sub _b64
{
    my ($s) = @_;

    return encode_base64($s, '');
}


# Descriptions: compare two strings without letting how long they agree
#               for show up in how long the comparison takes.
#    Arguments: STR($a) STR($b)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub _eq_const
{
    my ($a, $b) = @_;

    return 0 unless defined $a && defined $b;
    return 0 unless length($a) == length($b);

    my $diff = 0;
    for (my $i = 0; $i < length($a); $i++) {
	$diff |= ord(substr($a, $i, 1)) ^ ord(substr($b, $i, 1));
    }

    return $diff == 0 ? 1 : 0;
}


=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2003,2004 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

FML::Crypt appeared in fml8 mailing list driver package.
See C<http://www.fml.org/> for more details.

=cut


1;
