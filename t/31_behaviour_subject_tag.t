#-*- perl -*-
#
# Subject tags, asked of fml4 rather than read from it.
#
# t/28 parses libtagdef.pl to learn what each layout looks like.  This
# one runs SubjectTagDef() and takes its answer, which includes
# $SUBJECT_FREE_FORM_REGEXP -- the pattern fml4 itself uses to recognise
# its own tag on an incoming article.
#
# That pattern is the interesting object.  A list migrated from fml4 to
# fml8 keeps receiving replies carrying tags fml4 put there, and fml8
# has to recognise exactly those, or the article goes out with two tags.
# So the test is: generate what fml4 would have generated, confirm fml4
# would recognise it, then require fml8 to strip it.
#
# fml4 runs in a process of its own; see ParityFML4::run_in_fml4.
#

use strict;
use warnings;
use Test::More;
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

plan skip_all => "no fml4 checkout (set FML4_DIR, or put one at ../fml4)"
    unless ParityFML4::fml4_dir();
plan skip_all => "fml4 will not run here"
    unless ParityFML4::fml4_is_runnable();

# fml4 as published does not compile on a perl newer than 5.30, so this
# comparison can only be made against a tree that has been made to.  The
# modernize-perl branch is exactly that and changes nothing else.
my $LOAD_ERROR = ParityFML4::fml4_load_error("proc/libtagdef.pl");
plan skip_all => $LOAD_ERROR if $LOAD_ERROR;

my $ML  = 'Elena';       # libtagdef.pl's own default $BRACKET
my $SEQ = 100;


# Descriptions: run fml4's SubjectTagDef() for every layout and return
#               what it set, one record per layout.
#    Arguments: none
# Side Effects: forks a perl(1).
# Return Value: ARRAY_REF of HASH_REF
sub fml4_layouts
{
    my $out = ParityFML4::run_in_fml4(q{
	require "./proc/libtagdef.pl";

	# the modes SubjectTagDef() branches on, read from itself
	open(my $fh, "<", "proc/libtagdef.pl") or exit 1;
	local $/ = undef;
	my $src = <$fh>;
	close($fh);

	my %seen = ();
	my @mode = ();
	while ($src =~ /\$mode eq '([^']*)'/g) {
	    push @mode, $1 unless $seen{$1}++;
	}

	for my $m (@mode) {
	    # each branch only assigns what it needs, so clear first
	    $main::BEGIN_BRACKET = $main::END_BRACKET = "";
	    $main::BRACKET_SEPARATOR = "";
	    $main::SUBJECT_FREE_FORM_REGEXP = "";
	    $main::BRACKET = "Elena";

	    &main::SubjectTagDef($m);

	    printf "%s\t%s\t%s\t%s\t%s\n", $m,
		$main::BEGIN_BRACKET, $main::BRACKET_SEPARATOR,
		$main::END_BRACKET, $main::SUBJECT_FREE_FORM_REGEXP;
	}
    });

    my @rec = ();
    for my $line (split(/\n/, $out)) {
	my ($mode, $begin, $sep, $end, $re) = split(/\t/, $line, 5);
	next unless defined $end && length($begin);
	push @rec, {
	    mode   => $mode,
	    begin  => $begin,
	    sep    => defined $sep ? $sep : '',
	    end    => $end,
	    regexp => defined $re ? $re : '',
	};
    }

    return \@rec;
}


# Descriptions: does fml4's own pattern match this subject?
#    Arguments: STR($regexp) STR($subject)
# Side Effects: forks a perl(1).
# Return Value: NUM(1 or 0)
sub fml4_recognises
{
    my ($regexp, $subject) = @_;

    my $hex_re = unpack("H*", $regexp);
    my $hex_s  = unpack("H*", $subject);

    my $out = ParityFML4::run_in_fml4(qq{
	my \$re = pack("H*", "$hex_re");
	my \$s  = pack("H*", "$hex_s");
	print((\$s =~ /\$re/) ? "1\\n" : "0\\n");
    });

    chomp($out);
    return $out eq '1' ? 1 : 0;
}


my $LAYOUT = fml4_layouts();


# ---------------------------------------------------------------------
# 1. fml4 answered
# ---------------------------------------------------------------------
subtest 'fml4 SubjectTagDef() runs and describes each layout' => sub {
    cmp_ok(scalar(@$LAYOUT), '>=', 5,
	   scalar(@$LAYOUT) . ' layouts came back from fml4');

    for my $l (@$LAYOUT) {
	ok(length($l->{ begin }), "\"$l->{mode}\" has a begin bracket");
	ok(length($l->{ end }),   "\"$l->{mode}\" has an end bracket");
	ok(length($l->{ regexp }),
	   "\"$l->{mode}\" has a recognition pattern: $l->{regexp}");
    }
};


# ---------------------------------------------------------------------
# 2. fml4 recognises its own output
#
# Establishes that the generated tag really is what fml4 would emit,
# before asking fml8 anything about it.
# ---------------------------------------------------------------------
subtest 'fml4 recognises the tags it would produce' => sub {
    for my $l (@$LAYOUT) {
	my $tag = sprintf("%s%s%s%d%s",
			  $l->{ begin }, $ML, $l->{ sep }, $SEQ, $l->{ end });

	# the "(ID)" layout is the sequence number alone
	$tag = sprintf("%s%d%s", $l->{ begin }, $SEQ, $l->{ end })
	    if $l->{ regexp } !~ /\Q$ML\E/;

	# the "[]" layout has no number at all
	$tag = sprintf("%s%s%s", $l->{ begin }, $ML, $l->{ end })
	    if $l->{ regexp } !~ /\\d/;

	ok(fml4_recognises($l->{ regexp }, "$tag hello"),
	   "\"$l->{mode}\": fml4 recognises $tag");
    }
};


# ---------------------------------------------------------------------
# 3. fml8 strips what fml4 emitted
#
# The migration case: a reply carrying fml4's tag arrives at a list now
# running fml8.
# ---------------------------------------------------------------------
subtest 'fml8 strips a tag fml4 produced' => sub {
    for my $l (@$LAYOUT) {
	next if $l->{ regexp } !~ /\\d/;    # layouts with a number
	next if $l->{ regexp } !~ /\Q$ML\E/; # and with the list name

	my $fml4_tag = sprintf("%s%s%s%d%s",
			       $l->{ begin }, $ML, $l->{ sep }, $SEQ,
			       $l->{ end });
	my $fml8_tag = sprintf("%s%s%s%%d%s",
			       $l->{ begin }, $ML, $l->{ sep }, $l->{ end });

	my $s = new Mail::Message::Subject "$fml4_tag hello";
	$s->delete_tag($fml8_tag);
	my $out = $s->as_str();
	$out =~ s/^\s+//;
	$out =~ s/\s+$//;

	is($out, 'hello', "\"$l->{mode}\": $fml4_tag stripped by fml8");
    }
};


# ---------------------------------------------------------------------
# 4. fml8 does not strip another list's tag
#
# The same pattern being loose enough to eat anything would satisfy
# subtest 3 and quietly damage unrelated subjects.
# ---------------------------------------------------------------------
subtest "fml8 leaves another list's tag alone" => sub {
    for my $l (@$LAYOUT) {
	next if $l->{ regexp } !~ /\\d/;
	next if $l->{ regexp } !~ /\Q$ML\E/;

	my $other = sprintf("%s%s%s%d%s",
			    $l->{ begin }, 'Mirei', $l->{ sep }, $SEQ,
			    $l->{ end });
	my $fml8_tag = sprintf("%s%s%s%%d%s",
			       $l->{ begin }, $ML, $l->{ sep }, $l->{ end });

	my $s = new Mail::Message::Subject "$other hello";
	$s->delete_tag($fml8_tag);
	my $out = $s->as_str();
	$out =~ s/^\s+//;

	is($out, "$other hello", "\"$l->{mode}\": $other kept");
    }
};


# ---------------------------------------------------------------------
# 5. and fml4 would not have stripped it either
#
# Both generations must agree about whose tag it is, or a migrated list
# starts behaving differently towards its neighbours' mail.
# ---------------------------------------------------------------------
subtest 'the two agree about which tags are theirs' => sub {
    for my $l (@$LAYOUT) {
	next if $l->{ regexp } !~ /\\d/;
	next if $l->{ regexp } !~ /\Q$ML\E/;

	my $other = sprintf("%s%s%s%d%s",
			    $l->{ begin }, 'Mirei', $l->{ sep }, $SEQ,
			    $l->{ end });

	ok(!fml4_recognises($l->{ regexp }, "$other hello"),
	   "\"$l->{mode}\": fml4 does not claim $other either");
    }
};

done_testing();
