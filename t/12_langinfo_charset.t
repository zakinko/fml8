#-*- perl -*-
#
# fml8 issue #8: "Use of uninitialized value $language in lc".
#
# Mail::Message::Charset has three lookup helpers and all three called
# lc() on their argument without asking whether there was one.  The CGI
# path has no "language_hint" in the PCB, so undef reached lc() and every
# hit on menu.cgi logged a warning naming Charset.pm line 254.
#
# There are two halves to it and both are tested here.  The helpers must
# tolerate undef, which is the repair; and langinfo_get_charset() must
# not hand them undef in the first place, which is where the undef came
# from.  Fixing only the first would leave the caller silently choosing
# the empty charset instead of the configured default.
#
# The category names are the real ones -- "cgi", "reply_message",
# "template_file", "log_file" -- since the whole point is that a category
# with no hint behaves like one that has it.
#

use strict;
use warnings;
use Test::More;

BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

use Mail::Message::Charset;
use FML::PCB;
use FML::Process::Utils;

my $CS = new Mail::Message::Charset;

# The categories fml8 asks about.
my @CATEGORY = qw(cgi reply_message template_file log_file
		  file subject_tag);


# A process object with only what langinfo_get_charset() reaches for.
# Inheriting from FML::Process::Utils is what makes this a test of the
# real routine rather than of a copy of it.
{
    package t::Curproc;
    use vars qw(@ISA);
    @ISA = qw(FML::Process::Utils);

    sub new
    {
	my ($self, $config, $pcb) = @_;

	return bless {
	    _config => $config || {},
	    _pcb    => $pcb,
	    _log    => [],
	}, $self;
    }

    sub config   { return $_[0]->{ _config } }
    sub pcb      { return $_[0]->{ _pcb } }
    sub logdebug { push @{ $_[0]->{ _log } }, $_[1]; return 1 }
    sub log      { push @{ $_[0]->{ _log } }, $_[1]; return 1 }
    sub logerror { push @{ $_[0]->{ _log } }, $_[1]; return 1 }
    sub logwarn  { push @{ $_[0]->{ _log } }, $_[1]; return 1 }
}


# Descriptions: run $code with warnings collected rather than printed.
#    Arguments: CODE($code)
# Side Effects: none
# Return Value: ARRAY(ANY, ARRAY_REF)
sub warnings_from
{
    my ($code) = @_;
    my @warn   = ();

    local $SIG{__WARN__} = sub { push @warn, $_[0] };
    my $r = $code->();

    return ($r, \@warn);
}


# ---------------------------------------------------------------------
# 1. the three helpers tolerate undef
#
# The repair itself.  Each used to call lc($_[1]) straight away.
# ---------------------------------------------------------------------
subtest 'the charset helpers do not warn on undef' => sub {
    for my $method (qw(language_to_message_charset
		       language_to_internal_charset
		       message_charset_to_language)) {
	my ($r, $warn) = warnings_from(sub { $CS->$method(undef) });

	is($r, '', "$method(undef) returns the empty string");
	is(scalar(@$warn), 0, "$method(undef) warns about nothing")
	    or diag("warnings: @$warn");
    }
};


# ---------------------------------------------------------------------
# 2. and the empty string, which is the other shape of "no hint"
# ---------------------------------------------------------------------
subtest 'the charset helpers tolerate the empty string too' => sub {
    for my $method (qw(language_to_message_charset
		       language_to_internal_charset
		       message_charset_to_language)) {
	my ($r, $warn) = warnings_from(sub { $CS->$method('') });

	is($r, '', "$method('') returns the empty string");
	is(scalar(@$warn), 0, "$method('') warns about nothing")
	    or diag("warnings: @$warn");
    }
};


# ---------------------------------------------------------------------
# 3. they still answer when there is a hint
#
# A guard that returns early for everything would also stop the warning.
# ---------------------------------------------------------------------
subtest 'the charset helpers still answer a real hint' => sub {
    is($CS->language_to_message_charset('ja'),  'iso-2022-jp', 'ja -> wire');
    is($CS->language_to_internal_charset('ja'), 'euc-jp',      'ja -> internal');
    is($CS->language_to_message_charset('en'),  'us-ascii',    'en -> wire');
    is($CS->message_charset_to_language('iso-2022-jp'), 'ja',  'wire -> ja');
    is($CS->message_charset_to_language('us-ascii'),    'en',  'wire -> en');
};


# ---------------------------------------------------------------------
# 4. langinfo_get_charset() with no hint at all
#
# This is the CGI case: a PCB with nothing in it.  The answer has to be
# the configured default, not the empty string and not a warning.
# ---------------------------------------------------------------------
subtest 'no language hint falls back to the configured default' => sub {
    my $config = {
	cgi_default_charset           => 'euc-jp',
	reply_message_default_charset => 'iso-2022-jp',
	template_file_default_charset => 'euc-jp',
	log_file_default_charset      => 'euc-jp',
    };

    my $curproc = t::Curproc->new($config, FML::PCB->new());

    for my $category (qw(cgi reply_message template_file log_file)) {
	my ($charset, $warn) =
	    warnings_from(sub { $curproc->langinfo_get_charset($category) });

	my $want = $config->{ "${category}_default_charset" };
	is($charset, $want, "$category: the configured default is used");
	is(scalar(@$warn), 0, "$category: nothing warned")
	    or diag("warnings: @$warn");
    }
};


# ---------------------------------------------------------------------
# 5. a category the configuration says nothing about
#
# 'us-ascii' is the last resort in the routine itself.  An empty answer
# here would be a charset of "", which is what a template would then be
# read as.
# ---------------------------------------------------------------------
subtest 'an unconfigured category still yields a charset' => sub {
    my $curproc = t::Curproc->new({}, FML::PCB->new());

    for my $category (@CATEGORY) {
	my ($charset, $warn) =
	    warnings_from(sub { $curproc->langinfo_get_charset($category) });

	is($charset, 'us-ascii', "$category: falls back to us-ascii");
	isnt($charset, '',       "$category: never the empty string");
	is(scalar(@$warn), 0,    "$category: nothing warned")
	    or diag("warnings: @$warn");
    }
};


# ---------------------------------------------------------------------
# 6. no PCB at all
#
# langinfo_get_charset() guards on defined($pcb), so this path exists.
# It is the earliest one in bootstrap, before anything is set up.
# ---------------------------------------------------------------------
subtest 'a process with no PCB still yields a charset' => sub {
    my $curproc = t::Curproc->new({ cgi_default_charset => 'euc-jp' }, undef);

    my ($charset, $warn) =
	warnings_from(sub { $curproc->langinfo_get_charset('cgi') });

    is($charset, 'euc-jp', 'the configured default is used');
    is(scalar(@$warn), 0, 'nothing warned') or diag("warnings: @$warn");
};


# ---------------------------------------------------------------------
# 7. a hint that IS there is still honoured
#
# The fallback must not have replaced the lookup.
# ---------------------------------------------------------------------
subtest 'a language hint in the PCB is used' => sub {
    my $pcb = FML::PCB->new();
    $pcb->set("language_hint", "reply_message", "ja");

    my $curproc = t::Curproc->new(
	{ reply_message_default_charset => 'us-ascii' }, $pcb);

    my ($charset, $warn) =
	warnings_from(sub { $curproc->langinfo_get_charset('reply_message') });

    is($charset, 'iso-2022-jp', 'the hint wins over the default');
    isnt($charset, 'us-ascii',  'and the default is not what came back');
    is(scalar(@$warn), 0, 'nothing warned') or diag("warnings: @$warn");
};


# ---------------------------------------------------------------------
# 8. a charset set directly in the PCB wins over everything
#
# Note the category: the PCB is process-wide, so this cannot use the
# same one as the tests below.  See the subtest after next.
# ---------------------------------------------------------------------
subtest 'an enforced charset in the PCB wins' => sub {
    my $pcb = FML::PCB->new();
    $pcb->set("charset", "file", "utf-8");
    $pcb->set("language_hint", "file", "ja");

    my $curproc = t::Curproc->new({ file_default_charset => 'euc-jp' }, $pcb);

    my ($charset, $warn) =
	warnings_from(sub { $curproc->langinfo_get_charset('file') });

    is($charset, 'utf-8', 'the enforced charset is used');
    is(scalar(@$warn), 0, 'nothing warned') or diag("warnings: @$warn");
};


# ---------------------------------------------------------------------
# 8a. the PCB is process-wide, and that is not an accident
#
# FML::PCB keeps its data in package globals -- it is the process
# control block, one per process by definition, and new() hands back
# another handle onto the same pool rather than a fresh object.
#
# Pinned because it is invisible at the call site and it caught this
# very file: one subtest set a charset for a category and the next one,
# with its own "new" PCB, still saw it.  Anything writing to the PCB in
# a test has to pick a category nothing else uses.
# ---------------------------------------------------------------------
subtest 'FML::PCB is shared across objects, by design' => sub {
    my $a = FML::PCB->new();
    my $b = FML::PCB->new();

    # Not merely shared state: new() hands back the same reference.
    is("$a", "$b", 'new() returns the one object, twice');

    $a->set("charset", "t_probe", "utf-8");
    is($b->get("charset", "t_probe"), 'utf-8',
       'but they address the same pool');

    $b->set("charset", "t_probe", "euc-jp");
    is($a->get("charset", "t_probe"), 'euc-jp', 'in both directions');
};


# ---------------------------------------------------------------------
# 9. a hint nobody knows
#
# language_to_message_charset() answers '' for an unknown language, and
# the routine has a trailing "||= $default" for exactly that.  Without
# it the caller would get "" and read its templates as no charset.
# ---------------------------------------------------------------------
subtest 'an unknown language hint falls back rather than emptying' => sub {
    my $pcb = FML::PCB->new();
    $pcb->set("language_hint", "subject_tag", "klingon");

    my $curproc =
	t::Curproc->new({ subject_tag_default_charset => 'euc-jp' }, $pcb);

    my ($charset, $warn) =
	warnings_from(sub { $curproc->langinfo_get_charset('subject_tag') });

    isnt($charset, '', 'the charset is not empty');
    is($charset, 'euc-jp', 'it is the configured default');
    is(scalar(@$warn), 0, 'nothing warned') or diag("warnings: @$warn");
};

done_testing();
