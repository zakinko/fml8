#-*- perl -*-
#
# Constructs that must not come back.
#
# fml8 is a Perl 5 rewrite of a Perl 4 program, and it was written
# against a perl of the late nineties.  Several things that were normal
# then are now either fatal or undefined, and they keep reappearing
# because the surrounding code still looks like the code they came from.
#
# Each guard here corresponds to something that was actually found in
# this tree, not to a list of general good practice:
#
#   defined(@array), defined(%hash)   fatal since perl 5.22
#   $*                                removed in perl 5.30
#   $[                                removed in perl 5.30
#   my $x = ... if COND               undefined behaviour, perlsyn
#   $str |= 'literal'                 string bitwise or, meant ||=
#   open($fh, $fh)                    symbolic reference, fatal under strict
#
# The last two are the shapes of two bugs fixed here: the charset that
# came out as 'o}s-jp' and the checksum routine that could never run.
# A comment explains why the old code was wrong; this is what stops it
# being written again.
#
# The CI workflow greps for the first two.  This file is the same
# guarantee where a developer will meet it, running prove(1) rather than
# waiting for a push, and it covers the rest.
#

use strict;
use warnings;
use Test::More;
use vars qw($TODO);

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

my @ROOT = grep { -d $_ } qw(fml cpan/lib t);

plan skip_all => "no source tree here" unless @ROOT;


# Descriptions: every perl source file under @ROOT.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub all_sources
{
    my @found = ();

    my $walk;
    $walk = sub {
	my ($dir) = @_;
	opendir(my $dh, $dir) or return;
	my @e = sort grep { !/^\.\.?$/ } readdir($dh);
	closedir($dh);

	for my $e (@e) {
	    my $path = "$dir/$e";
	    if (-l $path)            { next }
	    elsif (-d $path)         { $walk->($path) }
	    elsif ($path =~ /\.(?:pm|pl|t)$/) { push @found, $path }
	}
    };
    $walk->($_) for @ROOT;

    return \@found;
}


# Descriptions: the lines of $path as (line number, code) pairs, with
#               comments, POD and quoted strings removed.
#
#               Removing the quoted parts matters: "find paragraph
#               boundary if could" is a default message in Mail::Message
#               and would otherwise be read as a statement modifier.
#    Arguments: STR($path)
# Side Effects: none
# Return Value: ARRAY_REF
sub code_lines
{
    my ($path) = @_;

    open(my $fh, '<', $path) or return [];
    my @out    = ();
    my $in_pod = 0;
    my $n      = 0;

    while (my $line = <$fh>) {
	$n++;
	chomp($line);

	if    ($line =~ /^=cut\b/)       { $in_pod = 0; next }
	elsif ($line =~ /^=[a-zA-Z]\w*/) { $in_pod = 1; next }
	next if $in_pod;

	# A whole-line comment says nothing about what runs.
	next if $line =~ /^\s*#/;

	# Blank out the contents of quoted strings, keeping the quotes so
	# the shape of the statement survives.
	my $code = $line;
	$code =~ s/'[^']*'/''/g;
	$code =~ s/"[^"]*"/""/g;

	# And a trailing comment.
	$code =~ s/\s#[^"']*$//;

	push @out, [ $n, $code ];
    }
    close($fh);

    return \@out;
}


my $SOURCES = all_sources();


# Descriptions: report every place $re matches, over the files whose
#               path matches $only (all of them if $only is not given).
#
#               The scope matters.  fml/ is ours and is held to all of
#               these.  cpan/lib is a vendor drop where the answer to a
#               defect is a newer release rather than an edit, and t/
#               contains deliberate examples of the very lines being
#               searched for -- t/07 runs the old open() form on purpose
#               to show that it dies.
#    Arguments: CODE($re) STR($only)
# Side Effects: none
# Return Value: ARRAY_REF
sub scan_for
{
    my ($re, $only) = @_;
    my @hit = ();

    for my $path (@$SOURCES) {
	next if defined $only && $path !~ $only;

	for my $pair (@{ code_lines($path) }) {
	    my ($n, $code) = @$pair;
	    push @hit, "$path:$n: $code" if $code =~ $re;
	}
    }

    return \@hit;
}

# Our own code, as opposed to the vendor drops and the tests.
my $OURS = qr{^fml/};


# ---------------------------------------------------------------------
# 0. the scan is looking at something
#
# A guard that silently walks an empty list passes forever.
# ---------------------------------------------------------------------
subtest 'there are sources to scan' => sub {
    cmp_ok(scalar(@$SOURCES), '>', 300,
	   sprintf("found %d source files", scalar(@$SOURCES)));

    my $lines = 0;
    $lines += scalar(@{ code_lines($_) }) for @$SOURCES;
    cmp_ok($lines, '>', 20_000, "and $lines lines of code in them");

    # The comment stripping must not be so keen that nothing is left.
    my ($sample) = grep { m{fml/lib/FML/Command\.pm$} } @$SOURCES;
    ok($sample, 'FML/Command.pm is among them');
    my @sub = grep { $_->[1] =~ /^sub\s+\w+/ } @{ code_lines($sample) };
    cmp_ok(scalar(@sub), '>', 5, 'and its subs survive the stripping');
};


# ---------------------------------------------------------------------
# 1. defined(@array) and defined(%hash)
#
# Deprecated in 5.6, fatal in 5.22.  cpan/lib/File/MMagic carried one,
# which is how it came out that nothing had loaded that file in years.
# ---------------------------------------------------------------------
subtest 'defined(@array) / defined(%hash) is gone' => sub {
    my $hit = scan_for(qr/defined\s*\(?\s*[\@\%][A-Za-z_\$]/);

    is(scalar(@$hit), 0, 'no defined() on an aggregate')
	or diag(join("\n", @$hit));
};


# ---------------------------------------------------------------------
# 2. $* and $[
#
# $* was multiline matching before /m; $[ was the array base.  Both were
# removed in 5.30 and both appear throughout Perl 4 code.
# ---------------------------------------------------------------------
subtest 'the removed punctuation variables are gone' => sub {
    my $star = scan_for(qr/(?<![\$\\])\$\*\s*=/);
    is(scalar(@$star), 0, '$* is not assigned')
	or diag(join("\n", @$star));

    my $base = scan_for(qr/(?<![\$\\])\$\[\s*=/);
    is(scalar(@$base), 0, '$[ is not assigned')
	or diag(join("\n", @$base));
};


# ---------------------------------------------------------------------
# 3. my $x = ... if COND
#
# perlsyn: "the behaviour of a my statement modified with a statement
# modifier conditional is undefined".  The variable is not re-initialised
# when the modifier is false, so it keeps whatever the previous call left
# in it -- which on a long lived process is another user's data.
#
# Eight of these were rewritten here.  It is harmless on the perl in
# front of us, which is exactly why it must be caught by a machine
# rather than by reading.
# ---------------------------------------------------------------------
my $RE_MY_IF = qr/
    ^\s*my\s+                      # a declaration
    (?:\([^)]*\)|[\$\@\%]\w+)      # one variable or a list
    \s*=                           # being initialised
    [^;]*?                         # by anything
    \s\b(?:if|unless)\b            # with a statement modifier on it
    [^;]*;                         # to the end of the statement
/x;

subtest 'no "my $x = ... if COND"' => sub {
    my $hit = scan_for($RE_MY_IF, $OURS);

    is(scalar(@$hit), 0, 'every my declaration in fml/ is unconditional')
	or diag(join("\n", @$hit));
};


# ---------------------------------------------------------------------
# 3a. the same thing in the bundled modules
#
# cpan/lib is a vendor drop: the repair for a defect there is a newer
# release, not an edit, so this is recorded rather than failed.  It is
# not hidden either -- MIME::Lite::HTML is reached through
# Mail::Message::Compose, so this is code fml8 can run.
# ---------------------------------------------------------------------
subtest 'the bundled modules are checked too, and recorded' => sub {
    my $hit = scan_for($RE_MY_IF, qr{^cpan/lib/});

    {
	local $TODO = 'vendor drops are fixed by updating them, not by editing';
	is(scalar(@$hit), 0, 'no "my $x = ... if COND" under cpan/lib');
    }

    diag(sprintf("cpan/lib carries %d of them:\n%s",
		 scalar(@$hit), join("\n", @$hit))) if @$hit;
};


# ---------------------------------------------------------------------
# 4. $str |= 'literal'
#
# "$out_code |= 'euc-jp'" is a bitwise or of two strings, not a default
# assignment.  'jis' | 'euc-jp' is 'o}s-jp', which matches no charset
# name, so the conversion was skipped and the caller got its input back
# unchanged.  ||= is what was meant, in all three places it appeared.
#
# The lookbehind is the whole point: ||= contains |=.
# ---------------------------------------------------------------------
subtest 'no string bitwise-or where a default was meant' => sub {
    my $hit = scan_for(qr/(?<![\|\$])\|=\s*(?:''|"")/, $OURS);

    is(scalar(@$hit), 0, 'no |= against a string literal')
	or diag(join("\n", @$hit));

    # The reason it is worth guarding: show what the old line computed.
    my $bad = 'jis' | 'euc-jp';
    isnt($bad, 'jis',    '|= does not leave the left side alone');
    isnt($bad, 'euc-jp', '|= is not a default assignment either');
    unlike($bad, qr/^(?:jis|sjis|euc)(?:[-_]jp)?$/i,
	   'and what it produces matches no charset name');
};


# ---------------------------------------------------------------------
# 5. open($fh, $fh)
#
# Mail::Message::Checksum::cksum2() passed the file name as both the
# handle and the path.  Perl reads the first argument as a symbolic
# filehandle reference, which "use strict refs" makes fatal, so the
# routine died on every call.
# ---------------------------------------------------------------------
subtest 'no open() using one variable as both handle and path' => sub {
    my $hit = scan_for(qr/open\s*\(?\s*(\$[A-Za-z_]\w*)\s*,\s*\1\s*[,\)]/,
		       $OURS);

    is(scalar(@$hit), 0, 'no open($x, $x)')
	or diag(join("\n", @$hit));
};


# ---------------------------------------------------------------------
# 5a. the scan must see the files grep(1) refuses to read
#
# Three modules under fml/lib are EUC-JP, and grep(1) decides they are
# binary and skips them without saying so.  The CI workflow greps, so
# those three have never been checked by it -- and one of them,
# Mail::Message::Language::Japanese::Subject, is the module that still
# carried "use Jcode" when everything else had stopped.  A guard that
# silently cannot see part of the tree is worse than no guard, because
# it reports success.
#
# This file reads with perl and no encoding layer, so it sees octets and
# has no such blind spot.  Prove that rather than assume it.
# ---------------------------------------------------------------------
subtest 'the EUC-JP modules are scanned, not skipped' => sub {
    my @euc = grep {
	my $path = $_;
	my $seen = 0;
	if (open(my $fh, '<', $path)) {
	    local $/ = undef;
	    binmode($fh);
	    my $src = <$fh>;
	    close($fh);
	    # A high octet outside a UTF-8 sequence: what makes grep(1)
	    # call the file binary.
	    $seen = 1 if $src =~ /[\x80-\xff]/;
	}
	$seen;
    } grep { m{^fml/lib/} } @$SOURCES;

    cmp_ok(scalar(@euc), '>=', 3,
	   sprintf("found %d modules with non-ASCII octets: %s",
		   scalar(@euc), join(', ', @euc)));

    # Each of them has to yield code lines, not an empty list.
    for my $path (@euc) {
	my $lines = code_lines($path);
	cmp_ok(scalar(@$lines), '>', 10, "$path: read $path as code");

	my @sub = grep { $_->[1] =~ /^sub\s+\w+/ } @$lines;
	cmp_ok(scalar(@sub), '>', 0, "$path: its subs are visible");
    }
};


# ---------------------------------------------------------------------
# 6. the guards can actually see something
#
# Every scan above returns an empty list, which is also what a scan with
# a mistake in it returns.  Run each pattern against a line that is
# known to be wrong and check it is caught.
# ---------------------------------------------------------------------
subtest 'each pattern catches the thing it is looking for' => sub {
    my %sample = (
	'defined(@array)'   => [ 'defined(@foo)',
				 qr/defined\s*\(?\s*[\@\%][A-Za-z_\$]/ ],
	'defined %hash'     => [ '    if (defined %ENV) { }',
				 qr/defined\s*\(?\s*[\@\%][A-Za-z_\$]/ ],
	'$* assignment'     => [ '    $* = 1;',
				 qr/(?<![\$\\])\$\*\s*=/ ],
	'$[ assignment'     => [ '    $[ = 1;',
				 qr/(?<![\$\\])\$\[\s*=/ ],
	'my $x = ... if'    => [ '    my $rcpt = $args->{ x } if defined $y;',
				 qr/^\s*my\s+(?:\([^)]*\)|[\$\@\%]\w+)\s*=[^;]*?\s\b(?:if|unless)\b[^;]*;/ ],
	'my ($a) = ... if'  => [ '    my ($a) = $b if $c;',
				 qr/^\s*my\s+(?:\([^)]*\)|[\$\@\%]\w+)\s*=[^;]*?\s\b(?:if|unless)\b[^;]*;/ ],
	'|= literal'        => [ '    $out_code |= "";',
				 qr/(?<![\|\$])\|=\s*(?:''|"")/ ],
	'open($f, $f)'      => [ '    if (open($file, $file)) {',
				 qr/open\s*\(?\s*(\$[A-Za-z_]\w*)\s*,\s*\1\s*[,\)]/ ],
    );

    for my $name (sort keys %sample) {
	my ($line, $re) = @{ $sample{ $name } };
	like($line, $re, "caught: $name");
    }

    # And the patterns that have to stay quiet on correct code.
    my %ok = (
	'||= literal'       => [ '    $out_code ||= "";',
				 qr/(?<![\|\$])\|=\s*(?:''|"")/ ],
	'open($fh, "<", $f)' => [ '    if (open($fh, "<", $file)) {',
				 qr/open\s*\(?\s*(\$[A-Za-z_]\w*)\s*,\s*\1\s*[,\)]/ ],
	'a plain my'        => [ '    my $rcpt = $args->{ recipient };',
				 qr/^\s*my\s+(?:\([^)]*\)|[\$\@\%]\w+)\s*=[^;]*?\s\b(?:if|unless)\b[^;]*;/ ],
	'defined $scalar'   => [ '    if (defined $foo) { }',
				 qr/defined\s*\(?\s*[\@\%][A-Za-z_\$]/ ],
    );

    for my $name (sort keys %ok) {
	my ($line, $re) = @{ $ok{ $name } };
	unlike($line, $re, "not caught: $name");
    }
};


# ---------------------------------------------------------------------
# 7. everything compiles
#
# The syntax guards above are greps and can only see what they were told
# to look for.  perl itself is the exhaustive check, so run it over the
# modules that need nothing outside the core.  Anything that cannot be
# loaded here is reported rather than counted as a pass.
# ---------------------------------------------------------------------
subtest 'every module compiles or says why not' => sub {
    my @lib = grep { -d $_ } qw(fml/lib cpan/lib img/lib);
    my $inc = join(' ', map { "-I$_" } @lib);

    my @fail    = ();
    my @skipped = ();
    my $ok      = 0;

    for my $path (@$SOURCES) {
	next unless $path =~ m{^fml/lib/.*\.pm$};

	my $out = `perl $inc -I. -c $path 2>&1`;
	if ($? == 0) {
	    $ok++;
	}
	elsif ($out =~ /Can't locate (\S+)/) {
	    push @skipped, "$path (needs $1)";
	}
	else {
	    my ($first) = split(/\n/, $out);
	    push @fail, "$path: $first";
	}
    }

    cmp_ok($ok, '>', 100, "$ok modules compile");
    is(scalar(@fail), 0, 'no module fails to compile for its own reasons')
	or diag(join("\n", @fail));

    # A skip is a module nobody compiled.  Name them so the blind spot
    # cannot grow quietly.
    diag(sprintf("not compiled here (%d): %s",
		 scalar(@skipped), join(', ', @skipped)))
	if @skipped;
};

done_testing();
