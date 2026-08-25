#-*- perl -*-
#
# Tie::JournaledFile: the append-only store fml8 keeps its caches in.
#
# Nothing here is ever rewritten in place.  A new value for a key is a
# new line at the end of the file, and reading takes the last line with
# that key -- or the first, if the caller asks for "first match".  That
# is what makes it safe to write to while another process is reading,
# which is the whole reason a mailing list driver uses it: several
# messages can be in flight at once, each in its own process, with no
# lock between them.
#
# It holds the message-id cache (which decides whether an article is a
# duplicate and should be dropped), the confirmation ids, and the error
# counters.  A key lookup that matched too loosely would drop somebody
# else's article as a duplicate; one that matched too tightly would let
# a loop run.
#
# It had no tests.
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

use Tie::JournaledFile;

my $TMPDIR = tempdir(CLEANUP => 1);
my $SEQ    = 0;


# Descriptions: a path nothing else in this file uses.
#    Arguments: none
# Side Effects: none
# Return Value: STR
sub fresh_file
{
    return sprintf("%s/cache.%d", $TMPDIR, $SEQ++);
}


# Descriptions: the raw contents of $path.
#    Arguments: STR($path)
# Side Effects: none
# Return Value: STR
sub slurp
{
    my ($path) = @_;

    return '' unless -f $path;
    open(my $fh, '<', $path) or return '';
    binmode($fh);
    local $/ = undef;
    my $s = <$fh>;
    close($fh);

    return defined $s ? $s : '';
}


# ---------------------------------------------------------------------
# 1. what goes in comes out
# ---------------------------------------------------------------------
subtest 'a value stored is a value fetched' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    ok(defined $db, 'the store constructs');

    $db->STORE('rudo', 'teddy bear');
    $db->STORE('ken',  'north fox');

    is($db->FETCH('rudo'), 'teddy bear', 'rudo');
    is($db->FETCH('ken'),  'north fox',  'ken');

    is($db->FETCH('nobody'), undef, 'a key never stored is undef');
};


# ---------------------------------------------------------------------
# 2. the file is a journal
#
# The old value stays on disk.  That is the property the whole design
# rests on: a reader part way through the file sees a consistent older
# answer rather than a half-written newer one.
# ---------------------------------------------------------------------
subtest 'writing again appends rather than rewrites' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    $db->STORE('rudo', 'teddy bear');
    $db->STORE('rudo', 'brown bear');
    $db->STORE('rudo', 'polar bear');

    my $raw = slurp($file);
    my @line = grep { /\S/ } split(/\n/, $raw);

    is(scalar(@line), 3, 'three writes, three lines');
    like($raw, qr/teddy bear/,  'the first value is still on disk');
    like($raw, qr/brown bear/,  'and the second');
    like($raw, qr/polar bear/,  'and the third');

    # Each line is "key<whitespace>value".
    for my $l (@line) {
	like($l, qr/^rudo\s+\S/, "line is key then value: [$l]");
    }
};


# ---------------------------------------------------------------------
# 3. last match wins, and first match can be asked for
#
# Which one a caller wants depends on what the key means.  The newest
# answer is right for a counter; the oldest is right for "when did we
# first see this message-id".
# ---------------------------------------------------------------------
subtest 'the match condition decides which write is read' => sub {
    my $file = fresh_file();

    my $w = new Tie::JournaledFile { file => $file };
    $w->STORE('x', 'first');
    $w->STORE('x', 'second');
    $w->STORE('x', 'third');

    my $last = new Tie::JournaledFile { file => $file };
    is($last->FETCH('x'), 'third', 'the default is the newest value');

    my $first = new Tie::JournaledFile { file => $file,
					 match_condition => 'first' };
    is($first->FETCH('x'), 'first', '"first" gives the oldest');

    # find() gives every value, in the order they were written.
    my @all = $last->find('x');
    is_deeply(\@all, [ 'first', 'second', 'third' ],
	      'find() gives all of them, oldest first');
};


# ---------------------------------------------------------------------
# 4. keys match exactly
#
# The store is a flat file and the lookup is a scan, so this is the
# question worth asking of it.  A key that matched as a prefix would
# make "rudo" find "rudolf" -- and in the message-id cache that means
# one article suppressing another.
# ---------------------------------------------------------------------
subtest 'a key does not match a longer or shorter one' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    $db->STORE('rudo',   'A');
    $db->STORE('rudolf', 'B');
    $db->STORE('ud',     'C');
    $db->STORE('RUDO',   'D');

    is($db->FETCH('rudo'),   'A', 'rudo');
    is($db->FETCH('rudolf'), 'B', 'rudolf is not rudo');
    is($db->FETCH('ud'),     'C', 'ud is not rudo either');
    is($db->FETCH('RUDO'),   'D', 'and keys are case sensitive');

    is($db->FETCH('udo'),   undef, 'a substring of a key is not a key');
    is($db->FETCH('rud'),   undef, 'nor is a prefix');
    is($db->FETCH('rudos'), undef, 'nor is an extension');

    is_deeply([ $db->find('rudo') ], [ 'A' ],
	      'find() is exact as well');
};


# ---------------------------------------------------------------------
# 5. the keys fml8 really uses
#
# Message-ids, with the angle brackets and the punctuation they carry.
# These are the strings the cache is keyed on in practice, and several
# of them are regexp metacharacters.
# ---------------------------------------------------------------------
subtest 'a message-id works as a key' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    my @id = (
	'<20010909014640.ABC123@example.jp>',
	'<a.b+c$d@example.co.jp>',
	'<1234567890.9876.qmail@nuinui.net>',
	'<[a-z]*@example.jp>',
	'<.*@example.jp>',
    );

    my $n = 0;
    for my $id (@id) {
	$db->STORE($id, 'seen.' . $n++);
    }

    $n = 0;
    for my $id (@id) {
	is($db->FETCH($id), 'seen.' . $n++, "fetched: $id");
    }

    # The metacharacter ones must not have matched each other.
    isnt($db->FETCH('<.*@example.jp>'), $db->FETCH('<[a-z]*@example.jp>'),
	 'two patterns as keys are two different keys');

    # And a message-id that was never stored is not a duplicate.
    is($db->FETCH('<never.seen@example.jp>'), undef,
       'an unseen message-id is not in the cache');
};


# ---------------------------------------------------------------------
# 6. values with whitespace in them
#
# The line format is "key<whitespace>value", so a value containing
# whitespace is the case that tests where the split happens.  Subscriber
# names go in these.
# ---------------------------------------------------------------------
subtest 'a value may contain whitespace' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    # The keys are deliberately whitespace free; see the subtest below.
    my %case = (
	'spaces'      => 'Taro Yamada',
	'many.words'  => 'a value with several words in it',
	'tab.inside'  => "before\tafter",
	'punctuation' => 'a: b; c, d "e"',
	'colon'       => 'reason: user unknown',
    );

    for my $name (sort keys %case) {
	$db->STORE($name, $case{ $name });
    }

    for my $name (sort keys %case) {
	is($db->FETCH($name), $case{ $name }, "$name: comes back unchanged");
    }

    # Leading whitespace does not survive, and cannot: the line format
    # is "key<whitespace>value", so the separator and the start of the
    # value are the same characters.  Recorded because a value read back
    # shorter than it was written is the kind of thing that is blamed on
    # the caller.
    $db->STORE('leading', '  indented');
    is($db->FETCH('leading'), 'indented',
       'leading whitespace in a value is absorbed by the separator');

    # Trailing whitespace, on the other hand, is kept.  Not symmetrical,
    # and worth knowing which way round it goes.
    $db->STORE('trailing', "spaced  ");
    is($db->FETCH('trailing'), "spaced  ",
       'but trailing whitespace is part of the value');
};


# ---------------------------------------------------------------------
# 6a. a key may not contain whitespace
#
# It is the field separator, so a key with a space in it is stored as a
# shorter key and a longer value, and reading it back with the key it
# was written under finds nothing.  Silently: the write succeeds.
#
# Nothing in fml8 does this -- the keys are addresses, message-ids and
# counter names -- but it is a real constraint on the store and it is
# not written down anywhere else.
# ---------------------------------------------------------------------
subtest 'a key with whitespace in it cannot be read back' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    $db->STORE('two words', 'a value');

    is($db->FETCH('two words'), undef,
       'the key it was written under finds nothing');

    # What was stored instead: the first word became the key and
    # everything after it -- including the padding STORE() writes to
    # line the columns up -- became the value.
    my $got = $db->FETCH('two');
    ok(defined $got, 'the first word is a key now');
    like($got, qr/^words\s+a value$/,
	 'and the rest of the line is its value');

    # The keys fml8 actually uses have no whitespace in them, which is
    # why this has never bitten.
    for my $k ('taro@example.jp', '<20010909.ABC@example.jp>',
	       'error_count', 'article_id') {
	unlike($k, qr/\s/, "a real key has no whitespace: $k");
    }
};


# ---------------------------------------------------------------------
# 7. octets
#
# Mail is octets and so is everything derived from it.  A store that
# decoded would change the length of what came back.
# ---------------------------------------------------------------------
subtest 'octets are stored and returned unchanged' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    my %case = (
	'euc-jp' => "\xc6\xfc\xcb\xdc\xb8\xec",
	'utf-8'  => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e",
	'high'   => "\xff\xfe\xfd",
	'french' => "caf\xc3\xa9",
    );

    for my $name (sort keys %case) {
	$db->STORE("k.$name", $case{ $name });
    }

    for my $name (sort keys %case) {
	my $got = $db->FETCH("k.$name");
	is($got, $case{ $name }, "$name: the octets come back");
	is(length($got), length($case{ $name }), "$name: and the same length");
    }

    # And as a key.
    $db->STORE("\xc6\xfc\xcb\xdc\xb8\xec", 'japanese key');
    is($db->FETCH("\xc6\xfc\xcb\xdc\xb8\xec"), 'japanese key',
       'an EUC-JP key works too');
};


# ---------------------------------------------------------------------
# 8. an empty store
#
# The state every cache is in on the first message a new list receives.
# ---------------------------------------------------------------------
subtest 'an empty or absent file has no entries' => sub {
    my $file = fresh_file();

    my $db = new Tie::JournaledFile { file => $file };

    is($db->FETCH('anything'), undef, 'nothing is in an absent file');
    is_deeply([ $db->find('anything') ], [], 'and find() gives nothing');

    # Touch it into existence, still empty.
    open(my $wh, '>', $file) or die $!;
    close($wh);

    my $db2 = new Tie::JournaledFile { file => $file };
    is($db2->FETCH('anything'), undef, 'nor in an empty one');

    # A file of blank lines and comments.
    open(my $wh2, '>', $file) or die $!;
    print $wh2 "\n\n# a comment\n\n";
    close($wh2);

    my $db3 = new Tie::JournaledFile { file => $file };
    is($db3->FETCH('anything'), undef, 'nor among blanks and comments');
};


# ---------------------------------------------------------------------
# 9. two handles onto one file
#
# The case the design exists for: one process writing while another
# reads, with no lock.  A reader opened before the write must not see a
# half-written line, and one opened after must see the new value.
# ---------------------------------------------------------------------
subtest 'a second handle sees what the first wrote' => sub {
    my $file = fresh_file();

    my $a = new Tie::JournaledFile { file => $file };
    $a->STORE('shared', 'one');

    my $b = new Tie::JournaledFile { file => $file };
    is($b->FETCH('shared'), 'one', 'the second handle reads the first write');

    $b->STORE('shared', 'two');
    is($a->FETCH('shared'), 'two', 'and the first reads the second write');

    my @all = $a->find('shared');
    is_deeply(\@all, [ 'one', 'two' ],
	      'both writes are in the journal, in order');

    # Every line is complete: no interleaving left a partial record.
    for my $l (grep { /\S/ } split(/\n/, slurp($file))) {
	like($l, qr/^shared\s+\S+$/, "complete line: [$l]");
    }
};


# ---------------------------------------------------------------------
# 10. the hash interface
#
# The documented alternative to the method calls, and the one the
# SYNOPSIS shows.  It has to agree with the methods.
# ---------------------------------------------------------------------
subtest 'the tied hash agrees with the methods' => sub {
    my $file = fresh_file();

    my %db = ();
    tie %db, 'Tie::JournaledFile', { file => $file };

    $db{ rudo } = 'teddy bear';
    $db{ ken  } = 'north fox';

    is($db{ rudo }, 'teddy bear', 'read back through the hash');
    is($db{ ken  }, 'north fox',  'and the other one');
    is($db{ nope }, undef,        'a missing key is undef');

    untie %db;

    my $obj = new Tie::JournaledFile { file => $file };
    is($obj->FETCH('rudo'), 'teddy bear',
       'and the method interface sees the same');
};


# ---------------------------------------------------------------------
# 11. every key, once
#
# get_all_values_as_hash_ref() is how the whole store is walked.  A key
# written three times is still one key.
# ---------------------------------------------------------------------
subtest 'the whole store can be walked' => sub {
    my $file = fresh_file();
    my $db   = new Tie::JournaledFile { file => $file };

    $db->STORE('a', '1');
    $db->STORE('b', '2');
    $db->STORE('a', '3');
    $db->STORE('c', '4');

    my $all = $db->get_all_values_as_hash_ref();
    is(ref($all), 'HASH', 'a hash reference comes back');

    my @key = sort keys %$all;
    is_deeply(\@key, [ qw(a b c) ], 'three distinct keys, not four entries');

    # The values for a repeated key are all there.
    is(ref($all->{ a }), 'ARRAY', 'the values arrive as an ARRAY_REF');
    is_deeply($all->{ a }, [ '1', '3' ], 'both writes for "a"');
    is_deeply($all->{ b }, [ '2' ],      'and the single write for "b"');
};

done_testing();
