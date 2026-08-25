#-*- perl -*-
#
# Membership: the map, and the decision taken from it.
#
# This is the question everything else depends on.  A post is accepted
# or refused, a command is obeyed or ignored, an article is delivered or
# not, all on the answer to "is this address in that map".
#
# The answer is taken in two stages, and the split is deliberate.
# IO::Adapter::find() is a loose match -- it takes a pattern, not an
# address, and "aro" finds "taro@example.jp" -- and its job is only to
# narrow the file down to candidates.  FML::Credential::is_same_address()
# then decides, with the case and domain rules the configuration asks
# for.  The caller quotemeta()s the user part before handing it over, so
# a metacharacter in an incoming address is a literal.
#
# Written down because the loose half looks like a bug on its own and is
# the sort of thing that gets "fixed" by making find() authoritative --
# which would let aro@example.jp post to a list taro@example.jp belongs
# to.  Both halves are pinned here, and so is the join between them.
#

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use IO::Adapter;
use FML::Credential;

my $TMPDIR = tempdir(CLEANUP => 1);
my $SEQ    = 0;


{
    package t::Config;

    sub new { return bless { %{ $_[1] || {} } }, $_[0] }
    sub yes { my $v = $_[0]->{ $_[1] };
	      return (defined $v && $v eq 'yes') ? 1 : 0 }
    sub get { return $_[0]->{ $_[1] } }
}

{
    package t::Curproc;

    sub new       { return bless { _config => $_[1] }, $_[0] }
    sub config    { return $_[0]->{ _config } }
    sub log       { return 1 }
    sub logdebug  { return 1 }
    sub logerror  { return 1 }
}


# Descriptions: write $body to a fresh file and return "file:$path".
#    Arguments: STR($body)
# Side Effects: creates a file.
# Return Value: STR
sub map_of
{
    my ($body) = @_;
    my $path   = sprintf("%s/map.%d", $TMPDIR, $SEQ++);

    open(my $wh, '>', $path) or die "cannot write $path: $!";
    binmode($wh);
    print $wh $body;
    close($wh);

    return "file:$path";
}


# Descriptions: a credential configured as given.
#    Arguments: HASH_REF($args)
# Side Effects: FML::Credential is process-wide; this reconfigures it.
# Return Value: OBJ
sub credential
{
    my ($args) = @_;

    my %config = (
	use_address_compare_function  => 'yes',
	address_compare_function_type => 'user_part_case_insensitive',
	address_compare_function_domain_matching_level => 3,
	%{ $args || {} },
    );

    return new FML::Credential t::Curproc->new(t::Config->new(\%config));
}


my $ROSTER = <<'END_OF_MAP';
taro@example.jp
hanako@example.jp
ichiro@example.co.jp
END_OF_MAP


# ---------------------------------------------------------------------
# 1. reading a map
#
# getline() is the raw line; get_next_key() is the cooked one, and the
# difference is what a comment and a blank line do.
# ---------------------------------------------------------------------
subtest 'a file map is read line by line' => sub {
    my $map = map_of(<<'END_OF_MAP');
taro@example.jp
hanako@example.jp	Hanako Suzuki
# a comment

ichiro@example.co.jp
END_OF_MAP

    my $raw = new IO::Adapter $map;
    ok($raw->open(), 'the map opens');

    my @line = ();
    while (defined(my $l = $raw->getline())) {
	chomp $l;
	push @line, $l;
    }
    $raw->close();

    is(scalar(@line), 5, 'getline() gives every line, comment and blank too');

    my $cooked = new IO::Adapter $map;
    $cooked->open();

    my @key = ();
    while (defined(my $k = $cooked->get_next_key())) {
	chomp $k;
	push @key, $k;
    }
    $cooked->close();

    is_deeply(\@key,
	      [ 'taro@example.jp', 'hanako@example.jp', 'ichiro@example.co.jp' ],
	      'get_next_key() skips comments and blanks and takes the first field');
};


# ---------------------------------------------------------------------
# 2. find() is a pattern match, and is not a membership decision
#
# Recorded as behaviour rather than complained about: this is the
# narrowing stage.  The point of writing it down is that every one of
# these would be a hole if find() were the whole answer.
# ---------------------------------------------------------------------
subtest 'find() matches loosely, on purpose' => sub {
    my $map = map_of($ROSTER);

    my %case = (
	'the whole address'   => [ 'taro@example.jp',  1 ],
	'the user part alone' => [ 'taro',             1 ],
	'a suffix of it'      => [ 'aro@example.jp',   1 ],
	'a regexp'            => [ '.*',              1 ],
	'a character class'   => [ '[a-z]+@example',  1 ],
	'nothing like it'     => [ 'nobody',           0 ],
    );

    for my $name (sort keys %case) {
	my ($pattern, $want) = @{ $case{ $name } };

	my $obj = new IO::Adapter $map;
	$obj->open();
	my $got = $obj->find($pattern);
	$obj->close();

	is((defined $got && $got =~ /\S/) ? 1 : 0, $want,
	   "$name: find('$pattern')");
    }
};


# ---------------------------------------------------------------------
# 3. the decision is not the narrowing
#
# The assertion this whole file exists for.  Each of these finds
# something with find() and must still not be a member.
# ---------------------------------------------------------------------
subtest 'a loose match is not a membership' => sub {
    my $map  = map_of($ROSTER);
    my $cred = credential();

    my %case = (
	'the member'            => [ 'taro@example.jp',       1 ],
	'another member'        => [ 'hanako@example.jp',     1 ],
	'a suffix of a member'  => [ 'aro@example.jp',        0 ],
	'a prefix of a member'  => [ 'tar@example.jp',        0 ],
	'a member plus a digit' => [ 'taro2@example.jp',      0 ],
	'a longer name'         => [ 'hanakotaro@example.jp', 0 ],
	'the right user, wrong domain' => [ 'taro@example.com', 0 ],
	'nobody'                => [ 'nobody@example.jp',     0 ],
    );

    for my $name (sort keys %case) {
	my ($addr, $want) = @{ $case{ $name } };

	is($cred->has_address_in_map($map, {}, $addr), $want,
	   "$name: $addr");
    }
};


# ---------------------------------------------------------------------
# 4. a metacharacter in an address is a literal
#
# has_address_in_map() quotemeta()s the user part before it becomes a
# pattern.  Without that, an address whose user part is ".*" would find
# every line in the map, and each of those would then go to
# is_same_address() -- which would refuse them, so this is defence in
# depth rather than the only guard.  It is still the guard that stops a
# roster of ten thousand being walked on every message.
# ---------------------------------------------------------------------
subtest 'a regexp in an address does not become a regexp' => sub {
    my $map  = map_of($ROSTER);
    my $cred = credential();

    for my $addr ('.*@example.jp', '.*', '[a-z]*@example.jp',
		  'taro|hanako@example.jp', '^taro@example.jp$',
		  't.ro@example.jp') {
	is($cred->has_address_in_map($map, {}, $addr), 0,
	   "not a member: $addr");
    }

    # And the guard is in the source where it is claimed to be.
    open(my $fh, '<', 'fml/lib/FML/Credential.pm') or die $!;
    local $/ = undef;
    my $src = <$fh>;
    close($fh);

    like($src, qr/quotemeta\(\$user\)/,
	 'the user part is quotemeta()d before it is used as a pattern');
};


# ---------------------------------------------------------------------
# 5. the case rules reach the map lookup
#
# is_same_address() has a dial for the case of the user part, and the
# lookup has to honour it -- otherwise the dial changes what two
# addresses compare as but not who is on the list.
# ---------------------------------------------------------------------
subtest 'the case configuration reaches the map lookup' => sub {
    my $map = map_of($ROSTER);

    my $ci = credential({
	address_compare_function_type => 'user_part_case_insensitive' });
    is($ci->has_address_in_map($map, {}, 'TARO@example.jp'), 1,
       'case insensitive: TARO is a member');
    is($ci->has_address_in_map($map, {}, 'Taro@Example.JP'), 1,
       'and so is Taro@Example.JP');

    my $cs = credential({
	address_compare_function_type => 'user_part_case_sensitive' });
    is($cs->has_address_in_map($map, {}, 'TARO@example.jp'), 0,
       'case sensitive: TARO is not');
    is($cs->has_address_in_map($map, {}, 'taro@EXAMPLE.JP'), 1,
       'but the domain is still case insensitive');
};


# ---------------------------------------------------------------------
# 6. which entry matched
#
# matched_address() is what gets written back when a subscriber is
# removed, so it has to be the entry as the map spells it, not as the
# incoming mail spelled it.  Removing "TARO@example.jp" from a file that
# says "taro@example.jp" removes nothing.
# ---------------------------------------------------------------------
subtest 'the matched entry is the one the map holds' => sub {
    my $map  = map_of($ROSTER);
    my $cred = credential();

    is($cred->has_address_in_map($map, {}, 'TARO@example.jp'), 1,
       'TARO@example.jp is a member');
    is($cred->matched_address(), 'taro@example.jp',
       'and the entry reported is the one in the file');

    # A miss must not leave the previous answer behind.
    is($cred->has_address_in_map($map, {}, 'nobody@example.jp'), 0,
       'nobody@example.jp is not a member');
    my $m = $cred->matched_address();
    ok(!defined $m || $m eq '' || $m ne 'taro@example.jp',
       'and the previous match was not left in place')
	or diag("matched_address() still says: $m");
};


# ---------------------------------------------------------------------
# 7. an empty map, and a map that is not there
#
# A missing member map must mean "nobody is a member", not "everybody
# is" and not a died process.  This is the state a newly created list is
# in, and the state a broken deployment is in.
# ---------------------------------------------------------------------
subtest 'an empty or missing map has no members' => sub {
    my $cred = credential();

    my $empty = map_of('');
    is($cred->has_address_in_map($empty, {}, 'taro@example.jp'), 0,
       'an empty map has no members');

    my $blank = map_of("\n\n\n");
    is($cred->has_address_in_map($blank, {}, 'taro@example.jp'), 0,
       'a map of blank lines has no members');

    my $comments = map_of("# taro\@example.jp\n# everyone\n");
    is($cred->has_address_in_map($comments, {}, 'taro@example.jp'), 0,
       'a commented out entry is not a member');

    my $missing = "file:$TMPDIR/no-such-map";
    my $r = eval { $cred->has_address_in_map($missing, {}, 'taro@example.jp') };
    is($@, '', 'a missing map does not die') or diag($@);
    is($r, 0, 'and has no members');
};


# ---------------------------------------------------------------------
# 8. what a map line may carry besides the address
#
# The second field is the subscriber's name and it is free text, in
# whatever charset the list runs in.  It must not affect the lookup, and
# it must not be mistaken for part of the address.
# ---------------------------------------------------------------------
subtest 'the fields after the address are ignored' => sub {
    my $map = map_of(join('', map { "$_\n" }
	"taro\@example.jp\tTaro Yamada",
	"hanako\@example.jp \xc6\xfc\xcb\xdc\xb8\xec",       # euc-jp
	"ichiro\@example.co.jp \xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e", # utf-8
	"jiro\@example.jp   several   spaces   here",
    ));

    my $cred = credential();

    for my $addr ('taro@example.jp', 'hanako@example.jp',
		  'ichiro@example.co.jp', 'jiro@example.jp') {
	is($cred->has_address_in_map($map, {}, $addr), 1, "$addr is a member");
    }

    # And the name is not an address.
    is($cred->has_address_in_map($map, {}, 'Taro Yamada'), 0,
       'the display name is not a membership');
    is($cred->has_address_in_map($map, {}, 'several@example.jp'), 0,
       'nor is a word out of the rest of the line');
};


# ---------------------------------------------------------------------
# 9. adding and removing
#
# The write side of the same map.  A subscribe that does not land, or an
# unsubscribe that does not remove, is the commonest complaint a list
# owner gets.
# ---------------------------------------------------------------------
subtest 'add() and delete() change what the map holds' => sub {
    my $map  = map_of($ROSTER);
    my $cred = credential();

    is($cred->has_address_in_map($map, {}, 'jiro@example.jp'), 0,
       'jiro is not a member to begin with');

    my $w = new IO::Adapter $map;
    $w->open( { flag => 'a' } );
    $w->add('jiro@example.jp');
    $w->close();

    is($cred->has_address_in_map($map, {}, 'jiro@example.jp'), 1,
       'after add(), jiro is a member');
    is($cred->has_address_in_map($map, {}, 'taro@example.jp'), 1,
       'and taro still is');

    my $d = new IO::Adapter $map;
    $d->open( { flag => 'a' } );
    $d->delete('jiro@example.jp');
    $d->close();

    is($cred->has_address_in_map($map, {}, 'jiro@example.jp'), 0,
       'after delete(), jiro is not');
    is($cred->has_address_in_map($map, {}, 'taro@example.jp'), 1,
       'and the others are untouched');
    is($cred->has_address_in_map($map, {}, 'hanako@example.jp'), 1,
       'all of them');
};


# ---------------------------------------------------------------------
# 10. deleting one address does not delete a longer one
#
# delete() works on the file, and if it matched loosely it would take
# "hanakotaro@example.jp" out along with "taro@example.jp".  That is the
# same class of mistake as find() being taken for the answer, on the
# other side of the map.
# ---------------------------------------------------------------------
subtest 'delete() removes one entry, not everything like it' => sub {
    my $map = map_of(<<'END_OF_MAP');
taro@example.jp
hanakotaro@example.jp
taro@example.com
taro2@example.jp
END_OF_MAP

    my $d = new IO::Adapter $map;
    $d->open( { flag => 'a' } );
    $d->delete('taro@example.jp');
    $d->close();

    my $cred = credential();

    is($cred->has_address_in_map($map, {}, 'taro@example.jp'), 0,
       'the address asked for is gone');

    for my $keep ('hanakotaro@example.jp', 'taro@example.com',
		  'taro2@example.jp') {
	is($cred->has_address_in_map($map, {}, $keep), 1,
	   "$keep is still there");
    }
};

done_testing();
