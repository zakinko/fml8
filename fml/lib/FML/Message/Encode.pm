#-*- perl -*-
#
#  Copyright (C) 2002,2003,2004,2005,2011 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#
# $FML: Encode.pm,v 1.24 2011/08/25 00:39:58 fukachan Exp $
#

package FML::Message::Encode;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;

# XXX these were MIME::Base64::Perl and MIME::QuotedPrint::Perl, the
# XXX pure perl fallbacks for hosts that could not build the XS ones.
# XXX MIME::Base64 has been in the core since 5.7.3 and brings
# XXX MIME::QuotedPrint with it, so the fallback is what is unusual now,
# XXX and it is the slower of the two by a wide margin on a busy list.
# XXX
# XXX They were also loaded through eval q{ use ... } at each call site,
# XXX which was deferring a decision there is no longer anything to
# XXX decide; loading them here means a missing one is a startup error
# XXX rather than a header that silently stays encoded.
use MIME::Base64;
use MIME::QuotedPrint;

=head1 NAME

FML::Message::Encode - encode/decode/charset conversion routines.

=head1 SYNOPSIS

    use FML::Message::Encode;
    my $code = FML::Message::Encode->detect_code($str);

It is not recommended but if you use old style, import required function:

    use FML::Message::Encode qw(STR2EUC);
    my $euc_string = STR2EUC($string);


=head1 DESCRIPTION

=head1 METHODS

=head2 new()

constructor.

=cut


# Descriptions: constructor.
#    Arguments: OBJ($self) HASH_REF($args)
# Side Effects: load Encode or Jcode.
# Return Value: OBJ
sub new
{
    my ($self, $args) = @_;
    my ($type) = ref($self) || $self;
    my $me     = {};

    # XXX this used to choose between Encode and Jcode by perl version,
    # XXX with the Encode branch disabled by a literal 0 so that Jcode
    # XXX was always the answer -- and the Jcode branch was guarded by
    # XXX $] <= 5.006001, so on any perl this century neither ran and
    # XXX the load was left to the "use Jcode" further down.  Encode has
    # XXX been in the core since 5.7.3; there is nothing left to choose.
    eval q{ use Encode; use Encode::Guess; };
    croak("cannot load Encode") if $@;

    # default language
    # XXX 'japanese' includes both Japanese and English.
    $me->{ _language } = 'japanese';

    return bless $me, $type;
}


=head2 detect_code($str)

speculate the code of $str string. $str is checked by C<Encode::Guess>,
which is in the perl core. It returns one of C<jis>, C<sjis>, C<euc>,
C<utf8>, C<ascii>, or C<unknown> when it cannot decide.

Since C<Encode::Guess> cannot tell euc-jp from shiftjis unless it is
told which encodings to consider, the candidates are fixed to euc-jp,
shiftjis and 7bit-jis here.

This used to call C<Unicode::Japanese::getcode()>, which named more
encodings -- UTF-16 and the mobile phone Shift_JIS variants among them
-- but could not decline: shown French or Korean written in UTF-8 it
answered C<euc> and C<sjis> respectively. Nothing here asks about the
encodings that were lost, and a wrong answer is what leads something
downstream to convert a message that was never Japanese.

C<CAUTION>: we handle only Japanese and English.

=cut


# Descriptions: speculate code of $str string.
#    Arguments: OBJ($self) STR($str)
# Side Effects: none
# Return Value: STR
sub detect_code
{
    my ($self, $str) = @_;
    my $lang = $self->{ _language };

    # XXX Japanese includes English.
    if ($lang eq 'japanese' || $lang eq 'english') {
	# XXX this used to call Unicode::Japanese::getcode(), which is
	# XXX the only reason this module needed anything outside the
	# XXX perl core.  Encode::Guess agrees with it on every Japanese
	# XXX encoding -- euc, sjis, jis, utf8 and ascii all come back
	# XXX the same -- and is better on everything else.
	# XXX
	# XXX getcode() answered "euc" for French written in UTF-8 and
	# XXX "sjis" for Korean, because it has no way to say it does not
	# XXX know: it always names a Japanese encoding.  Acting on that
	# XXX and "converting" the message destroys it.  Encode::Guess
	# XXX reads the French as undecidable and the Korean correctly as
	# XXX utf8, and says "unknown" when it cannot tell.
	# XXX
	# XXX What is lost is the ability to name UTF-16 and the mobile
	# XXX phone Shift_JIS variants; nothing here asks about either.
	return $self->_guess_code($str);
    }
    else {
	carp("FML::Message::Encode: unknown language");
	return 'unknown';
    }
}


# XXX Encode::Guess has to be told which encodings to consider: it
# XXX cannot tell euc-jp from shiftjis on its own, since a string of
# XXX either is a valid string of the other.  utf8 and ascii it decides
# XXX without being asked.
my @guess_suspects = qw(euc-jp shiftjis 7bit-jis);

# XXX Encode's names for them against the ones this module has always
# XXX returned, and which FML::Message::Charset and the callers below
# XXX still expect.
my %guess_name_map = (
		      'utf8'     => 'utf8',
		      'euc-jp'   => 'euc',
		      'shiftjis' => 'sjis',
		      '7bit-jis' => 'jis',
		      'ascii'    => 'ascii',
		      );

# XXX and the same table the other way, for handing a name to Encode.
my %encode_name_map = (
		       'utf8' => 'utf8',
		       'euc'  => 'euc-jp',
		       'sjis' => 'shiftjis',
		       'jis'  => '7bit-jis',
		       'ascii'=> 'ascii',
		       );


# Descriptions: speculate the encoding of $str, in the names this
#               module has always used.
#    Arguments: OBJ($self) STR($str)
# Side Effects: none
# Return Value: STR
sub _guess_code
{
    my ($self, $str) = @_;

    use Encode::Guess;
    my $guess = Encode::Guess->guess($str, @guess_suspects);

    # guess() hands back an error string, not an object, when it cannot
    # decide.  "unknown" is what the rest of fml8 checks for.
    return 'unknown' unless ref $guess;

    return( $guess_name_map{ $guess->name } || 'unknown' );
}


# Unicode::Japanese
#           'jis', 'sjis', 'euc', 'utf8', 'ucs2', 'ucs4', 'utf16',
#           'utf16-ge', 'utf16-le', 'utf32', 'utf32-ge',
#           'utf32-le', 'ascii', 'binary', 'sjis-imode', 'sjis-
#           doti', 'sjis-jsky'.
#
# Jcode
#            ascii   Ascii (Contains no Japanese Code)
#            binary  Binary (Not Text File)
#            euc     EUC-JP
#            sjis    SHIFT_JIS
#            jis     JIS (ISO-2022-JP)
#            ucs2    UCS2 (Raw Unicode)
#            utf8    UTF8


=head2 convert($str, $out_code, $in_code)

convert $str to $out_code code.
$in_code is used as a hint.

=head2 convert_str_ref($str_ref, $out_code, $in_code)

convert string reference $str_str to $out_code code.
$in_code is used as a hint.

=cut


# Descriptions: convert $str to $out_code code.
#    Arguments: OBJ($self) STR($str) STR($out_code) STR($in_code)
# Side Effects: none
# Return Value: STR
sub convert
{
    my ($self, $str, $out_code, $in_code) = @_;
    my $status = $self->convert_str_ref(\$str, $out_code, $in_code);
    return $str;
}


# Descriptions: convert string reference $str_str to $out_code code.
#    Arguments: OBJ($self) STR_REF($str_ref) STR($out_code) STR($in_code)
# Side Effects: croak() if input data is invalid.
# Return Value: NUM(1/0)
sub convert_str_ref
{
    my ($self, $str_ref, $out_code, $in_code) = @_;
    my $lang = $self->{ _language };

    unless (ref($str_ref) eq 'SCALAR') {
	croak("convert_str_ref: invalid input data");
    }

    # XXX Japanese includes English.
    if ($lang eq 'japanese' || $lang eq 'english') {
	# 1. if the encoding for the given $str_ref is unknown, return ASAP.
	unless (defined $in_code) {
	    $in_code = $self->detect_code($$str_ref);
	    if ($in_code eq 'unknown') {
		return 0;
	    }
	}
	else {
	    # print "1 ok\n";
	}

	# 2. try conversion ! (converted to 'euc' by default).
	if ($in_code) {
	    return $self->_jp_str_ref($str_ref, $out_code, $in_code);
	}
    }
    else {
	croak("FML::Message::Encode: unknown language");
    }

    return 0;
}


# Descriptions: convert japanese string to $out_code.
#               XXX $in_code must be determined here !
#    Arguments: OBJ($self) STR_REF($str_ref) STR($out_code) STR($in_code)
# Side Effects: none
# Return Value: NUM(1/0)
sub _jp_str_ref
{
    my ($self, $str_ref, $out_code, $in_code) = @_;

    if ($out_code =~ /^(jis|sjis|euc)$|^(jis|sjis|euc)[-_]jp$/i) {
	my $code = $1 || $2;
	$code    =~ tr/A-Z/a-z/;

	return $self->_recode($str_ref, $code, $in_code);
    }
    elsif ($out_code =~ /^(iso2022jp|iso-2022-jp)$/i) {
	return $self->_recode($str_ref, 'jis', $in_code);
    }

    return 0;
}


# Descriptions: convert $$str_ref from $in_code to $out_code in place.
#               $in_code is a hint; when it is missing or not one we
#               know, the string is examined instead.
#
#               XXX this replaces Jcode::convert(), which was the last
#               XXX reason this module needed anything outside the perl
#               XXX core.  Encode is core from 5.7.3 and agrees with
#               XXX Jcode byte for byte on every conversion between
#               XXX euc-jp, Shift_JIS and ISO-2022-JP; that is asserted
#               XXX against fml4's own jcode.pl in t/30.
#    Arguments: OBJ($self) STR_REF($str_ref) STR($out_code) STR($in_code)
# Side Effects: update $$str_ref.
# Return Value: NUM(1 or 0)
sub _recode
{
    my ($self, $str_ref, $out_code, $in_code) = @_;

    my $to = $encode_name_map{ $out_code } || return 0;

    my $from = '';
    $from = $encode_name_map{ lc($in_code) } if $in_code;
    $from ||= $encode_name_map{ $self->_guess_code($$str_ref) } || '';

    # XXX Jcode guessed too, and guessed a Japanese encoding whatever it
    # XXX was looking at.  Leaving the string alone is the safer answer:
    # XXX re-encoding from the wrong charset is how a French or Korean
    # XXX message gets destroyed, and there is nothing to gain by it.
    return 0 unless $from;

    # ASCII survives every one of these unchanged, so there is nothing
    # to do and nothing to get wrong.
    return 1 if $from eq 'ascii';

    use Encode;

    # XXX decode() with a CHECK argument consumes what it converted out
    # XXX of the buffer it was handed, so it must never be given the
    # XXX caller's string: a conversion that then turns out to be
    # XXX impossible would leave the caller holding an empty one.
    my $octets  = $$str_ref;
    my $decoded = eval { Encode::decode($from, $octets, Encode::FB_CROAK()) };
    return 0 if $@;

    # XXX and refuse a conversion the target charset cannot represent.
    # XXX Korean or Russian read correctly as UTF-8 and then written as
    # XXX euc-jp comes out as a row of question marks, which is worse
    # XXX than leaving it: the reader with the right mail client could
    # XXX have read the original, and nobody can read "???".  Jcode
    # XXX substituted silently here.
    my $encoded = eval { Encode::encode($to, $decoded, Encode::FB_CROAK()) };
    return 0 if $@;

    $$str_ref = $encoded;
    return 1;
}


=head2 run_in_code($proc, $s, $args, $out_code, $in_code)

run $proc($s) under $out_code environment.
So, execute $proc like this.

    my $obj         = new FML::Message::Encode;
    my $conv_status = $obj->convert_str_ref($s, $out_code, $in_code);

    &$proc($s, $args);

It means run $proc() after $s is converted to $out_code code.

=cut


# Descriptions: run $proc($s) under $out_code environment.
#               It means run $proc() after $s is converted to $out_code code.
#    Arguments: OBJ($self) CODE_REF($proc) STR($s) HASH_REF($args)
#               STR($out_code) STR($in_code)
# Side Effects: none
# Return Value: none
sub run_in_code
{
    my ($self, $proc, $s, $args, $out_code, $in_code) = @_;
    my $proc_status = undef;

    my $obj         = new FML::Message::Encode;
    my $conv_status = $obj->convert_str_ref(\$s, $out_code, $in_code);

    # XXX-TODO: validate $proc name regexp.
    eval q{
	$proc_status = &$proc($s, $args);
    };

    # XXX-TODO: correct ?
    if ($conv_status && $out_code) {
	$obj->convert_str_ref($s, $out_code, $in_code);
    }

    return wantarray ? ($conv_status, $proc_status): $conv_status;
}


=head1 UTILITIES

=head2 is_iso2022jp_string($buf)

$buf looks like Japanese or not ?

=cut


# Descriptions: $buf looks like Japanese or not ?
#    Arguments: OBJ($self) STR($buf)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub is_iso2022jp_string
{
    my ($self, $buf) = @_;
    return (not _look_not_iso2022jp_string($buf));
}


# Descriptions: $buf looks like Japanese or not ?
#               based on fml-support: 07020, 07029
#                  Koji Sudo <koji@cherry.or.jp>
#                  Takahiro Kambe <taca@sky.yamashina.kyoto.jp>
#               check the given buffer has unusual Japanese (not ISO-2022-JP)
#    Arguments: STR($buf)
#      History: imported fml 4.0 functions.
# Side Effects: none
# Return Value: NUM(1 or 0)
sub _look_not_iso2022jp_string
{
    my ($buf) = @_;

    # trivial check;
    return 0 unless defined $buf;
    return 0 unless $buf;

    # check 8 bit on
    if ($buf =~ /[\x80-\xFF]/){
        return 1;
    }

    # check SI/SO
    if ($buf =~ /[\016\017]/) {
        return 1;
    }

    # HANKAKU KANA
    if ($buf =~ /\033\(I/) {
        return 1;
    }

    # MSB flag or other control sequences
    if ($buf =~ /[\001-\007\013\015\020-\032\034-\037\177-\377]/) {
        return 1;
    }

    0; # O.K.
}


=head1 BACKWARD COMPATIBILITY

=head2 STR2EUC($str)

convert $str to japanese EUC code.

=head2 STR2JIS($str)

convert $str to japanese JIS code.

=head2 STR2SJIS($str)

convert $str to japanese SJIS code.

=cut


# Descriptions: convert $str to euc.
#    Arguments: STR($str)
# Side Effects: none
# Return Value: STR
sub STR2EUC
{
    my ($str) = @_;
    my $obj = new FML::Message::Encode;
    $obj->convert( $str, 'euc-jp' );
}


# Descriptions: convert $str to sjis.
#    Arguments: STR($str)
# Side Effects: none
# Return Value: STR
sub STR2SJIS
{
    my ($str) = @_;
    my $obj = new FML::Message::Encode;
    $obj->convert( $str, 'sjis-jp' );
}


# Descriptions: convert $str to jis.
#    Arguments: STR($str)
# Side Effects: none
# Return Value: STR
sub STR2JIS
{
    my ($str) = @_;
    my $obj = new FML::Message::Encode;
    $obj->convert( $str, 'jis-jp' );
}


=head1 MIME ENCODE/DECODE

=cut


# Descriptions: decode MIME base64 encoded-string.
#    Arguments: OBJ($self) STR($str) STR($out_code) STR($in_code)
# Side Effects: croak() if language is unknown.
# Return Value: STR
sub decode_base64_string
{
    my ($self, $str, $out_code, $in_code) = @_;
    my $lang    = $self->{ _language };
    my $str_out = undef;

    if ($lang eq 'japanese') {
	$str_out = eval { decode_base64($str) };
	return $str if $@ || ! defined $str_out;

	# XXX-TODO: use FML::Message::Charset ?
	$in_code   = $self->detect_code($str_out);
	$out_code ||= 'euc-jp'; # euc-jp by default. XXX was |= (string bit-or).
    }
    else {
	croak("FML::Message::Encode: unknown language");
    }

    return $self->convert($str_out, $out_code, $in_code);
}


# Descriptions: decode MIME quoted-printable encoded-string.
#    Arguments: OBJ($self) STR($str) STR($out_code) STR($in_code)
# Side Effects: croak() if language is unknown.
# Return Value: STR
sub decode_qp_string
{
    my ($self, $str, $out_code, $in_code) = @_;
    my $lang    = $self->{ _language };
    my $str_out = undef;

    if ($lang eq 'japanese') {
	$str_out = eval { decode_qp($str) };
	return $str if $@ || ! defined $str_out;

	# XXX-TODO: use FML::Message::Charset ?
	$in_code   = $self->detect_code($str_out);
	$out_code ||= 'euc-jp'; # euc-jp by default. XXX was |= (string bit-or).
    }
    else {
	croak("FML::Message::Encode: unknown language");
    }

    return $self->convert($str_out, $out_code, $in_code);
}


# Descriptions: decode mime encoded string.
#    Arguments: OBJ($self) STR($buf)
# Side Effects: none
# Return Value: STR
sub raw_decode_base64
{
    my ($self, $buf) = @_;
    my $rbuf = '';

    $rbuf = eval { decode_base64($buf) };

    return( $rbuf || $buf );
}


# Descriptions: decode mime encoded string.
#    Arguments: OBJ($self) STR($buf)
# Side Effects: none
# Return Value: STR
sub raw_decode_qp
{
    my ($self, $buf) = @_;
    my $rbuf = '';

    $rbuf = eval { decode_qp($buf) };

    return( $rbuf || $buf );
}


=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2002,2003,2004,2005,2011 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

FML::Message::Encode first appeared in fml8 mailing list driver package.
See C<http://www.fml.org/> for more details.

=cut


1;
