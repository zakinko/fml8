#-*- perl -*-
#
#  Copyright (C) 2026 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#

package FML::CGI::Unsubscribe;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK);
use Carp;
use CGI qw/:standard/; # load standard CGI routines

=head1 NAME

FML::CGI::Unsubscribe - the endpoint RFC 8058 posts to.

=head1 DESCRIPTION

RFC 8058 section 3.2: the receiving mail system sends

    POST /the/uri HTTP/1.1
    Content-Type: application/x-www-form-urlencoded

    List-Unsubscribe=One-Click

and section 3.1 says the request carries no cookies, no HTTP
authorization and no other context.  So everything needed is in the
URI, and the answer must not be a redirect --

    "The mail sender MUST NOT return an HTTPS redirect, since
     redirected POST actions have historically not worked reliably"

-- which is why this returns 200 with a short page rather than
bouncing the caller somewhere friendlier.

A GET on the same URI is a person who clicked the link by hand, and
gets a confirmation form.  Only the POST unsubscribes.

=head1 METHODS

=cut


=head2 run($curproc, $args)

handle one request.

=cut


# Descriptions: handle one one-click request.
#    Arguments: OBJ($self) OBJ($curproc) HASH_REF($args)
# Side Effects: may unsubscribe the address named in the URI.
# Return Value: none
sub run
{
    my ($self, $curproc, $args) = @_;

    my $method  = $ENV{ REQUEST_METHOD } || '';
    my $address = $args->{ address }     || '';
    my $token   = $args->{ token }       || '';
    my $confirm = $args->{ confirm }     || '';

    unless ($address && $token) {
	return $self->_reply($curproc, 400, "missing address or token");
    }

    use FML::Unsubscribe;
    my $unsub = new FML::Unsubscribe $curproc;

    unless ($unsub->verify($address, $token)) {
	# XXX Say the same thing for a forged token and an expired one.
	# XXX Telling them apart tells somebody probing the endpoint
	# XXX which addresses are members.
	return $self->_reply($curproc, 403, "this link is no longer valid");
    }

    if ($method eq 'POST' && $confirm eq 'One-Click') {
	return $self->_unsubscribe($curproc, $address);
    }

    if ($method eq 'POST') {
	# XXX A POST without the pair is not RFC 8058.  Treat it as a
	# XXX form submission from the page below, which carries its own
	# XXX field, rather than acting on an unexplained POST.
	if (($args->{ submit } || '') eq 'unsubscribe') {
	    return $self->_unsubscribe($curproc, $address);
	}

	return $self->_reply($curproc, 400, "unexpected POST");
    }

    # A person following the link.
    return $self->_form($curproc, $address, $token);
}


# Descriptions: do it.
#    Arguments: OBJ($self) OBJ($curproc) STR($address)
# Side Effects: update the member map.
# Return Value: none
sub _unsubscribe
{
    my ($self, $curproc, $address) = @_;

    my $ok = eval {
	use FML::Command;
	my $command = new FML::Command;
	$command->auth_level('user');
	$command->unsubscribe($curproc, {
	    command_context => undef,
	    address         => $address,
	});
	1;
    };

    unless ($ok) {
	$curproc->logerror("one-click: $@");
	return $self->_reply($curproc, 500, "could not unsubscribe");
    }

    $curproc->log("one-click: unsubscribed $address");

    # XXX 200, not a redirect.  See the note at the top.
    return $self->_reply($curproc, 200, "unsubscribed");
}


# Descriptions: the page a person gets on GET.
#    Arguments: OBJ($self) OBJ($curproc) STR($address) STR($token)
# Side Effects: none
# Return Value: none
sub _form
{
    my ($self, $curproc, $address, $token) = @_;
    my $charset = eval { $curproc->langinfo_get_charset("cgi") } || 'us-ascii';

    print header(-type => "text/html; charset=$charset");
    print start_html(-title => 'unsubscribe', -lang => $charset);

    printf("<p>%s</p>\n",
	   escapeHTML(sprintf("Remove %s from this list?", $address)));

    # XXX POST to the same URI.  RFC 8058 section 3.2: "The target of
    # XXX the POST action is the same as the one in the GET action for
    # XXX a manual unsubscription."
    print start_form();
    print hidden(-name => 'a',      -value => $address);
    print hidden(-name => 't',      -value => $token);
    print hidden(-name => 'submit', -value => 'unsubscribe');
    print submit(-name => 'unsubscribe');
    print end_form();
    print end_html();
}


# Descriptions: a short answer with a status.
#    Arguments: OBJ($self) OBJ($curproc) NUM($code) STR($text)
# Side Effects: none
# Return Value: none
sub _reply
{
    my ($self, $curproc, $code, $text) = @_;

    my %status = (
	200 => '200 OK',
	400 => '400 Bad Request',
	403 => '403 Forbidden',
	500 => '500 Internal Server Error',
    );

    printf("Status: %s\r\n", $status{ $code } || '200 OK');
    print  "Content-Type: text/plain; charset=us-ascii\r\n";
    print  "\r\n";
    printf("%s\n", $text);
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

FML::CGI::Unsubscribe appeared in fml8 mailing list driver package.

=cut


1;
