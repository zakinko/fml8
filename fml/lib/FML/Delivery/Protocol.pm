#-*- perl -*-
#
#  Copyright (C) 2006 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#
# $FML: @template.pm,v 1.10 2006/01/07 13:16:41 fukachan Exp $
#

package FML::Delivery::Protocol;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;

use FML::Delivery::Base;
@ISA = qw(FML::Delivery::Base);

# import
use FML::Delivery::Net::INET4;
use FML::Delivery::Net::INET6;


=head1 NAME

FML::Delivery::Protocol - protocol base class

=head1 SYNOPSIS

=head1 DESCRIPTION

Currently, this class just inherits FML::Delivery::Base as a dummy.

=head1 METHODS

=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2006 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

FML::Delivery::Protocol appeared in fml8 mailing list driver package.
See C<http://www.fml.org/> for more details.

=cut


1;
