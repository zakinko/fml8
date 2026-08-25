#-*- perl -*-
#
#  Copyright (C) 2026 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#

package FML::CGI::Compat;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK);
use Carp;
use Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(param header start_html end_html
	     start_form end_form
	     textfield hidden submit reset popup_menu scrolling_list
	     table Tr td
	     escapeHTML url);

=head1 NAME

FML::CGI::Compat - the part of CGI.pm fml8 uses.

=head1 SYNOPSIS

    use FML::CGI::Compat;

    print header(-type => "text/html; charset=euc-jp");
    print start_form(-action => $action);
    print textfield(-name => 'ml_name', -size => 32);
    print submit(-name => 'ok');
    print end_form();

=head1 DESCRIPTION

CGI.pm left the perl core at 5.021 and fml8 has never bundled it, so
"use CGI" is a module an installation has to be told to add before the
web interface runs at all.  fml8 asks it for twelve functions and
fourteen of their options, all of them in the -name => value form, and
that is small enough to keep here instead.

The HTML-generating half of CGI.pm is also the half its own author
marked as no longer recommended, so this is not a copy of something
being maintained elsewhere.

Reading the request is the other half, and that is CGI as a protocol
rather than as a module: QUERY_STRING and the request body, parsed the
way RFC 3875 describes.

=head1 METHODS

=cut


my %param       = ();
my $param_read  = 0;
my $form_open   = 0;

# The upper bound on a request body read into memory.  A form on an
# fml8 admin page is a few hundred bytes; anything far past that is a
# mistake or an attempt at one.
my $POST_MAX = 1024 * 1024;


=head2 param([$key])

the value of a form field, or the list of field names with no argument.

=cut


# Descriptions: the value of a form field, or every field name.
#    Arguments: STR($key)
# Side Effects: reads QUERY_STRING and STDIN once.
# Return Value: STR or ARRAY
sub param
{
    my ($key) = @_;

    _read_param() unless $param_read;

    return sort keys %param unless defined $key;
    return undef            unless exists $param{ $key };

    my $v = $param{ $key };

    return wantarray ? @$v : $v->[0];
}


# Descriptions: read the request into %param.
#    Arguments: none
# Side Effects: update %param. reads STDIN.
# Return Value: none
sub _read_param
{
    $param_read = 1;

    my $buf = $ENV{ QUERY_STRING } || '';

    my $method = $ENV{ REQUEST_METHOD } || '';
    if ($method eq 'POST') {
	my $len = $ENV{ CONTENT_LENGTH } || 0;

	# XXX An unread body would be a truncated form; a body larger
	# XXX than any fml8 page produces is not one worth reading.
	croak("FML::CGI::Compat: request body too large") if $len > $POST_MAX;

	if ($len > 0) {
	    my $body = '';
	    my $got  = read(STDIN, $body, $len);
	    croak("FML::CGI::Compat: short read on request body")
		unless defined($got) && $got == $len;

	    $buf = length($buf) ? "$buf&$body" : $body;
	}
    }

    for my $pair (split(/[&;]/, $buf)) {
	next unless length $pair;
	my ($k, $v) = split(/=/, $pair, 2);
	next unless defined $k;
	$v = '' unless defined $v;

	push @{ $param{ _unescape($k) } }, _unescape($v);
    }
}


# Descriptions: undo application/x-www-form-urlencoded.
#    Arguments: STR($s)
# Side Effects: none
# Return Value: STR
sub _unescape
{
    my ($s) = @_;

    $s =~ tr/+/ /;
    $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;

    return $s;
}


# Descriptions: read a (-key => value) list into a hash, without the -.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: HASH_REF
sub _opt
{
    my (@av) = @_;
    my %o    = ();

    while (@av) {
	my $k = shift @av;

	# XXX A caller may pass a bare list where CGI.pm would have read
	# XXX it as the default value; hidden(-name => 'x', [ '' ]) is
	# XXX in the tree.  Keep that shape working.
	unless (defined($k) && !ref($k) && $k =~ /^-/) {
	    $o{ default } = $k;
	    next;
	}

	$k =~ s/^-//;
	$o{ lc($k) } = shift @av;
    }

    return \%o;
}


=head2 escapeHTML($s)

escape the five characters that mean something to a parser.

=cut


# Descriptions: escape what HTML reserves.
#    Arguments: STR($s)
# Side Effects: none
# Return Value: STR
sub escapeHTML
{
    my ($s) = @_;

    return '' unless defined $s;

    # XXX Bytes above 127 are left alone.  fml8 hands this euc-jp, and
    # XXX escaping octets as if they were characters is what turned
    # XXX every Japanese article into Latin-1 entity names once already.
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;

    return $s;
}


# Descriptions: the value of an option as a single string.
#    Arguments: HASH_REF($o) STR($key)
# Side Effects: none
# Return Value: STR
sub _first
{
    my ($o, $key) = @_;
    my $v = $o->{ $key };

    return '' unless defined $v;
    return ref($v) eq 'ARRAY' ? (defined $v->[0] ? $v->[0] : '') : $v;
}


=head2 header(-type => $type, ...)

the CGI response header.

=cut


# Descriptions: the CGI response header.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub header
{
    my $o    = _opt(@_);
    my $type = $o->{ type } || 'text/html';

    # XXX -charset is given beside a -type that already carries the
    # XXX charset in every call in the tree.  Adding it twice would be
    # XXX a header no browser has to agree about, so it is added only
    # XXX when -type does not say.
    if ($o->{ charset } && $type !~ /charset=/i) {
	$type .= sprintf("; charset=%s", $o->{ charset });
    }

    my $buf = sprintf("Content-Type: %s\r\n", $type);
    $buf   .= sprintf("Window-Target: %s\r\n", $o->{ target })
	if $o->{ target };

    return $buf . "\r\n";
}


=head2 start_html(-title => $title, ...)

open an HTML document.

=head2 end_html()

close it.

=cut


# Descriptions: open an HTML document.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub start_html
{
    my $o     = _opt(@_);
    my $title = escapeHTML($o->{ title } || '');
    my $buf   = '';

    # XXX HTML 4.01 Transitional and a BGCOLOR attribute are what
    # XXX CGI.pm wrote and what fml8 has been serving.  A page that says
    # XXX <!DOCTYPE html> is parsed in standards mode instead of quirks
    # XXX mode, and the viewport line is what stops a phone rendering
    # XXX the page at 980px and scaling it down to unreadable.
    $buf .= "<!DOCTYPE html>\n";
    $buf .= "<html";
    $buf .= sprintf(" lang=\"%s\"", escapeHTML($o->{ lang })) if $o->{ lang };
    $buf .= ">\n<head>\n";
    $buf .= sprintf("<meta charset=\"%s\">\n",
		    escapeHTML($o->{ charset })) if $o->{ charset };
    $buf .= "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
    $buf .= sprintf("<title>%s</title>\n", $title);
    $buf .= "</head>\n";
    $buf .= "<body";
    $buf .= sprintf(" style=\"background-color:%s\"",
		    escapeHTML($o->{ bgcolor })) if $o->{ bgcolor };
    $buf .= ">\n";

    return $buf;
}


# Descriptions: close an HTML document.
#    Arguments: none
# Side Effects: none
# Return Value: STR
sub end_html
{
    return "</body>\n</html>\n";
}


=head2 start_form(-action => $action, ...)

open a form.

=head2 end_form()

close it.

=cut


# Descriptions: open a form.
#    Arguments: ARRAY(@av)
# Side Effects: update $form_open.
# Return Value: STR
sub start_form
{
    my $o   = _opt(@_);
    my $buf = "<form method=\"post\"";

    $buf .= sprintf(" action=\"%s\"", escapeHTML($o->{ action }))
	if $o->{ action };
    $buf .= sprintf(" target=\"%s\"", escapeHTML($o->{ target }))
	if $o->{ target };
    $buf .= " enctype=\"application/x-www-form-urlencoded\">\n";

    $form_open = 1;

    return $buf;
}


# Descriptions: close a form.
#    Arguments: none
# Side Effects: update $form_open.
# Return Value: STR
sub end_form
{
    $form_open = 0;

    return "</form>\n";
}


=head2 textfield(-name => $name, ...)

=head2 hidden(-name => $name, ...)

=head2 submit(-name => $name)

=cut


# Descriptions: a text input.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub textfield
{
    my $o   = _opt(@_);
    my $buf = sprintf("<input type=\"text\" name=\"%s\"",
		      escapeHTML($o->{ name }));

    $buf .= sprintf(" value=\"%s\"", escapeHTML(_first($o, 'default')))
	if defined $o->{ default };
    $buf .= sprintf(" size=\"%s\"", escapeHTML($o->{ size }))
	if defined $o->{ size };
    $buf .= sprintf(" maxlength=\"%s\"", escapeHTML($o->{ maxlength }))
	if defined $o->{ maxlength };

    return $buf . ">";
}


# Descriptions: a hidden input.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub hidden
{
    my $o = _opt(@_);

    # XXX CGI.pm reads -value and -default as the same thing here, and
    # XXX fml8 uses both spellings.
    my $v = defined $o->{ value } ? $o->{ value } : $o->{ default };
    $v    = ref($v) eq 'ARRAY' ? (defined $v->[0] ? $v->[0] : '') : $v;
    $v    = '' unless defined $v;

    return sprintf("<input type=\"hidden\" name=\"%s\" value=\"%s\">",
		   escapeHTML($o->{ name }), escapeHTML($v));
}


# Descriptions: a submit button.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub submit
{
    my $o    = _opt(@_);
    my $name = defined $o->{ name } ? $o->{ name } : '';
    my $val  = defined $o->{ value } ? $o->{ value } : $name;

    return sprintf("<input type=\"submit\" name=\"%s\" value=\"%s\">",
		   escapeHTML($name), escapeHTML($val));
}


=head2 reset(-name => $name)

a reset button.

=cut


# Descriptions: a reset button.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub reset
{
    my $o    = _opt(@_);
    my $name = defined $o->{ name } ? $o->{ name } : 'Reset';

    return sprintf("<input type=\"reset\" name=\"%s\" value=\"%s\">",
		   escapeHTML($name), escapeHTML($name));
}


=head2 table({ -border => $n }, @rows)

=head2 Tr($attr, @cells)

=head2 td([ @cells ]) or td($cell)

The three fml8 uses to lay a form out.  Each takes an optional leading
HASH_REF of attributes, which is how CGI.pm spells it, and joins what
follows.

=cut


# Descriptions: split a leading HASH_REF of attributes off the argument list.
#    Arguments: ARRAY_REF($av)
# Side Effects: shift $av when the first element is a HASH_REF.
# Return Value: STR
sub _attr
{
    my ($av) = @_;

    # XXX undef is passed where CGI.pm expects "no attributes", as in
    # XXX Tr( undef, ... ), so it has to be swallowed the same way.
    unless (@$av) { return '' }

    my $first = $av->[0];
    if (!defined($first) || ref($first) eq 'HASH') {
	shift @$av;
	return '' unless defined $first;

	my $buf = '';
	for my $k (sort keys %$first) {
	    my $v = $first->{ $k };
	    (my $name = $k) =~ s/^-//;

	    # XXX -border => undef means the bare attribute in CGI.pm.
	    # XXX HTML5 has no border attribute on <table> at all, so it
	    # XXX is dropped rather than written out; the tables here are
	    # XXX laying out a form, not showing data.
	    next if lc($name) eq 'border';
	    next unless defined $v;

	    $buf .= sprintf(" %s=\"%s\"", lc($name), escapeHTML($v));
	}
	return $buf;
    }

    return '';
}


# Descriptions: flatten the cells a row or cell was given.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: ARRAY
sub _cells
{
    my (@av) = @_;

    return map { ref($_) eq 'ARRAY' ? @$_ : $_ }
           grep { defined $_ } @av;
}


# Descriptions: a table.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub table
{
    my @av   = @_;
    my $attr = _attr(\@av);

    return sprintf("<table%s>\n%s</table>\n", $attr, join("", _cells(@av)));
}


# Descriptions: a table row.  Named Tr because tr() is a perl operator.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub Tr
{
    my @av   = @_;
    my $attr = _attr(\@av);

    return sprintf("<tr%s>%s</tr>\n", $attr, join("", _cells(@av)));
}


# Descriptions: one or more table cells.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub td
{
    my @av   = @_;
    my $attr = _attr(\@av);

    return join("", map { sprintf("<td%s>%s</td>", $attr,
				  defined $_ ? $_ : '') } _cells(@av));
}


=head2 popup_menu(-name => $name, -values => $values, ...)

=head2 scrolling_list(-name => $name, -values => $values, -size => $n, ...)

=cut


# Descriptions: a one line select.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub popup_menu
{
    return _select(_opt(@_), 0);
}


# Descriptions: a select shown $size rows high.
#    Arguments: ARRAY(@av)
# Side Effects: none
# Return Value: STR
sub scrolling_list
{
    return _select(_opt(@_), 1);
}


# Descriptions: the shared body of popup_menu() and scrolling_list().
#    Arguments: HASH_REF($o) NUM($use_size)
# Side Effects: none
# Return Value: STR
sub _select
{
    my ($o, $use_size) = @_;
    my $values  = $o->{ values } || [];
    $values     = [ $values ] unless ref($values) eq 'ARRAY';
    my $default = _first($o, 'default');
    my $labels  = $o->{ labels } || {};

    my $buf = sprintf("<select name=\"%s\"", escapeHTML($o->{ name }));
    $buf   .= sprintf(" size=\"%s\"", escapeHTML($o->{ size }))
	if $use_size && defined $o->{ size };
    $buf   .= ">\n";

    for my $v (@$values) {
	next unless defined $v;
	my $label = defined $labels->{ $v } ? $labels->{ $v } : $v;

	$buf .= sprintf("<option value=\"%s\"%s>%s</option>\n",
			escapeHTML($v),
			($v eq $default ? ' selected' : ''),
			escapeHTML($label));
    }

    return $buf . "</select>\n";
}


=head2 url()

the URL this script was reached by.

=cut


# Descriptions: the URL this script was reached by.
#    Arguments: none
# Side Effects: none
# Return Value: STR
sub url
{
    # XXX Scheme from HTTPS or the port rather than assumed, since a
    # XXX plain http:// here on a TLS site sends the browser back out
    # XXX of it.  HTTP_HOST carries the port when there is one.
    my $https  = $ENV{ HTTPS } || '';
    my $port   = $ENV{ SERVER_PORT } || 80;
    my $scheme = ($https =~ /^on$/i || $port == 443) ? 'https' : 'http';

    my $host = $ENV{ HTTP_HOST } || $ENV{ SERVER_NAME } || 'localhost';
    my $path = $ENV{ SCRIPT_NAME } || '';

    return sprintf("%s://%s%s", $scheme, $host, $path);
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

FML::CGI::Compat appeared in fml8 mailing list driver package.

=cut


1;
