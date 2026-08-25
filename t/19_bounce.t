#-*- perl -*-
#
# Mail::Bounce, against the corpus that is already in the tree.
#
# regress/errormails holds thirty-four real bounces, collected from the
# mailers that were sending them: qmail, exim, Postfix, sendmail, SIMS,
# InterScan, Notes, and a row of Japanese providers.  There is a harness
# for it in regress/errormails/Makefile, and it prints "ok" or "fail"
# per file and exits zero either way, so under make(1) the whole set has
# always looked like a pass.
#
# Which addresses this can pull out of a bounce decides who gets removed
# from a list.  Get it wrong in one direction and a dead address stays
# on the roster forever; in the other, a live subscriber is dropped
# because their provider worded a warning like a rejection.
#
# So: the twenty-nine that parse today are pinned by name, and the five
# that do not are named as well.  A gap nobody can list is a gap nobody
# closes.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);
use FileHandle;

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use FML::Message;
use Mail::Bounce;

my $DIR = 'regress/errormails';

plan skip_all => "no bounce corpus at $DIR" unless -d $DIR;

# The addresses each bounce is expected to yield.  Written out rather
# than recorded from a run, so that a change in the answer is visible as
# a change to this table.
my %EXPECT = (
    'biglobe.ne.jp'      => [ 'rudo@xxx.biglobe.ne.jp' ],
    'e500'               => [ 'rudo@nuinui.net' ],
    'exim'               => [ 'rudo@nuinui.net' ],
    'freeserve.ne.jp'    => [ 'errorperson@fb.freeserve.ne.jp' ],
    'gatekeeper'         => [ 'rudo@nuinui.net' ],
    'goo.ne.jp'          => [ 'user@mail.goo.ne.jp' ],
    'intermail'          => [ 'kenken@mb.nuinui.net' ],
    'interscan'          => [ 'account@domain.co.jp' ],
    'jp-r.ne.jp'         => [ '****@jp-r.ne.jp' ],
    'lotus'              => [ 'xxxxxxxx@chuo.tokyo.nuinui.net' ],
    'mailsweeper'        => [ 'rudo@nuinui.net' ],
    'nifty.ne.jp'        => [ 'RUDO0000@nifty.ne.jp' ],
    'norton'             => [ 'rudo@nuinui.net' ],
    'odn.ne.jp'          => [ 'XXX12345@pop06.odn.ne.jp' ],
    'pakeo.ne.jp'        => [ '*********@i.pakeo.ne.jp' ],
    'pdx.ne.jp'          => [ '***********@pdx.ne.jp' ],
    'postfix-verp'       => [ 'rudo@nuinui.net' ],
    'postfix19991231'    => [ 'rudo@nuinui.net' ],
    'postfix19991231-mp' => [ 'uja@beth.fml.org' ],
    'sims2'              => [ 'rudo@nuinui.net' ],
    'smail'              => [ 'rudo@nuinui.net' ],
    'smi-8.6'            => [ 'rudo@nuinui.net' ],
    'smtp32'             => [ '*******@docomo.ne.jp' ],
    'smtpsvc'            => [ 'xxxxx@email.msn.com' ],
    'webtv.ne.jp'        => [ 'errorperson@webtv.ne.jp' ],
    'yahoo.com'          => [ 'xxx@yahoo.com' ],
);

# The ones that yield more than one address.  Kept apart because the
# count is the interesting part: a bounce carrying eleven recipients has
# to give up all eleven, or ten subscribers stay on a list they cannot
# be delivered to.
my %EXPECT_MANY = (
    'dsn'   => 2,
    'sims1' => 2,
    'qmail' => 11,
);

# Bounces this cannot read.  Named, so that the list is a to-do rather
# than a silence.  The Makefile harness prints "fail" for each of these
# and exits zero.
my @NOT_PARSED = qw(fetchmail karame.net nms354 sky.tkk.ne.jp umin.ac.jp);


# Descriptions: analyse the bounce in $file and return the bouncer.
#    Arguments: STR($file)
# Side Effects: none
# Return Value: OBJ or undef
sub analyze
{
    my ($file) = @_;
    my $path   = "$DIR/$file";

    return undef unless -f $path;

    my $fh = new FileHandle $path;
    return undef unless defined $fh;

    my $msg = FML::Message->parse( { fd => $fh } );
    my $b   = new Mail::Bounce;
    $b->analyze($msg);

    return $b;
}


# ---------------------------------------------------------------------
# 1. the corpus is where it is expected to be
# ---------------------------------------------------------------------
subtest 'the corpus is present and accounted for' => sub {
    opendir(my $dh, $DIR) or die "cannot read $DIR: $!";
    my @file = sort grep { !/^\./ && $_ ne 'Makefile' && -f "$DIR/$_" }
	readdir($dh);
    closedir($dh);

    cmp_ok(scalar(@file), '>=', 30,
	   sprintf("%d bounces in the corpus", scalar(@file)));

    # Every file is accounted for by one of the three lists above, so a
    # bounce added to the corpus cannot sit there unexercised.
    my %known = (%EXPECT, %EXPECT_MANY, map { $_ => 1 } @NOT_PARSED);
    my @unlisted = grep { !$known{ $_ } } @file;

    is(scalar(@unlisted), 0, 'every bounce in the corpus is listed here')
	or diag("not listed: @unlisted");

    my @missing = grep { !-f "$DIR/$_" } keys %known;
    is(scalar(@missing), 0, 'and every listed bounce is in the corpus')
	or diag("listed but absent: @missing");
};


# ---------------------------------------------------------------------
# 2. each bounce gives up the address it is about
# ---------------------------------------------------------------------
subtest 'the single-recipient bounces are read correctly' => sub {
    for my $file (sort keys %EXPECT) {
	my $b = analyze($file);
	ok($b, "$file: analysed") or next;

	my @got = sort $b->address_list();
	is_deeply(\@got, [ sort @{ $EXPECT{ $file } } ], "$file: $got[0]");
    }
};


# ---------------------------------------------------------------------
# 3. a bounce about several recipients gives up all of them
#
# qmail folds eleven failures into one message.  Reading only the first
# leaves ten dead addresses on the list, and the next post generates the
# same bounce again.
# ---------------------------------------------------------------------
subtest 'a multi-recipient bounce gives up every address' => sub {
    for my $file (sort keys %EXPECT_MANY) {
	my $b = analyze($file);
	ok($b, "$file: analysed") or next;

	my @got = $b->address_list();
	is(scalar(@got), $EXPECT_MANY{ $file },
	   sprintf("%s: %d addresses", $file, $EXPECT_MANY{ $file }));

	# No address may appear twice: each is a separate decision about
	# a separate subscriber.
	my %seen = ();
	$seen{ $_ }++ for @got;
	my @dup = grep { $seen{ $_ } > 1 } keys %seen;
	is(scalar(@dup), 0, "$file: no address is reported twice")
	    or diag("duplicated: @dup");
    }
};


# ---------------------------------------------------------------------
# 4. every address comes with a reason
#
# The address alone is not enough to act on: a mailbox that is full is
# not a mailbox that does not exist, and fml8 counts them differently.
# ---------------------------------------------------------------------
subtest 'each address carries a status and a reason' => sub {
    my $checked = 0;

    for my $file (sort keys %EXPECT, sort keys %EXPECT_MANY) {
	my $b = analyze($file) or next;

	for my $addr ($b->address_list()) {
	    $checked++;

	    my $status = $b->status($addr);
	    my $reason = $b->reason($addr);

	    ok(defined $status, "$file: $addr has a status");
	    ok(defined $reason, "$file: $addr has a reason");

	    # Something has to be there.  An address with an empty status
	    # and an empty reason is an address nothing can be decided
	    # about.
	    ok((defined $status && $status =~ /\S/) ||
	       (defined $reason && $reason =~ /\S/),
	       "$file: $addr says why");
	}
    }

    cmp_ok($checked, '>', 30, "checked $checked addresses");
};


# ---------------------------------------------------------------------
# 5. the status codes are DSN codes where there are any
#
# RFC 3463: class.subject.detail.  The first digit is what separates a
# permanent failure from a temporary one, and removing a subscriber on a
# temporary failure is how a full mailbox costs somebody their
# subscription.
# ---------------------------------------------------------------------
subtest 'a status that is present is a DSN status' => sub {
    my $with_status = 0;

    for my $file (sort keys %EXPECT, sort keys %EXPECT_MANY) {
	my $b = analyze($file) or next;

	for my $addr ($b->address_list()) {
	    my $status = $b->status($addr);
	    next unless defined $status && $status =~ /\S/;

	    $with_status++;

	    # "5.x.y" is Mail::Bounce's own placeholder, used by six of
	    # the models: it means "a permanent failure, and the mailer
	    # gave no DSN code".  It is a real answer rather than a
	    # missing one, so it belongs in the pattern.
	    like($status, qr/^[245]\.(?:\d+|x)\.(?:\d+|y)/,
		 "$file: $addr status '$status' is class.subject.detail");
	}
    }

    cmp_ok($with_status, '>', 5,
	   "$with_status addresses came with a DSN status");
};


# ---------------------------------------------------------------------
# 5a. a real DSN code is preserved where the mailer sent one
#
# The placeholder must not be covering for a code that was there to be
# read: the first digit is what separates "gone" from "try again later",
# and fml8 counts those differently.
# ---------------------------------------------------------------------
subtest 'a real DSN code is not replaced by the placeholder' => sub {
    my $b = analyze('qmail');
    ok($b, 'qmail analysed') or return;

    my %status = map { $_ => $b->status($_) } $b->address_list();

    my @real = grep { $status{ $_ } =~ /^[245]\.\d+\.\d+$/ } keys %status;
    cmp_ok(scalar(@real), '>', 0,
	   sprintf("%d of the qmail recipients kept a real code", scalar(@real)));

    # And both classes appear in this one bounce, which is the case that
    # matters: a temporary failure among permanent ones.
    my @temp = grep { $status{ $_ } =~ /^4\./ } keys %status;
    my @perm = grep { $status{ $_ } =~ /^5\./ } keys %status;

    cmp_ok(scalar(@temp), '>', 0, 'a temporary failure is reported as 4.x.x');
    cmp_ok(scalar(@perm), '>', 0, 'and a permanent one as 5.x.x');
};


# ---------------------------------------------------------------------
# 6. what it cannot read
#
# Five of thirty-four.  Named as TODO rather than left out, because the
# harness that already exists prints "fail" for these and exits zero, so
# they have been invisible for as long as they have existed.
# ---------------------------------------------------------------------
subtest 'the bounces that are not understood yet' => sub {
    for my $file (@NOT_PARSED) {
      SKIP: {
	    skip("$file is not in this checkout", 1) unless -f "$DIR/$file";

	    my $b = analyze($file);
	    my @got = $b ? $b->address_list() : ();

	    local $TODO = "no model in Mail::Bounce reads $file yet";
	    cmp_ok(scalar(@got), '>', 0, "$file: an address is extracted");
	}
    }

    # The count is asserted so the gap cannot grow without being noticed,
    # in either direction: a model added here should shorten the list.
    my $unread = 0;
    for my $file (@NOT_PARSED) {
	next unless -f "$DIR/$file";
	my $b = analyze($file);
	$unread++ unless $b && $b->address_list();
    }

    is($unread, scalar(@NOT_PARSED),
       sprintf("still %d bounces unread: %s",
	       scalar(@NOT_PARSED), join(', ', @NOT_PARSED)));
};


# ---------------------------------------------------------------------
# 7. the addresses that come out are addresses
#
# The extracted string is looked up in the member map, so anything the
# map cannot match leaves a dead address subscribed forever.  Whitespace
# is the case that bit: Mail::Header::get() returns a field with its
# newline still attached, Mail::Bounce::Exim passed that straight into
# address_cleanup(), and address_cleanup() stripped brackets, quotes and
# a trailing dot but never whitespace.  So an exim bounce yielded
# "rudo@nuinui.net\n" and removed nobody.
#
# One address here is still malformed and is meant to be: the corpus was
# anonymised by substituting characters, and in regress/errormails/qmail
# line 25 the substitution produced "<xayaxhxaxx@.co.nuinui.net>", a
# domain beginning with a dot.  Mail::Bounce reports faithfully what the
# mailer said, so that one is data rather than a defect.
# ---------------------------------------------------------------------
subtest 'the extracted addresses look like addresses' => sub {
    my @malformed = ();
    my $checked   = 0;

    for my $file (sort keys %EXPECT, sort keys %EXPECT_MANY) {
	my $b = analyze($file) or next;

	for my $addr ($b->address_list()) {
	    $checked++;

	    # Not RFC 5322 -- the corpus is anonymised and full of "*" --
	    # but a local part, an "@", and a domain that begins with a
	    # letter or a digit.
	    push @malformed, "$file: $addr"
		unless $addr =~ /\A[^@\s]+\@[A-Za-z0-9][A-Za-z0-9.\-]*\z/;
	}
    }

    cmp_ok($checked, '>', 30, "checked $checked addresses");

    is_deeply(\@malformed, [ 'qmail: xayaxhxaxx@.co.nuinui.net' ],
	      'the only malformed address is the one the corpus itself carries')
	or diag(join("\n", @malformed));
};


# ---------------------------------------------------------------------
# 7a. no address carries whitespace
#
# Stated on its own because it is the failure that was found, and
# because it is invisible: an address with a newline on the end prints
# identically to one without.
# ---------------------------------------------------------------------
subtest 'no extracted address carries whitespace' => sub {
    my @dirty = ();

    for my $file (sort keys %EXPECT, sort keys %EXPECT_MANY) {
	my $b = analyze($file) or next;

	for my $addr ($b->address_list()) {
	    push @dirty, sprintf("%s: [%s]", $file, _show($addr))
		if $addr =~ /\s/;
	}
    }

    is(scalar(@dirty), 0, 'no leading, trailing or embedded whitespace')
	or diag(join("\n", @dirty));

    # And address_cleanup() strips it whatever is wrapped around it.
    my $b = new Mail::Bounce;
    for my $in ("rudo\@nuinui.net\n", " rudo\@nuinui.net ",
		"<rudo\@nuinui.net>\n", "\"rudo\@nuinui.net\"\n",
		"\trudo\@nuinui.net\r\n") {
	is($b->address_cleanup('t', $in), 'rudo@nuinui.net',
	   sprintf("cleaned: [%s]", _show($in)));
    }
};


# Descriptions: $s with its control characters made visible.
#    Arguments: STR($s)
# Side Effects: none
# Return Value: STR
sub _show
{
    my ($s) = @_;
    $s =~ s/([^\x20-\x7e])/sprintf("\\x%02x", ord($1))/ge;
    return $s;
}


# ---------------------------------------------------------------------
# 8. analysing the same bounce twice gives the same answer
#
# Mail::Bounce walks its models in order and stops at the first that
# matches, so the answer depends on module load order.  It must not
# depend on anything else.
# ---------------------------------------------------------------------
subtest 'the analysis is repeatable' => sub {
    for my $file (qw(qmail dsn postfix19991231 exim)) {
	next unless -f "$DIR/$file";

	my @first  = sort( analyze($file)->address_list() );
	my @second = sort( analyze($file)->address_list() );

	is_deeply(\@second, \@first, "$file: the same answer twice");
    }
};


# ---------------------------------------------------------------------
# 9. a message that is not a bounce yields nothing
#
# Every mail to the error address is put through this, including the
# ordinary ones people send there by mistake.  Extracting an address
# from a non-bounce would unsubscribe somebody who did nothing.
# ---------------------------------------------------------------------
subtest 'an ordinary mail is not read as a bounce' => sub {
    use File::Temp qw(tempdir);
    my $tmp = tempdir(CLEANUP => 1);

    my %case = (
	'a plain note' =>
	    "From: taro\@example.jp\n" .
	    "To: elena-admin\@example.jp\n" .
	    "Subject: a question\n" .
	    "\n" .
	    "Could somebody tell me how to unsubscribe?\n",
	'an empty body' =>
	    "From: taro\@example.jp\n" .
	    "Subject: (none)\n" .
	    "\n",
	'a mail mentioning an address' =>
	    "From: taro\@example.jp\n" .
	    "Subject: hello\n" .
	    "\n" .
	    "Please add hanako\@example.jp to the list.\n",
    );

    my $n = 0;
    for my $name (sort keys %case) {
	my $path = "$tmp/mail." . $n++;
	open(my $wh, '>', $path) or die $!;
	print $wh $case{ $name };
	close($wh);

	my $fh  = new FileHandle $path;
	my $msg = FML::Message->parse( { fd => $fh } );
	my $b   = new Mail::Bounce;
	eval { $b->analyze($msg) };

	is($@, '', "$name: analysing does not die") or diag($@);

	my @got = $b->address_list();
	is(scalar(@got), 0, "$name: no address extracted")
	    or diag("extracted: @got");
    }
};

done_testing();
