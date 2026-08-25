#-*- perl -*-
#
# Copyright (C) 2003,2004 Ken'ichi Fukamachi
#
# $FML: Charset.pm,v 1.4 2004/02/26 12:59:07 fukachan Exp $
#

package FML::Message::Charset;
use strict;

=head1 NAME

FML::Message::Charset - charset map.

=head1 SYNOPSIS

    use FML::Message::Charset;
    my $mh = new FML::Message::Charset;

=head1 DESCRIPTION

=head1 METHODS

=cut


1;

my %language_code =  (
		      "aa"  => "Afar",
		      "ab"  => "Abkhazian",
		      "af"  => "Afrikaans",
		      "am"  => "Amharic",
		      "ar"  => "Arabic",
		      "as"  => "Assamese",
		      "ay"  => "Aymara",
		      "az"  => "Azerbaijani",
		      "ba"  => "Bashkir",
		      "be"  => "Belarusian",
		      "bg"  => "Bulgarian",
		      "bh"  => "Bihari",
		      "bi"  => "Bislama",
		      "bn"  => "Bengali",
		      "bnt" => "Bantu",
		      "bo"  => "Tibetan",
		      "br"  => "Breton",
		      "ca"  => "Catalan",
		      "co"  => "Corsican",
		      "cs"  => "Czech",
		      "cy"  => "Welsh",
		      "da"  => "Danish",
		      "de"  => "German",
		      "div" => "Maldivian",
		      "dz"  => "Bhutani",
		      "el"  => "Greek",
		      "en"  => "English",
		      "eo"  => "Esperanto",
		      "es"  => "Spanish",
		      "et"  => "Estonian",
		      "eu"  => "Basque",
		      "fa"  => "Farsi/Persian",
		      "fi"  => "Finnish",
		      "fj"  => "Fijian",
		      "fo"  => "Faroese",
		      "fr"  => "French",
		      "fy"  => "Frisian",
		      "ga"  => "Irish",
		      "gd"  => "Scottish",
		      "gl"  => "Galician",
		      "gn"  => "Guarani",
		      "gu"  => "Gujarati",
		      "ha"  => "Hausa",
		      "he"  => "Hebrew",
		      "hi"  => "Hindi",
		      "hr"  => "Croatian",
		      "hu"  => "Hungarian",
		      "hy"  => "Armenian",
		      "id"  => "Indonesian",
		      "ik"  => "Inupiaq",
		      "is"  => "Icelandic",
		      "it"  => "Italian",
		      "ja"  => "Japanese",
		      "jv"  => "Javanese",
		      "ka"  => "Georgian",
		      "kk"  => "Kazakh",
		      "kl"  => "Greenlandic",
		      "km"  => "Cambodian/Khmer",
		      "kn"  => "Kannada",
		      "ko"  => "Korean",
		      "ks"  => "Kashmiri",
		      "ku"  => "Kurdish",
		      "ky"  => "Kirghiz",
		      "ln"  => "Lingala",
		      "lo"  => "Laothian",
		      "lt"  => "Lithuanian",
		      "lv"  => "Latvian",
		      "mg"  => "Malagasy",
		      "mi"  => "Maori",
		      "mk"  => "Macedonian",
		      "ml"  => "Malayalam",
		      "mn"  => "Mongolian",
		      "mo"  => "Moldavian",
		      "mr"  => "Marathi",
		      "ms"  => "Malay",
		      "mt"  => "Maltese",
		      "my"  => "Burmese",
		      "na"  => "Nauru",
		      "ne"  => "Nepali",
		      "nl"  => "Dutch",
		      "no"  => "Norwegian",
		      "oc"  => "Occitan",
		      "om"  => "Oromo",
		      "or"  => "Oriya",
		      "pa"  => "Punjabi",
		      "pap" => "Papiamento",
		      "pl"  => "Polish",
		      "ps"  => "Pushto",
		      "pt"  => "Portuguese",
		      "qu"  => "Quechua",
		      "rm"  => "Raeto-Romance",
		      "rn"  => "Kurundi",
		      "ro"  => "Romanian",
		      "ru"  => "Russian",
		      "rw"  => "Kinyarwanda",
		      "sa"  => "Sanskrit",
		      "sd"  => "Sindhi",
		      "sg"  => "Sangho",
		      "sh"  => "Serbo-Croatian",
		      "si"  => "Singhalese",
		      "sk"  => "Slovak",
		      "sl"  => "Slovenian",
		      "sm"  => "Samoan",
		      "sn"  => "Shona",
		      "so"  => "Somali",
		      "sq"  => "Albanian",
		      "sr"  => "Serbian",
		      "ss"  => "Siswati",
		      "st"  => "Sesotho",
		      "su"  => "Sundanese",
		      "sv"  => "Swedish",
		      "sw"  => "Swahili",
		      "ta"  => "Tamil",
		      "te"  => "Telugu",
		      "tg"  => "Tajik",
		      "th"  => "Thai",
		      "ti"  => "Tigrinya",
		      "tk"  => "Turkmen",
		      "tl"  => "Tagalog",
		      "tn"  => "Setswana",
		      "to"  => "Tonga",
		      "tr"  => "Turkish",
		      "ts"  => "Tsonga",
		      "tt"  => "Tatar",
		      "tw"  => "Twi",
		      "uk"  => "Ukrainian",
		      "ur"  => "Urdu",
		      "uz"  => "Uzbek",
		      "vi"  => "Vietnamese",
		      "vo"  => "Volapuk",
		      "wo"  => "Wolof",
		      "xh"  => "Xhosa",
		      "yi"  => "Yiddish",
		      "yo"  => "Yoruba",
		      "zh"  => "Chinese",
		      "zu"  => "Zulu",
		      );


my %internal_charset_map = (
			    'ja'       => 'euc-jp',
			    'japanese' => 'euc-jp',

			    'en'       => 'us-ascii',
			    'english'  => 'us-ascii',
			    );


my %message_charset_map  = (
			    'ja'       => 'iso-2022-jp',
			    'japanese' => 'iso-2022-jp',

			    'en'       => 'us-ascii',
			    'english'  => 'us-ascii',
			    );

# XXX the keys here must include the names that actually turn up in
# XXX Content-Type: and in =?...?= encoded words, not only the short
# XXX internal ones.  "Shift_JIS" is the registered name and is what
# XXX mail says; "sjis" is our own shorthand.  A name missing here
# XXX resolves to no language at all, so the message gets no language
# XXX hint and falls back to the default charset.
#
# XXX utf-8 is deliberately absent: it says nothing about the language,
# XXX and mapping it to "ja" would push non-Japanese mail through the
# XXX euc-jp conversion.  Representing it needs the charset model to
# XXX stop being language-keyed.
my %rev_message_charset_map  = (
				'euc-jp'        => 'ja',
				'euc_jp'        => 'ja',
				'x-euc-jp'      => 'ja',
				'euc'           => 'ja',

				'shift_jis'     => 'ja',
				'shift-jis'     => 'ja',
				'x-sjis'        => 'ja',
				'cp932'         => 'ja',
				'windows-31j'   => 'ja',
				'sjis-jp'       => 'ja',
				'sjis'          => 'ja',

				'iso-2022-jp'   => 'ja',
				'iso-2022-jp-1' => 'ja',
				'iso-2022-jp-2' => 'ja',
				'iso-2022-jp-3' => 'ja',
				'csiso2022jp'   => 'ja',
				'jis-jp'        => 'ja',
				'jis'           => 'ja',

				'us-ascii'      => 'en',
				'ascii'         => 'en',
				);


# Descriptions: constructor.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: OBJ
sub new
{
    my ($self) = @_;
    my ($type) = ref($self) || $self;
    my $me     = {};
    return bless $me, $type;
}


# Descriptions: return default charset for internal usage.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: OBJ
sub internal_default_charset
{
    my ($self) = @_;
    return 'us-ascii';
}


# Descriptions: return default charset for message handling.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: OBJ
sub message_default_charset
{
    my ($self) = @_;
    return 'us-ascii';
}


# Descriptions: convert charset info: e.g. japanese => euc-jp.
#    Arguments: OBJ($self) STR($language)
# Side Effects: none
# Return Value: STR
sub language_to_internal_charset
{
    my ($self, $language) = @_;

    # XXX $language may be undef when the caller has no hint at all
    # XXX (e.g. the CGI path has no "language_hint" in the PCB);
    # XXX lc(undef) warns under -w.  See fml8 issue #8.
    return '' unless defined $language;

    return( $internal_charset_map{ lc($language) } || '' );
}


# Descriptions: convert charset info: e.g. ja or japanese => iso-2022-jp.
#    Arguments: OBJ($self) STR($language)
# Side Effects: none
# Return Value: STR
sub language_to_message_charset
{
    my ($self, $language) = @_;

    # XXX $language may be undef when the caller has no hint at all
    # XXX (e.g. the CGI path has no "language_hint" in the PCB);
    # XXX lc(undef) warns under -w.  See fml8 issue #8.
    return '' unless defined $language;

    return( $message_charset_map{ lc($language) } || '' );
}


# Descriptions: charset to language: e.g. iso-2022-jp => ja.
#    Arguments: OBJ($self) STR($charset)
# Side Effects: none
# Return Value: STR
sub message_charset_to_language
{
    my ($self, $charset) = @_;

    # XXX $charset may be undef when the caller has no hint at all
    # XXX (e.g. the CGI path has no "language_hint" in the PCB);
    # XXX lc(undef) warns under -w.  See fml8 issue #8.
    return '' unless defined $charset;

    return( $rev_message_charset_map{ lc($charset) } || '' );
}


=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2003,2004 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut


1;
