#-*- perl -*-
#
# Command mail body handling.
#
# Mail::Message::message_text() returns the part as it stands on the
# wire, so a command mail sent with Content-Transfer-Encoding: base64
# used to give the command loop one line of base64.  Nothing matched a
# command, so the mail was isolated rather than obeyed.  That is fml8
# issue #5.
#
# The encoding was known all along: encoding_mechanism() reports it
# correctly.  The command loop simply never asked.
#

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

# cpan/lib and img/lib go on the end of @INC, so that a module the host
# has installed wins over the bundled copy.  It used to matter more than
# that: cpan/lib carried File::Spec 0.7, which lacks splitdir() and
# splitpath(), and putting it first broke fml8 and prove(1) alike.  That
# copy is gone now, but the order is still the right way round.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Message;
use MIME::Base64 ();
use MIME::QuotedPrint ();
use FML::Process::Command;

my $TMPDIR = tempdir(CLEANUP => 1);
my $SEQ    = 0;

# The command loop only calls logdebug() on $curproc here.
{
    package t::Curproc;
    sub new      { return bless {}, shift }
    sub logdebug { return 1 }
}
my $curproc = t::Curproc->new();

my $COMMANDS = "help\nsubscribe Taro Yamada\n";


# Descriptions: build a mail with the given transfer encoding and
#               return the first text/plain part of it.
sub first_plaintext_part
{
    my ($cte, $payload) = @_;

    my $mail = "From: taro\@example.jp\n"
	     . "Subject: request\n"
	     . "MIME-Version: 1.0\n"
	     . "Content-Type: text/plain; charset=us-ascii\n"
	     . ($cte ? "Content-Transfer-Encoding: $cte\n" : "")
	     . "\n"
	     . $payload;

    # Mail::Message->parse() wants a real handle, not an in-memory one.
    my $path = sprintf("%s/mail.%d", $TMPDIR, $SEQ++);
    open(my $wh, '>', $path) or die "cannot write $path: $!";
    print $wh $mail;
    close($wh);

    open(my $rh, '<', $path) or die "cannot read $path: $!";
    my $msg = Mail::Message->parse({ fd => $rh });

    return $msg->whole_message_body->find_first_plaintext_message();
}


# ---------------------------------------------------------------------
# 1. the encoding is visible on the part
# ---------------------------------------------------------------------
subtest 'encoding_mechanism() reports the transfer encoding' => sub {
    my $b64 = first_plaintext_part('base64',
				   MIME::Base64::encode_base64($COMMANDS));
    is($b64->encoding_mechanism(), 'base64', 'base64 is reported');

    my $qp = first_plaintext_part('quoted-printable',
				  MIME::QuotedPrint::encode_qp($COMMANDS));
    is($qp->encoding_mechanism(), 'quoted-printable', 'qp is reported');
};


# ---------------------------------------------------------------------
# 2. the raw text really is undecoded (this is what bit issue #5)
# ---------------------------------------------------------------------
subtest 'message_text() hands back the wire form' => sub {
    my $part = first_plaintext_part('base64',
				    MIME::Base64::encode_base64($COMMANDS));
    my $raw  = $part->message_text();

    unlike($raw, qr/subscribe/, 'the raw body is not readable as commands');
    like($raw, qr/^[A-Za-z0-9+\/=\s]+$/, 'the raw body is still base64');
};


# ---------------------------------------------------------------------
# 3. the command loop decodes before splitting into lines
# ---------------------------------------------------------------------
subtest 'command lines survive every transfer encoding' => sub {
    my @want = ('help', 'subscribe Taro Yamada');

    my %case = (
	'base64' =>
	    first_plaintext_part('base64',
				 MIME::Base64::encode_base64($COMMANDS)),
	'quoted-printable' =>
	    first_plaintext_part('quoted-printable',
				 MIME::QuotedPrint::encode_qp($COMMANDS)),
	# 7bit and 8bit are not transformations, so they must pass through
	# untouched rather than being "decoded".
	'7bit'    => first_plaintext_part('7bit', $COMMANDS),
	'8bit'    => first_plaintext_part('8bit', $COMMANDS),
	'(none)'  => first_plaintext_part('',     $COMMANDS),
    );

    for my $cte (sort keys %case) {
	my $lines = FML::Process::Command::_command_lines($curproc,
							  $case{ $cte });
	is_deeply($lines, \@want, "$cte: commands are readable");
    }
};


# ---------------------------------------------------------------------
# 4. a body with nothing in it must not blow up
# ---------------------------------------------------------------------
subtest 'an empty body yields no commands' => sub {
    my $part  = first_plaintext_part('base64', MIME::Base64::encode_base64(""));
    my $lines = FML::Process::Command::_command_lines($curproc, $part);

    is(ref($lines), 'ARRAY', 'still an ARRAY_REF');
    is(scalar(@$lines), 0,   'no command lines');
};

done_testing();
