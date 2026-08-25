#-*- perl -*-
#
#  Copyright (C) 2004,2005 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#
# $FML: Address.pm,v 1.7 2005/08/19 12:17:13 fukachan Exp $
#

package Mail::Message::Address;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;
use Mail::Address;


=head1 NAME

Mail::Message::Address - manipulate address type string.

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is an adapter for Mail::Address for convenience.

=head1 METHODS

=head2 new()

constructor.

=cut


# Descriptions: constructor.
#    Arguments: OBJ($self) STR($str)
# Side Effects: none
# Return Value: OBJ
sub new
{
    my ($self, $str) = @_;
    my ($type) = ref($self) || $self;

    # parse it by Mail::Address.
    my (@addrs) = Mail::Address->parse($str);
    _repair_group_syntax(\@addrs);
    my $addr    = @addrs ? $addrs[0]->address : '';

    # XXX in-core data area.
    # XXX if we manipulate Mail::Address object, it is dangerous. So
    # XXX not use @ISA to Mail::Address class but use it via AUTOLOAD()
    # XXX as object composition.
    my $me = {
	_addrs       => \@addrs,
	_addr_head   => $addrs[0] || '',
	_string      => $addr     || '',
	_orig_string => $str      || '',
    };

    return bless $me, $type;
}


# Descriptions: undo what Mail::Address does to RFC 5322 group syntax.
#
#               RFC 5322 section 3.4 defines
#
#                   group = display-name ":" [group-list] ";" [CFWS]
#
#               which is part of the core grammar, not an extension.
#               Mail::Address does not implement it.  Given
#
#                   friends: taro@example.jp, hanako@example.jp;
#
#               it returns two addresses and both are wrong:
#               "friends:taro@example.jp" carries the group name and
#               "hanako@example.jp;" carries the terminator.  With a
#               group name of more than one word it is worse still --
#
#                   A Group: a@x.jp, b@y.jp; c@z.jp
#                     -> "A", "Group:a@x.jp", "b@y.jp;c@z.jp"
#
#               -- so the count is wrong too, not just the strings.
#
#               fml8 decides who is a member by comparing addresses, so
#               none of those match anybody: a member posting to that
#               header is treated as a stranger.
#
#               Repairing afterwards is the small fix.  The other way --
#               Mail::Message, whose parser is correct -- pulls in 223
#               modules and reaches XS, which fml8 cannot bundle.
#
#               A colon cannot appear in an unquoted local part and a
#               semicolon cannot appear in a domain (RFC 5322 section
#               3.2.3 and 3.4.1), so neither rule can fire on an
#               address that is not part of a group.
#
#    Arguments: ARRAY_REF($addrs)
# Side Effects: replace the contents of $addrs.
# Return Value: none
sub _repair_group_syntax
{
    my ($addrs) = @_;

    return unless ref($addrs) eq 'ARRAY';
    return unless @$addrs;

    my @out = ();
    for my $a (@$addrs) {
	next unless defined $a;
	my $addr = eval { $a->address() };
	next unless defined $addr;

	# XXX A semicolon inside the string means two addresses were run
	# XXX together across a group terminator.  Split first, repair
	# XXX each piece, and let the count come out right.
	for my $part (split(/;/, $addr)) {
	    $part =~ s/^[^"<>@]*://;   # the group name and its colon
	    $part =~ s/^\s+//;
	    $part =~ s/\s+$//;

	    # XXX What is left of an empty group ("undisclosed-recipients:;")
	    # XXX or of a mangled group name ("A") is not an address.
	    next unless length $part;
	    next unless $part =~ /\@/;

	    if ($part eq $addr) {
		push @out, $a;      # untouched; keep the original object
		next;
	    }

	    # XXX Build a new object rather than reaching inside this one.
	    # XXX Mail::Address is an ARRAY underneath in 2.x and was a
	    # XXX HASH earlier; either way its layout is not ours to
	    # XXX write to.
	    push @out, Mail::Address->new($a->phrase(), $part, $a->comment());
	}
    }

    @$addrs = @out;
}

# Descriptions: return date as string.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: STR
sub as_str
{
    my ($self) = @_;

    return $self->{ _string };
}


=head1 CLEAN UP

=head2 cleanup()

clean up address. no return value.

=cut


# Descriptions: utility to remove ^\s*< and >\s*$.
#    Arguments: OBJ($self)
# Side Effects: update $self->{ _string }.
# Return Value: none
sub cleanup
{
    my ($self) = @_;
    my $addr   = $self->{ _string } || '';

    # 1. remove ^\s*< and >\s*$.
    $addr =~ s/^\s*<//o;
    $addr =~ s/>\s*$//o;

    # return the result.
    $self->{ _string } = $addr || '';
}


=head1 UTILITIES

=head2 substr($offset, $len)

return $len byte of data from $offset.

=cut


# Descriptions: return substr()-fied data.
#    Arguments: OBJ($self) NUM($offset) NUM($len)
# Side Effects: none
# Return Value: STR
sub substr
{
    my ($self, $offset, $len) = @_;
    my $addr = $self->{ _string } || '';

    return substr($addr, $offset, $len);
}


=head1 Mail::Address FORWARDING.

forward request to Mail::Address class. Forwarded requests follow:
phrase, address, comment, format, name, host, user, path, canon.

=cut


# Descriptions: return address by string.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: STR
sub AUTOLOAD
{
    my ($self) = @_;
    my $addr   = $self->{ _addr_head } || undef;

    # we need to ignore DESTROY()
    return if $AUTOLOAD =~ /DESTROY/o;

    my $function = $AUTOLOAD;
    $function =~ s/.*:://o;

    if ($function =~
	/^(phrase|address|comment|format|name|host|user|path|canon)$/o) {
	if (defined $addr) {
	    return $addr->$function();
	}
	else {
	    return '';
	}
    }
    else {
	croak("$function method undefined.");
    }
}


#
# debug
#
if ($0 eq __FILE__) {
    my $format = "%7s %s\n";

    for my $file (@ARGV) {
	use FileHandle;
	my $fh = new FileHandle $file;
	if (defined $fh) {
	    my ($buf, @buf);
	    while (<$fh>) { $buf .= $_ if 1 .. /^$/;}

	    use Mail::Header;
	    my (@hdr) = split(/\n/, $buf);
	    my $hdr   = new Mail::Header \@hdr;
	    my $str   = $hdr->get('from'); $str =~ s/\n$//o;

	    print "\n";
	    printf $format, "FILE", $file;
	    printf $format, "STR",  $str;
	    if ($str) {
		my $m_addr = new Mail::Message::Address $str;
		printf $format, "ADDRESS", $m_addr->address();
		printf $format, "substr",  $m_addr->substr(0, 15);
	    }
	}
    }
}


=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2004,2005 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

Mail::Message::Address appeared in fml8 mailing list driver package.
See C<http://www.fml.org/> for more details.

=cut


1;
