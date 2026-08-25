#
# HTML::EntitiesLite -- escape the characters HTML reserves, and only those.
#
# This replaces a cut of HTML::Entities taken from HTML-Parser-3.69 by
# fukachan@fml.org, which fml8 carried because HTML::Entities itself is
# XS and cannot be bundled.  Nothing of that copy is left, so nothing of
# its copyright applies to what is here.
#
# The reason for rewriting rather than trimming is in the default.  The
# original encode_entities() escaped "control chars, high bit chars" as
# well as the five HTML ones, which is right for a character string and
# wrong for the octets fml8 handles.  Given EUC-JP, it read each byte as
# Latin-1 and produced an entity for it, so
#
#     日本語  (c6fc cbdc b8ec)
#
# came back as &AElig;&uuml;&Euml;&Uuml;&cedil;&igrave;, and every
# Japanese article in an HTML archive was turned into that.  Here the
# default is the five characters that actually mean something to a
# parser; anything with the high bit set is left as the byte it was.
#

package HTML::EntitiesLite;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION %char2entity);

require Exporter;
@ISA       = qw(Exporter);
@EXPORT    = qw(encode_entities);
@EXPORT_OK = qw(%char2entity);

$VERSION = '1.00';

%char2entity = (
		'&'  => '&amp;',
		'<'  => '&lt;',
		'>'  => '&gt;',
		'"'  => '&quot;',
		"'"  => '&#39;',
		);


# Descriptions: return $str with HTML's own characters escaped.
#               With $chars, escape those characters instead.
#    Arguments: STR($str) STR($chars)
# Side Effects: modifies $str in place when called in void context.
# Return Value: STR
sub encode_entities
{
    return undef unless defined $_[0];

    my $ref;
    if (defined wantarray) {
	my $x = $_[0];
	$ref  = \$x;		# copy
    }
    else {
	$ref  = \$_[0];		# modify in place
    }

    if (defined $_[1] && length $_[1]) {
	my $class = join('', map { quotemeta } split(//, $_[1]));
	$$ref =~ s/([$class])/$char2entity{$1} || sprintf("&#x%X;", ord($1))/ge;
    }
    else {
	$$ref =~ s/([&<>"'])/$char2entity{$1}/g;
    }

    return $$ref;
}


1;
