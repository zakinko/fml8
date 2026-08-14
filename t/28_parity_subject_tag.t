#-*- perl -*-
#
# Subject tags: the shapes fml4 could produce, against fml8.
#
# The tag is the most visible thing a mailing list does to a message,
# and it is what subscribers filter on.  A list migrated from fml4 to
# fml8 that starts tagging differently breaks every filter its members
# have, silently, on the first article.
#
# fml4 offers a fixed menu of layouts through SubjectTagDef(): the mode
# string "[ ]" gives "[Elena 100]", "(:)" gives "(Elena:100)", and so
# on.  Each sets a begin bracket, a separator and an end bracket.  fml8
# dropped the menu for one free-form tag, "[elena:%05d]" and the like,
# which is more general -- so every fml4 layout should be expressible.
#
# This walks fml4's menu, builds the equivalent fml8 tag, and checks
# fml8 can both produce and strip it.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);
use lib 't';

# cpan/lib and img/lib must be APPENDED, never prepended: cpan/lib ships
# File::Spec 0.7, which lacks splitdir()/splitpath()/rel2abs() that both
# fml8 and prove(1) call.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use ParityFML4;
use Mail::Message::Subject;

my $FML4 = ParityFML4::fml4_dir();
plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless $FML4;

my @MODE = @{ ParityFML4::fml4_subject_tag_modes() };
plan skip_all => "could not read fml4's subject tag modes" unless @MODE;

my $ML  = 'elena';
my $SEQ = 100;


# Descriptions: the begin bracket, separator and end bracket fml4 sets
#               for one SubjectTagDef() mode, read from its source.
#    Arguments: STR($mode)
# Side Effects: none
# Return Value: HASH_REF or undef
sub fml4_tag_parts
{
    my ($mode) = @_;

    open(my $fh, '<', "$FML4/proc/libtagdef.pl") or return undef;
    binmode($fh);
    local $/ = undef;
    my $src = <$fh>;
    close($fh);

    # take the branch for this mode, up to the next one
    my $q = quotemeta($mode);
    return undef unless $src =~ /\$mode eq '$q'\)\s*\{(.*?)(?=\n\s*(?:\}\s*)?els|\n\s*\})/s;
    my $body = $1;

    my %p = ();
    $p{ begin } = $1 if $body =~ /\$BEGIN_BRACKET\s*=\s*'([^']*)'/;
    $p{ end   } = $1 if $body =~ /\$END_BRACKET\s*=\s*'([^']*)'/;
    $p{ sep   } = $1 if $body =~ /\$BRACKET_SEPARATOR\s*=\s*'([^']*)'/;

    return undef unless defined $p{ begin } && defined $p{ end };
    $p{ sep } = '' unless defined $p{ sep };

    return \%p;
}


# Descriptions: the fml8 tag string that reproduces one fml4 layout.
#    Arguments: HASH_REF($p)
# Side Effects: none
# Return Value: STR
sub fml8_tag_for
{
    my ($p) = @_;

    return sprintf("%s%s%s%%d%s", $p->{ begin }, $ML, $p->{ sep }, $p->{ end });
}


# ---------------------------------------------------------------------
# 1. fml4's menu was read
# ---------------------------------------------------------------------
subtest "fml4's tag layouts were found" => sub {
    cmp_ok(scalar(@MODE), '>=', 5,
	   scalar(@MODE) . ' layouts: ' . join(' ', map { "\"$_\"" } @MODE));

    # the two fml4 documents everywhere
    my %m = map { $_ => 1 } @MODE;
    ok($m{ '[ ]' }, '"[ ]" is one of them');
    ok($m{ '( )' }, '"( )" is one of them');
};


# ---------------------------------------------------------------------
# 2. each layout's parts are readable
# ---------------------------------------------------------------------
subtest 'each layout states a begin, a separator and an end' => sub {
    for my $mode (@MODE) {
	my $p = fml4_tag_parts($mode);
	ok($p, "\"$mode\" parsed")
	    or next;
	ok(length($p->{ begin }), "\"$mode\" begin: $p->{begin}");
	ok(length($p->{ end }),   "\"$mode\" end: $p->{end}");
    }
};


# ---------------------------------------------------------------------
# 3. fml8 can strip the tag each layout produces
#
# delete_tag() is what runs on an incoming article, so this is the part
# that matters for a migrated list: a reply carrying fml4's old tag must
# not end up double-tagged.
# ---------------------------------------------------------------------
subtest 'fml8 strips the tag every fml4 layout produces' => sub {
    for my $mode (@MODE) {
	my $p = fml4_tag_parts($mode) or next;
	my $tag = fml8_tag_for($p);

	# what fml4 would have put on article 100
	my $fml4_tag = sprintf("%s%s%s%d%s",
			       $p->{ begin }, $ML, $p->{ sep }, $SEQ,
			       $p->{ end });

	my $s = new Mail::Message::Subject "$fml4_tag hello";
	$s->delete_tag($tag);
	my $out = $s->as_str();
	$out =~ s/^\s+//;
	$out =~ s/\s+$//;

	is($out, 'hello', "\"$mode\": $fml4_tag stripped");
    }
};


# ---------------------------------------------------------------------
# 4. and does not strip somebody else's
#
# A tag pattern loose enough to match anything would pass subtest 3 and
# quietly eat text out of unrelated subjects.
# ---------------------------------------------------------------------
subtest 'fml8 leaves other lists\' tags alone' => sub {
    for my $mode (@MODE) {
	my $p = fml4_tag_parts($mode) or next;
	my $tag = fml8_tag_for($p);

	my $other = sprintf("%s%s%s%d%s",
			    $p->{ begin }, 'mirei', $p->{ sep }, $SEQ,
			    $p->{ end });

	my $s = new Mail::Message::Subject "$other hello";
	$s->delete_tag($tag);
	my $out = $s->as_str();
	$out =~ s/^\s+//;

	is($out, "$other hello", "\"$mode\": $other kept");
    }
};


# ---------------------------------------------------------------------
# 5. zero padding, which fml4 could not do
#
# fml8's tag is a format string, so "[elena:%05d]" is available where
# fml4 only had a bare number.  Nothing in fml4 to compare against; this
# is here so the extra capability does not regress.
# ---------------------------------------------------------------------
subtest 'fml8 tags can pad, which fml4 could not' => sub {
    my $tag = "[$ML:%05d]";

    my $s = new Mail::Message::Subject "[$ML:00100] hello";
    $s->delete_tag($tag);
    my $out = $s->as_str();
    $out =~ s/^\s+//;

    is($out, 'hello', 'a zero padded tag is stripped');

    # and the unpadded form of the same list is still recognised
    my $s2 = new Mail::Message::Subject "[$ML:100] hello";
    $s2->delete_tag($tag);
    my $out2 = $s2->as_str();
    $out2 =~ s/^\s+//;

    local $TODO = 'the unpadded form of a padded tag is not stripped';
    is($out2, 'hello', 'the unpadded form is stripped too');
};


# ---------------------------------------------------------------------
# 6. reply tags
#
# fml4 stripped duplicated "Re:" while rewriting; fml8 has
# delete_dup_reply_tag() for the same job.  A migrated list that stops
# doing it grows "Re: Re: Re:" within a day.
# ---------------------------------------------------------------------
subtest 'duplicated reply tags are still collapsed' => sub {
    for my $in ('Re: Re: hello', 'Re: Re: Re: hello') {
	my $s = new Mail::Message::Subject $in;
	$s->delete_dup_reply_tag();
	my $out = $s->as_str();

	is($out, 'Re: hello', "\"$in\" -> \"$out\"");
    }

    my $s = new Mail::Message::Subject 'Re: hello';
    ok($s->has_reply_tag(), 'a single Re: is recognised');

    my $p = new Mail::Message::Subject 'hello';
    ok(!$p->has_reply_tag(), 'a plain subject has none');
};

done_testing();
