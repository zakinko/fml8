#-*- perl -*-
#
#  Copyright (C) 2018 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#
# $FML$
#

package FML::Message::Encode::Perl;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;
use Encode;
use Encode::MIME::Header;

# The charset of the "external printable form", which is what gets written
# to local files such as "summary" and "log".  It is NOT used for mail
# transfer.
#
# XXX-TODO: this should become UTF-8.  Existing installations have EUC-JP
# XXX-TODO: files on disk already, so flipping it mixes encodings in one
# XXX-TODO: archive; that migration has to be decided separately.  Callers
# XXX-TODO: that know better can override per object with
# XXX-TODO: FML::Message::String::set_mime_charset().
my $default_external_charset = "EUC-JP";

=head1 NAME

FML::Message::Encode::Perl - Perl (character-oriented) based Encoding

=head1 SYNOPSIS

    use FML::Message::Encode::Perl;
    my $obj = new FML::Message::Encode::Perl;

    my $pif_str = $obj->mime_header_decode($str);
    # ("[BSG:75] Re: Exodus Part II", "UTF-8", "base64")

    # ... several works ... 
    $pif_str  =~ s/Re: //;
    FML::Message::Subject->rewrite_XXX($pif_str);

    $mime_str = $obj->mime_header_encode($pif_str);
    print $mime_str;

=head1 DESCRIPTION

=head1 METHODS

=head2 new()

constructor.

=cut


# Descriptions: constructor.
#    Arguments: OBJ($self) HASH_REF($args)
# Side Effects: none
# Return Value: OBJ
sub new
{
    my ($self, $args) = @_;
    my ($type) = ref($self) || $self;
    my $me     = {};
    return bless $me, $type;
}


=head2 guess_encoding($str)

speculate the encoding of $str string. it returns one of
C<utf8>, C<euc>, C<sjis>, C<jis>, C<ascii>,
or C<unknown> if the encoding cannot be decided.

$str is checked by C<Encode::Guess>, which is in the perl core.
Since C<Encode::Guess> cannot tell euc-jp from shiftjis unless it is
told which encodings to consider, the candidates are fixed to
euc-jp, shiftjis and 7bit-jis here.

C<CAUTION>: Hmm, we suppose we handle only Japanese and English here...

=cut


# XXX Encode::Guess needs to be told which encodings to consider, it
# XXX cannot tell euc-jp from shiftjis on its own.  The names it returns
# XXX are Encode's, so map them back to the ones this package has always
# XXX returned.
my @guess_suspects = qw(euc-jp shiftjis 7bit-jis);

my %guess_name_map = (
		      'utf8'     => 'utf8',
		      'euc-jp'   => 'euc',
		      'shiftjis' => 'sjis',
		      '7bit-jis' => 'jis',
		      'ascii'    => 'ascii',
		      );


# Descriptions: speculate code of $str string.
#    Arguments: OBJ($self) STR($str)
# Side Effects: none
# Return Value: STR
sub guess_encoding
{
    my ($self, $str) = @_;

    # XXX this used to call Unicode::Japanese, which is the only reason
    # XXX this package needed anything outside the perl core.  Encode
    # XXX and Encode::Guess are both core and agree with it on utf8,
    # XXX euc-jp, shiftjis, iso-2022-jp and ascii.
    use Encode::Guess;
    my $guess = Encode::Guess->guess($str, @guess_suspects);

    # guess() returns an error string, not an object, when it cannot
    # decide. "unknown" is what the rest of fml8 expects in that case.
    return 'unknown' unless ref $guess;

    return( $guess_name_map{ $guess->name } || 'unknown' );
}


=head2 mime_header_enecode($str)

encode the given Perl internal format string to the mime header one.

=head2 mime_header_decode($str)

decode the given mime header format string to the Perl internal one.

=head3 CAUTION

In the current Perl (for backward compatibility), 
we need to handle the string this way.

   IN -> decode() -> Perl Internal UTF8 format -> encode() -> OUT

=cut

# Descriptions: encode the Perl internal format string to the mime header one.
#    Arguments: OBJ($self) STR($pif_str)
# Side Effects: none
# Return Value: STR
sub mime_header_encode
{
    my ($self, $pif_str) = @_;
    my $m;

    # XXX how we specify the encoding ?
    if (1) { # base64 by default
        $m = encode("MIME-Header", $pif_str, Encode::FB_WARN);
    }
    else {
        $m = encode("MIME-Q", $pif_str, Encode::FB_WARN);
    }
    return $m;
}

# Descriptions: decode mime header format string to the Perl internal one.
#    Arguments: OBJ($self) STR($pef_str)
# Side Effects: none
# Return Value: STR(perl internal UTF8 format)
sub mime_header_decode
{
    my ($self, $pef_str) = @_;

    decode("MIME-Header", $pef_str);
}


# Descriptions: decode mime header format string and return it as
#               printable format not the Perl internal one.
#               $code is the charset to emit. it defaults to
#               $default_external_charset if not given.
#    Arguments: OBJ($self) STR($pef_str) STR($code)
# Side Effects: none
# Return Value: STR
sub mime_header_decode_as_octets
{
    my ($self, $pef_str, $code) = @_;

    # XXX-TODO: see the note on $default_external_charset above.
    $code ||= $default_external_charset;
    encode($code, decode("MIME-Header", $pef_str));
}


=head2 convert_from_internal_to_external_form($pif_str)

convert the given Perl internal form to the external printable one.

=cut


# Descriptions: convert the given Perl internal form
#               to the external printable one.
#               $code is the charset to emit. it defaults to
#               $default_external_charset if not given.
#    Arguments: OBJ($self) STR($pif_str) STR($code)
# Side Effects: none
# Return Value: STR
sub convert_from_internal_to_external_form
{
    my ($self, $pif_str, $code) = @_;

    # XXX-TODO: the default should become UTF-8, see the note on
    # XXX-TODO: $default_external_charset above.
    $code ||= $default_external_charset;
    utf8::is_utf8($pif_str) ? encode($code, $pif_str) : $pif_str;
}


=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2018 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

FML::Message::Encode first appeared in fml8 mailing list driver package.
See C<http://www.fml.org/> for more details.

=cut


1;
