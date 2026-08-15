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


=head2 password_length_hard_limit()

the length below which a password is not stored at all.

=head2 password_length_lower_limit()

the length below which a password is stored, but remarked on.

Two lines, drawn from two places.

NIST SP 800-63B puts a password used as one factor among several at
"a minimum of eight characters in length", and one used on its own --
which is what an fml8 administrator password is -- at "a minimum of 15
characters".  NISC's own handbook, which is what the people running a
Japanese mailing list are more likely to have read, treats ten
characters as the point at which a password is in the safe range.

So fml8 refuses anything under ten, and remarks on anything under
fifteen.

Ten rather than eight for the refusal, for a reason particular to this
program: every password an existing installation holds was stored by
the old scheme, which hashed the first eight characters and threw the
rest away.  Setting the line at eight would let somebody told to change
their password set another eight-character one and gain nothing at all,
which is the situation the change was made to leave.

Fifteen is a remark rather than a refusal because the command interface
is mail: there is no prompt to answer, so the choice is between
accepting with a remark and refusing outright, and refusing would break
whatever already calls makefml changepassword.

Note that no composition rule is imposed -- no required mixture of
letters, digits and symbols.  SP 800-63B says a verifier "SHALL NOT
impose other composition rules", and length is what this checks.

=head2 is_too_short($password)

is $password below the hard limit, and so not to be stored?

=head2 is_short($password)

is $password below the lower limit, and so worth remarking on?

=cut


# Descriptions: the length below which a password is not stored at all.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: NUM
sub password_length_hard_limit
{
    my ($self) = @_;

    return 10;
}


# Descriptions: the length below which a password is worth remarking on.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: NUM
sub password_length_lower_limit
{
    my ($self) = @_;

    return 15;
}


# Descriptions: is $password below the hard limit?
#    Arguments: OBJ($self) STR($password)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub is_too_short
{
    my ($self, $password) = @_;

    return 1 unless defined $password;
    return length($password) < $self->password_length_hard_limit() ? 1 : 0;
}


# Descriptions: is $password below the lower limit?
#    Arguments: OBJ($self) STR($password)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub is_short
{
    my ($self, $password) = @_;

    return 1 unless defined $password;
    return length($password) < $self->password_length_lower_limit() ? 1 : 0;
}


=head2 blocklist_reason($password, $args)

is $password one that should not be used?  Returns a short reason if it
is, and the empty string if nothing objected.

NIST SP 800-63B says a verifier "SHALL compare the prospective secret
against a blocklist that contains known commonly used, expected, or
compromised passwords".  Three kinds of thing, and this checks them in
that order, cheapest first.

I<expected> is the context: the name of the list, the address the
password belongs to, the domain it is in.  These cost nothing to check
and are the first thing anyone guessing would try.  Pass them in
$args->{ terms }.

I<commonly used> is a file of one password per line, at
$args->{ file }.  A site can point that at whatever list it likes.

I<compromised> is the Pwned Passwords range service, used when
$args->{ use_service } is set.  This method does not set it -- a
library should not reach the network because it was called -- but
fml8's own caller does, unless the site has said
use_password_blocklist_service = no.

It is on because it is the only one of the three that can tell a
password has already been stolen, and because length does not rescue
one that has: "correct horse battery staple" is twenty-nine characters
and is in the data 391 times.

The password is not sent anywhere.  The service takes the first five
hexadecimal digits of its SHA-1 and answers with every suffix it holds
under that prefix -- some thousands of them -- and the comparison
happens here.  What leaves the host is five characters that some
half-million passwords share, which is the point of the arrangement:
the service cannot tell which password was asked about.

It does mean fml talks to a third party while handling a password
change, and a site that would rather it did not has one setting to turn
off.

If the service cannot be reached the password is accepted and the
caller is told nothing objected: a list that stopped being able to
change its passwords because a web service was down would be worse off
than one that accepted a weak one.  The failure belongs in the log, not
in the way.

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


# Descriptions: is $password one that should not be used?
#               returns a reason, or the empty string.
#    Arguments: OBJ($self) STR($password) HASH_REF($args)
# Side Effects: may talk to the network when $args->{ use_service }.
# Return Value: STR
sub blocklist_reason
{
    my ($self, $password, $args) = @_;

    return '' unless defined $password && length $password;
    $args ||= {};

    my $r = '';

    $r = $self->_reason_context($password, $args->{ terms });
    return $r if $r;

    $r = $self->_reason_file($password, $args->{ file });
    return $r if $r;

    if ($args->{ use_service }) {
	$r = $self->_reason_service($password, $args);
	return $r if $r;
    }

    return '';
}


# Descriptions: does $password give away where it is from?
#               the comparison is case insensitive: "Elena" is no more
#               of a secret than "elena".
#    Arguments: OBJ($self) STR($password) ARRAY_REF($terms)
# Side Effects: none
# Return Value: STR
sub _reason_context
{
    my ($self, $password, $terms) = @_;

    return '' unless ref($terms) eq 'ARRAY';

    my $p = lc($password);

    for my $t (@$terms) {
	next unless defined $t && length($t) >= 3;
	my $lc = lc($t);

	# equal to it, or the whole of it with something stuck on: both
	# are the guess anybody would make first.
	return "it is built from \"$t\"" if index($p, $lc) >= 0;
    }

    return '';
}


# Descriptions: is $password in the site's own list of ones not to use?
#    Arguments: OBJ($self) STR($password) STR($file)
# Side Effects: none
# Return Value: STR
sub _reason_file
{
    my ($self, $password, $file) = @_;

    return '' unless defined $file && length $file;
    return '' unless -f $file;

    open(my $fh, '<', $file) or return '';
    binmode($fh);

    my $p    = lc($password);
    my $seen = 0;

    while (my $line = <$fh>) {
	chomp($line);
	$line =~ s/\r$//;
	next unless length $line;
	next if $line =~ /^\s*#/;

	if (lc($line) eq $p) { $seen = 1; last }
    }
    close($fh);

    return $seen ? "it is in this site's list of passwords not to use" : '';
}


# Descriptions: has $password turned up in a breach?
#               only the first five hexadecimal digits of its SHA-1 are
#               sent; the answer is a list of suffixes to compare here.
#    Arguments: OBJ($self) STR($password) HASH_REF($args)
# Side Effects: one HTTPS request.
# Return Value: STR
sub _reason_service
{
    my ($self, $password, $args) = @_;

    my $base    = $args->{ service_url } ||
	          'https://api.pwnedpasswords.com/range';
    my $timeout = $args->{ timeout } || 10;

    my $ok = eval {
	require Digest::SHA;
	require HTTP::Tiny;
	1;
    };
    return '' unless $ok;

    my $sha = uc(Digest::SHA::sha1_hex($password));
    my ($prefix, $suffix) = (substr($sha, 0, 5), substr($sha, 5));

    my $res = eval {
	HTTP::Tiny->new(timeout => $timeout,
			agent   => 'fml8')->get("$base/$prefix");
    };

    # XXX unreachable, refused, timed out, anything: accept the password.
    # XXX A list that could not change its passwords because a web
    # XXX service was down would be worse off than one that accepted a
    # XXX weak password.
    return '' unless ref($res) eq 'HASH' && $res->{ success };
    return '' unless defined $res->{ content };

    for my $line (split(/\r?\n/, $res->{ content })) {
	my ($tail, $count) = split(/:/, $line, 2);
	next unless defined $tail;
	next unless uc($tail) eq $suffix;

	$count = 0 unless defined $count;
	$count =~ s/\D//g;

	return "it appears in known breaches ($count times)";
    }

    return '';
}


=head2 blocklist_service_decision($dir)

has this site said whether fml may ask the breach service?  Returns
"yes", "no", or the empty string if nobody has been asked yet.

=head2 ask_blocklist_service($dir)

ask, if there is somebody there to answer, and remember what they said.

The question is put once, the first time a command line tool runs after
this release is installed, and only when standard input and output are
a terminal.  Mail arrives without one, so nothing is ever asked while
handling a message; an installation that has not answered simply does
not use the service.

That is the whole of the arrangement: fml does not reach a third party
until somebody at a keyboard has said it may.

The answer is written to $dir/password_blocklist_service.  Deleting
that file asks again.

=cut


# The file the answer is kept in, under the site's config directory.
my $BLOCKLIST_DECISION_FILE = 'password_blocklist_service';

# What the question says.  Deliberately ASCII: this goes to a terminal
# whose encoding nothing here knows, and a prompt about protecting
# passwords is a poor place to produce mojibake.
my $BLOCKLIST_PROMPT = <<'EOT';

fml can check a new password against Have I Been Pwned's list of
passwords found in published breaches, and refuse one that is on it.
This catches what a length check cannot: "correct horse battery staple"
is twenty-nine characters long and appears in that data 391 times.

Doing so means this host makes an HTTPS request when an administrator
changes their password.  The password is not sent.  Five hexadecimal
digits of its SHA-1 are, and some half a million different passwords
share any five, so the service is not told which password was asked
about.

If this host has no route out, or you would rather it did not talk to
anyone, answer "no".  Nothing else changes; the other blocklist checks
do not use the network.

Pressing return accepts the default, which is yes.

You will not be asked again.  To change your mind later, edit
%s
or set use_password_blocklist_service in your configuration.

EOT


# Descriptions: what has this site said about the breach service?
#    Arguments: OBJ($self) STR($dir)
# Side Effects: none
# Return Value: STR ("yes", "no" or "")
sub blocklist_service_decision
{
    my ($self, $dir) = @_;

    return '' unless defined $dir && length $dir;

    my $file = "$dir/$BLOCKLIST_DECISION_FILE";
    return '' unless -f $file;

    open(my $fh, '<', $file) or return '';
    my $answer = '';
    while (my $line = <$fh>) {
	next if $line =~ /^\s*#/;
	next unless $line =~ /\S/;
	$answer = ($line =~ /^\s*(yes|no)\s*$/i) ? lc($1) : '';
	last;
    }
    close($fh);

    return $answer;
}


# Descriptions: write down what this site said.
#    Arguments: OBJ($self) STR($dir) STR($answer)
# Side Effects: creates $dir/password_blocklist_service.
# Return Value: NUM(1 or 0)
sub record_blocklist_service_decision
{
    my ($self, $dir, $answer) = @_;

    return 0 unless defined $dir && length $dir && -d $dir;
    return 0 unless defined $answer && $answer =~ /^(yes|no)$/;

    my $file = "$dir/$BLOCKLIST_DECISION_FILE";
    open(my $fh, '>', $file) or return 0;

    print $fh "# Whether fml may ask the Pwned Passwords service about a\n";
    print $fh "# new password before storing it.  Written when the\n";
    print $fh "# question was answered at a terminal; remove this file to\n";
    print $fh "# be asked again.\n";
    print $fh "$answer\n";

    close($fh);
    return 1;
}


# Descriptions: ask, if anyone is there, and remember the answer.
#               $in is where to read the answer from and defaults to
#               STDIN; the tests pass a handle of their own rather than
#               needing a terminal.
#    Arguments: OBJ($self) STR($dir) HANDLE($in)
# Side Effects: may write $dir/password_blocklist_service.
# Return Value: STR ("yes", "no" or "")
sub ask_blocklist_service
{
    my ($self, $dir, $in) = @_;

    my $known = $self->blocklist_service_decision($dir);
    return $known if $known;

    # No terminal, no question.  This is the path mail takes, and the
    # answer there is to do nothing until somebody has been asked.
    unless (defined $in) {
	return '' unless -t STDIN && -t STDOUT;
	$in = \*STDIN;
    }
    return '' unless defined $dir && length $dir && -d $dir;

    printf $BLOCKLIST_PROMPT, "$dir/$BLOCKLIST_DECISION_FILE";

    my $answer = '';
    for (1 .. 3) {
	print "Check new passwords against known breaches? [Yes/no] ";
	my $line = <$in>;

	# XXX End of input is not an answer.  Somebody pressing return
	# XXX has answered, and takes the default; a script that closed
	# XXX the handle has not, and gets asked again next time rather
	# XXX than having the default recorded on its behalf.
	last unless defined $line;

	$line =~ s/^\s+//;
	$line =~ s/\s+$//;

	if    ($line eq '')          { $answer = 'yes'; last }
	elsif ($line =~ /^y(es)?$/i) { $answer = 'yes'; last }
	elsif ($line =~ /^n(o)?$/i)  { $answer = 'no';  last }

	print "Please answer yes or no.\n";
    }

    # Nothing usable said: leave it unanswered rather than guessing, so
    # the question comes back next time.
    return '' unless $answer;

    my $what = $answer eq 'yes'
	? "fml will ask the service.\n"
	: "fml will not use the service.\n";

    if ($self->record_blocklist_service_decision($dir, $answer)) {
	print "Recorded. $what";
	return $answer;
    }

    # XXX Could not write it.  $config_dir usually belongs to root or to
    # XXX the fml owner, and whoever is running makefml may be neither,
    # XXX in which case the answer cannot be kept and the question would
    # XXX come back every time.  Say so and name the setting, so it can
    # XXX be answered once in a file the person can actually write.
    print <<"EOT";

Could not write $dir/$BLOCKLIST_DECISION_FILE, so this answer cannot be
remembered and you will be asked again.

To settle it, put

	use_password_blocklist_service	=	$answer

in your configuration, or create that file as the owner of $dir.

EOT

    return $answer;
}


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
