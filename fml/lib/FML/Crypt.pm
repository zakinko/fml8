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
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD $_des_ok);
use Carp;

=head1 NAME

FML::Crypt - raw level crypt library wrapper.

=head1 SYNOPSIS

    use FML::Crypt;
    my $crypt   = new FML::Crypt;
    my $p_input = $crypt->unix_crypt($text, $salt)

=head1 DESCRIPTION

FML::Crypt is an adapter layer for crypt libraries.
Now FML::Crypt is just a wrapper for Crypt::UnixCrypt module.

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
#    Arguments: OBJ($self) STR($text) STR($salt)
# Side Effects: none
# Return Value: STR
sub unix_crypt
{
    my ($self, $text, $salt) = @_;

    # XXX This used to call Crypt::UnixCrypt, a pure perl DES crypt(3)
    # XXX bundled under cpan/lib, with a comment saying to always use
    # XXX that one.  The two agree: the module and the built-in were
    # XXX compared over all 4096 salts against five passwords, 3000
    # XXX random passwords, and non-ASCII input, and answered the same
    # XXX every time -- so the reason for carrying it was portability,
    # XXX not correctness.
    # XXX
    # XXX The portability question is whether the host's libc still does
    # XXX classic DES.  Where it does not -- libxcrypt built with
    # XXX --disable-obsolete-api, say -- crypt() cannot return the
    # XXX answer a stored password was made with, and every password in
    # XXX the map stops matching.  That is worth saying out loud rather
    # XXX than letting it look like the wrong password, so ask a
    # XXX question with a known answer first.
    unless (_libc_does_des()) {
	croak("crypt(3) on this host cannot do DES; stored passwords unreadable");
    }

    return crypt($text, $salt);
}


# Descriptions: does crypt(3) here still answer for classic DES ?
#    Arguments: none
# Side Effects: none
# Return Value: NUM(1 or 0)
sub _libc_does_des
{
    return $_des_ok if defined $_des_ok;

    my $got = eval { crypt("fml", "ab") };

    return( $_des_ok = (defined($got) && $got eq 'abElTpU575Od6') ? 1 : 0 );
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
