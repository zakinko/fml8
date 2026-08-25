#-*- perl -*-
#
#  Copyright (C) 2026 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#

package FML::Unsubscribe;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;
use Digest::SHA qw(hmac_sha256);
use MIME::Base64 qw(encode_base64);

=head1 NAME

FML::Unsubscribe - one-click unsubscribe tokens (RFC 8058).

=head1 SYNOPSIS

    use FML::Unsubscribe;
    my $unsub = new FML::Unsubscribe $curproc;

    my $url = $unsub->url($address);
    if ($unsub->verify($address, $token)) { ... }

=head1 DESCRIPTION

RFC 8058 asks a list to put an HTTPS URI in C<List-Unsubscribe> and to
say so with

    List-Unsubscribe-Post: List-Unsubscribe=One-Click

The receiving mail system then POSTs to that URI with no cookies, no
authorization and no context beyond the URI itself, so section 3.1
requires that

    "The URI MUST contain enough information to identify the mail
     recipient and the list"

and that it

    "SHOULD include an opaque identifier or another hard-to-forge
     component".

Two things follow for fml8.

The URL is per recipient, so one message can no longer be handed to the
MTA for many recipients at once.  See C<use_rfc8058_one_click> in
config.cf for how that is arranged.

And the token has to be verifiable without being stored.  A list with
ten thousand members should not acquire ten thousand rows per article.
So it is an HMAC over the list, the address and a coarse timestamp,
keyed by a secret the list already has.  Nothing is written down; the
same inputs recompute the same token.

=head1 METHODS

=cut


# How long a token stays good, in days.  The RFC says nothing about
# expiry -- it is a defence against a token scraped from an archived
# message being used years later.  A week is what Sympa chose.
my $LIFETIME_DAYS = 7;

# How many bytes of the digest go into the URL.  16 bytes is 128 bits,
# base64url'd to 22 characters -- long enough that guessing is not a
# strategy, short enough that the header still folds tidily.
my $TOKEN_BYTES = 16;


=head2 new($curproc)

constructor.

=cut


# Descriptions: constructor.
#    Arguments: OBJ($self) OBJ($curproc)
# Side Effects: none
# Return Value: OBJ
sub new
{
    my ($self, $curproc) = @_;
    my ($type) = ref($self) || $self;
    my $me     = { _curproc => $curproc };

    return bless $me, $type;
}


# Descriptions: the secret this list signs tokens with.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: STR
sub _secret
{
    my ($self)  = @_;
    my $curproc = $self->{ _curproc };
    my $config  = $curproc->config();

    # XXX The list already holds one secret that never leaves the
    # XXX server: the admin password map.  Reusing it would tie an
    # XXX unsubscribe token to the password, so that changing the
    # XXX password silently invalidates every token in flight, and a
    # XXX token leak becomes a password question.  Keep them apart.
    my $secret = $config->{ unsubscribe_token_secret } || '';

    unless ($secret) {
	# XXX Without a configured secret, derive one from values that
	# XXX are stable for this list and not published in the mail.
	# XXX This is weaker than a real secret -- ml_home_dir is not
	# XXX secret from anyone with a shell on the box -- but it is
	# XXX better than a constant, and it means the feature works
	# XXX before anybody has been told to set anything.
	$secret = sprintf("%s\t%s\t%s",
			  $config->{ ml_name }     || '',
			  $config->{ ml_domain }   || '',
			  $config->{ ml_home_dir } || '');
    }

    return $secret;
}


# Descriptions: the coarse timestamp a token is bound to.
#    Arguments: OBJ($self) NUM($time)
# Side Effects: none
# Return Value: NUM
sub _epoch_day
{
    my ($self, $time) = @_;

    $time = time unless defined $time;

    return int($time / 86400);
}


=head2 token($address [, $day])

the token for $address.

=cut


# Descriptions: the token for $address.
#    Arguments: OBJ($self) STR($address) NUM($day)
# Side Effects: none
# Return Value: STR
sub token
{
    my ($self, $address, $day) = @_;
    my $config = $self->{ _curproc }->config();

    return '' unless defined $address && length $address;

    $day = $self->_epoch_day() unless defined $day;

    # XXX The list is in the input so that a token for one list cannot
    # XXX unsubscribe the same person from another, and the day is in
    # XXX it so that an old token stops working.
    my $data = sprintf("%s\t%s\t%s\t%d",
		       $config->{ ml_name }   || '',
		       $config->{ ml_domain } || '',
		       lc($address),
		       $day);

    my $digest = hmac_sha256($data, $self->_secret());
    my $b64    = encode_base64(substr($digest, 0, $TOKEN_BYTES), '');

    # base64url: the token travels in a URL, so + / = have to go.
    $b64 =~ tr{+/}{-_};
    $b64 =~ s/=+$//;

    return sprintf("%d.%s", $day, $b64);
}


=head2 verify($address, $token)

is $token a token this list issued for $address, and is it still good ?

=cut


# Descriptions: is $token this list's token for $address, still in date ?
#    Arguments: OBJ($self) STR($address) STR($token)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub verify
{
    my ($self, $address, $token) = @_;

    return 0 unless defined $address && length $address;
    return 0 unless defined $token   && length $token;

    my ($day) = $token =~ /^(\d+)\./;
    return 0 unless defined $day;

    my $today = $self->_epoch_day();

    # XXX Not in the future: a token dated tomorrow was not issued here.
    return 0 if $day > $today;
    return 0 if $today - $day > $LIFETIME_DAYS;

    return _eq($self->token($address, $day), $token);
}


=head2 url($address)

the HTTPS URI to put in List-Unsubscribe.

=cut


# Descriptions: the HTTPS URI for $address.
#    Arguments: OBJ($self) STR($address)
# Side Effects: none
# Return Value: STR
sub url
{
    my ($self, $address) = @_;
    my $config = $self->{ _curproc }->config();
    my $base   = $config->{ unsubscribe_one_click_url } || '';

    return '' unless $base;
    return '' unless defined $address && length $address;

    # XXX RFC 8058 section 3.1: the URI must be HTTPS.  A plain http
    # XXX URI here would have the receiving mail system POST a member's
    # XXX address over the wire in clear, on the say-so of a header
    # XXX anyone can forge into a copy of the message.
    return '' unless $base =~ m{^https://};

    my $sep = ($base =~ /\?/) ? '&' : '?';

    return sprintf("%s%sa=%s&t=%s",
		   $base, $sep,
		   _urlencode($address),
		   _urlencode($self->token($address)));
}


# Descriptions: percent-encode for a URL query.
#    Arguments: STR($s)
# Side Effects: none
# Return Value: STR
sub _urlencode
{
    my ($s) = @_;

    return '' unless defined $s;
    $s =~ s{([^A-Za-z0-9._~-])}{sprintf("%%%02X", ord($1))}ge;

    return $s;
}


# Descriptions: are these equal ? takes the same time either way.
#    Arguments: STR($a) STR($b)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub _eq
{
    my ($a, $b) = @_;

    return 0 unless defined $a && defined $b;
    return 0 unless length($a) == length($b);

    # XXX A byte-by-byte eq returns as soon as it finds a difference,
    # XXX so how long the answer takes says where the first wrong byte
    # XXX was, and the endpoint answers to anybody.
    my $diff = 0;
    for (my $i = 0; $i < length($a); $i++) {
	$diff |= ord(substr($a, $i, 1)) ^ ord(substr($b, $i, 1));
    }

    return( $diff ? 0 : 1 );
}


=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2026 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

FML::Unsubscribe appeared in fml8 mailing list driver package.

=cut


1;
