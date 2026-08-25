#-*- perl -*-
#
#  Copyright (C) 2001,2002,2003,2004 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#
# $FML: UnixGroup.pm,v 1.21 2004/01/24 09:00:53 fukachan Exp $
#

package FML::IO::Adapter::UnixGroup;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;
use FML::IO::Adapter::Array;

@ISA = qw(FML::IO::Adapter::Array);


=head1 NAME

FML::IO::Adapter::UnixGroup - IO wrapper to read /etc/group.

=head1 SYNOPSIS

    $map = 'unix.group:fml';

    use FML::IO::Adapter;
    $obj = new FML::IO::Adapter $map;
    $obj->open || croak("cannot open $map");
    while ($x = $obj->getline) { ... }
    $obj->close;

/etc/group has C<fml> entry like this:

  fml:*:1000:fukachan

=head1 DESCRIPTION

See L<FML::IO::Adapter::Array> for more details.
It inherits C<FML::IO::Adapter::Array> class.

C<CAUTION: this map is read only>.

=head1 METHOD

=head2 configure($obj)

Configure object for array IO operation.

=cut


# Descriptions: initialize /etc/group specific configuration.
#    Arguments: OBJ($self) HASH_REF($me)
# Side Effects: none
# Return Value: ARRAY_REF
sub configure
{
    my ($self, $me) = @_;
    my ($type)      = ref($self) || $self;

    # emulate an array on memory
    my (@x)        = getgrnam( $me->{_name} );
    my (@elements) = split ' ', $x[3];
    $me->{_array_reference} = \@elements;
}


=head1 SEE ALSO

L<FML::IO::Adapter::Array>

=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2001,2002,2003,2004 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

FML::IO::Adapter::UnixGroup first appeared in fml8 mailing list driver package.
See C<http://www.fml.org/> for more details.

=cut


1;
