#-*- perl -*-
#
# The body filter, and the rule that rejected almost all mail.
#
# reject_not_iso2022jp_japanese_string was in the default rule set.  Its
# name says it rejects Japanese that is not ISO-2022-JP; what it does is
# call is_iso2022jp_string() on the first paragraph and croak unless it
# says yes, and that says no for every non-ASCII body whatever language
# it is in.  So UTF-8 French was refused for being Japanese in the wrong
# encoding.
#
# When it was written, Japanese mail was ISO-2022-JP and the rule was
# nearly free.  It is now UTF-8, so the default rejected nearly
# everything.  Article relay and spooling do no charset conversion at
# all, so accepting other charsets costs nothing.
#
# The rule itself is not removed and is not broken: an ML that wants
# ISO-2022-JP only can put it back with
#
#	article_text_plain_filter_rules += reject_not_iso2022jp_japanese_string
#
# so this file checks both halves -- that it is not on by default, and
# that it still works when it is asked for.  Changing a default is a
# policy change rather than a bug fix, and a policy change is worth
# pinning from both sides.
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

use Mail::Message;
use FML::Filter::TextPlain;

my $TMPDIR = tempdir(CLEANUP => 1);
my $SEQ    = 0;

# "こんにちは" as octets, in each encoding.
my %HELLO = (
    'utf-8'       => "\xe3\x81\x93\xe3\x82\x93\xe3\x81\xab\xe3\x81\xa1\xe3\x81\xaf",
    'euc-jp'      => "\xa4\xb3\xa4\xf3\xa4\xcb\xa4\xc1\xa4\xcf",
    'iso-2022-jp' => "\x1b\x24\x42\x24\x33\x24\x73\x24\x4b\x24\x41\x24\x4f\x1b\x28\x42",
);


# Descriptions: build a mail with $body and return the Mail::Message.
#               Mail::Message->parse() wants a real handle, so the mail
#               goes through a file.
#    Arguments: STR($body) STR($charset)
# Side Effects: writes a temporary file.
# Return Value: OBJ
sub mail_with_body
{
    my ($body, $charset) = @_;
    $charset ||= 'us-ascii';

    my $mail = "From: taro\@example.jp\n"
	     . "Subject: hello\n"
	     . "MIME-Version: 1.0\n"
	     . "Content-Type: text/plain; charset=$charset\n"
	     . "\n"
	     . $body;

    my $path = sprintf("%s/mail.%d", $TMPDIR, $SEQ++);
    open(my $wh, '>', $path) or die "cannot write $path: $!";
    binmode($wh);
    print $wh $mail;
    close($wh);

    open(my $rh, '<', $path) or die "cannot read $path: $!";
    binmode($rh);
    my $msg = Mail::Message->parse({ fd => $rh });

    return $msg->whole_message_body();
}


# Descriptions: run the filter over $body and report the error, if any.
#    Arguments: STR($body) STR($charset) ARRAY_REF($rules)
# Side Effects: none
# Return Value: STR
sub filter_error
{
    my ($body, $charset, $rules) = @_;

    my $filter = new FML::Filter::TextPlain;
    $filter->set_rules($rules) if defined $rules;

    $filter->body_check(mail_with_body($body, $charset));

    my $e = $filter->error();

    return defined $e ? $e : '';
}


# ---------------------------------------------------------------------
# 1. what the default rule set is
#
# Read off the object rather than out of the source, so that the thing
# asserted is the thing that runs.
# ---------------------------------------------------------------------
subtest 'the default rules are the declared ones' => sub {
    my $filter = new FML::Filter::TextPlain;
    my $rules  = $filter->{ _rules };

    is(ref($rules), 'ARRAY', 'the object carries a rule list');

    my %has = map { $_ => 1 } @$rules;

    ok(!$has{ reject_not_iso2022jp_japanese_string },
       'reject_not_iso2022jp_japanese_string is NOT on by default');

    # Everything else it used to run alongside is still there.  The
    # change was to one rule, not to the filter.
    for my $rule (qw(reject_null_mail_body
		     reject_one_line_message
		     reject_old_fml_command_syntax
		     reject_invalid_fml_command_syntax
		     reject_japanese_command_syntax
		     reject_ms_guid)) {
	ok($has{ $rule }, "$rule is still on by default");
    }

    # And every rule named is a method that exists.  A typo in the list
    # is skipped silently by body_check(), which is a rule that never
    # runs rather than an error.
    for my $rule (@$rules) {
	can_ok($filter, $rule);
    }
};


# ---------------------------------------------------------------------
# 2. mail in the charsets people actually send
#
# The point of the change.
# ---------------------------------------------------------------------
subtest 'Japanese mail is accepted whatever its charset' => sub {
    for my $charset (sort keys %HELLO) {
	my $body = $HELLO{ $charset } . "\n\nthat is all.\n";
	my $err  = filter_error($body, $charset);

	is($err, '', "$charset: accepted");
    }
};


# ---------------------------------------------------------------------
# 3. and mail that is not Japanese at all
#
# This is the case whose refusal made no sense even on the old reading:
# French has nothing to do with ISO-2022-JP.
# ---------------------------------------------------------------------
subtest 'non-Japanese mail is accepted' => sub {
    my %body = (
	'French UTF-8'  => "caf\xc3\xa9 cr\xc3\xa8me, s'il vous pla\xc3\xaet.\n\nmerci.\n",
	'German UTF-8'  => "Gr\xc3\xbc\xc3\x9fe aus M\xc3\xbcnchen.\n\ndanke.\n",
	'Russian UTF-8' => "\xd0\xbf\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82\n\n\xd0\xbf\xd0\xbe\xd0\xba\xd0\xb0\n",
	'Korean UTF-8'  => "\xed\x95\x9c\xea\xb5\xad\xec\x96\xb4\n\n\xea\xb0\x90\xec\x82\xac\n",
	'plain ASCII'   => "hello, world.\n\nregards.\n",
    );

    for my $name (sort keys %body) {
	is(filter_error($body{ $name }, 'utf-8'), '', "$name: accepted");
    }
};


# ---------------------------------------------------------------------
# 4. the rule still works when it is asked for
#
# Turning a rule off by default is only defensible if the rule is intact,
# so that an ML which wants it gets what it asks for.
# ---------------------------------------------------------------------
subtest 'the rule still rejects when enabled explicitly' => sub {
    my $only = [ 'reject_not_iso2022jp_japanese_string' ];

    # ISO-2022-JP and ASCII pass it.
    is(filter_error($HELLO{'iso-2022-jp'} . "\n\nend.\n", 'iso-2022-jp', $only),
       '', 'ISO-2022-JP passes the rule');
    is(filter_error("hello, world.\n\nend.\n", 'us-ascii', $only),
       '', 'ASCII passes the rule');

    # Everything else does not.
    for my $charset (qw(utf-8 euc-jp)) {
	isnt(filter_error($HELLO{ $charset } . "\n\nend.\n", $charset, $only),
	     '', "$charset is rejected when the rule is on");
    }

    # Including mail that is not Japanese, which is what the name hides.
    isnt(filter_error("caf\xc3\xa9 cr\xc3\xa8me\n\nmerci.\n", 'utf-8', $only),
	 '', 'and so is UTF-8 French, despite the name of the rule');
};


# ---------------------------------------------------------------------
# 5. the rules that stayed on still reject what they are for
#
# Loosening one default must not have loosened the rest.
# ---------------------------------------------------------------------
subtest 'the remaining default rules still bite' => sub {
    # An empty body.
    isnt(filter_error("", 'us-ascii'), '', 'an empty body is rejected');
    isnt(filter_error("\n\n", 'us-ascii'), '',
	 'a body of nothing but newlines is rejected');

    # A mail whose whole body is an fml4-era command.  These are people
    # sending "# subscribe" to the article address by mistake, and
    # distributing it to the list helps nobody.
    isnt(filter_error("# subscribe Taro Yamada\n", 'us-ascii'), '',
	 'an old-style fml command as the whole body is rejected');

    isnt(filter_error("% echo hello\n", 'us-ascii'), '',
	 'the invalid command syntax is rejected');

    # And an ordinary article is not caught by any of them.
    is(filter_error("Hello everyone,\n\nthe meeting is at 10:00.\n\n-- taro\n",
		    'us-ascii'),
       '', 'an ordinary article is accepted');
};


# ---------------------------------------------------------------------
# 6. a body the filter cannot read is not an accept
#
# find_first_plaintext_message() returns nothing for a text/html only
# mail, and body_check() returns early.  Worth pinning: "no text part"
# and "the text part is fine" have to stay distinguishable.
# ---------------------------------------------------------------------
subtest 'a mail with no text part is not judged' => sub {
    my $filter = new FML::Filter::TextPlain;

    my $mail = "From: taro\@example.jp\n"
	     . "Subject: html only\n"
	     . "MIME-Version: 1.0\n"
	     . "Content-Type: text/html; charset=us-ascii\n"
	     . "\n"
	     . "<html><body>hello</body></html>\n";

    my $path = "$TMPDIR/html.mail";
    open(my $wh, '>', $path) or die "cannot write $path: $!";
    print $wh $mail;
    close($wh);

    open(my $rh, '<', $path) or die "cannot read $path: $!";
    my $msg = Mail::Message->parse({ fd => $rh });

    my $r = $filter->body_check($msg->whole_message_body());

    is($r, undef, 'body_check() returns undef rather than a verdict');
    my $e = $filter->error();
    ok(!defined $e || $e eq '', 'and records no error');
};


# ---------------------------------------------------------------------
# 7. an unknown rule name does not fail open silently
#
# body_check() skips a rule the object cannot do.  That is a rule that
# never runs, which looks exactly like a rule that passed.  Recorded so
# the behaviour is known; it is not being changed here.
# ---------------------------------------------------------------------
subtest 'a rule name that does not exist is skipped' => sub {
    my $err = filter_error("hello\n\nworld\n", 'us-ascii',
			   [ 'reject_no_such_rule_at_all' ]);

    is($err, '', 'an unknown rule name is silently skipped');

    # Which is why t/11 checks every default rule name resolves, above.
    my $filter = new FML::Filter::TextPlain;
    ok(!$filter->can('reject_no_such_rule_at_all'),
       'and the name really is not a method');
};

done_testing();
