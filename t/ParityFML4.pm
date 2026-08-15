#-*- perl -*-
#
# Read fml4's tables out of an fml4 checkout so that fml8 can be compared
# against them.
#
# fml8 is a rewrite of fml4, so anything fml4 could be asked to do fml8
# should be able to do as well.  Nothing enforces that today, and the two
# trees are separate repositories, so the drift is invisible.  These
# helpers parse fml4's own sources -- the command table, makefml's
# subcommands, the configuration variables, the address guard -- and hand
# them to the t/2*_parity_*.t tests.
#
# fml4 is found through $FML4_DIR, falling back to ../fml4.  When it is
# not there every parity test skips rather than fails, so a plain
# "prove t/" in an fml8 checkout alone still works.
#

package ParityFML4;
use strict;
use warnings;
use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA       = qw(Exporter);
@EXPORT_OK = qw(fml4_dir
		fml4_user_commands fml4_command_prefixes
		fml4_makefml_subcommands fml4_makefml_aliases
		fml4_makefml_handlers
		fml4_fmlserv_commands
		fml4_config_variables fml4_secure_class
		fml4_subject_tag_modes
		fml8_user_commands fml8_admin_commands fml8_user_aliases);


# Descriptions: return the fml4 checkout to compare against, or undef.
#    Arguments: none
# Side Effects: none
# Return Value: STR or undef
sub fml4_dir
{
    my $dir = $ENV{ FML4_DIR } || '../fml4';

    return undef unless -d $dir;
    return undef unless -f "$dir/proc/libfml.pl";
    return $dir;
}


# Descriptions: slurp $file from the fml4 tree as raw octets.
#               fml4 has EUC-JP comments, so nothing may decode it.
#    Arguments: STR($file)
# Side Effects: none
# Return Value: STR
sub _slurp
{
    my ($file) = @_;
    my $dir    = fml4_dir() || return '';

    open(my $fh, '<', "$dir/$file") or return '';
    binmode($fh);
    local $/ = undef;
    my $s = <$fh>;
    close($fh);
    return defined $s ? $s : '';
}


# Descriptions: return the body of sub $name in $file.
#    Arguments: STR($file) STR($name)
# Side Effects: none
# Return Value: STR
sub _sub_body
{
    my ($file, $name) = @_;
    my $src = _slurp($file);

    return '' unless $src =~ /^sub \Q$name\E\b.*?\n(.*?)^\}/ms;
    return $1;
}


# Descriptions: every key of fml4's %Procedure table, prefixes and all.
#               InitProcedure() builds it as a flat list of
#               'name', value pairs, so the quoted names in odd position
#               are what we want; taking every quoted word is close
#               enough and harmless, since the values are numbers or
#               Proc* function names.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub _fml4_procedure_keys
{
    my $body = _sub_body('proc/libfml.pl', 'InitProcedure');
    my %seen = ();

    # only lines that are a bare quoted token followed by a comma: the
    # table is laid out one "'name', value," pair per line.
    for my $line (split(/\n/, $body)) {
	next if $line =~ /^\s*#/;
	while ($line =~ /'([^']+)'\s*,/g) {
	    my $k = $1;
	    next if $k =~ /^Proc/;      # the handler, not the command
	    next if $k =~ /^\s*$/;
	    $seen{ $k } = 1;
	}
    }

    return [ sort keys %seen ];
}


# Descriptions: fml4's command names with every prefix stripped and the
#               internal-only entries dropped.  These are the names a
#               subscriber may actually put in a mail.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub fml4_user_commands
{
    my %seen = ();

    for my $k (@{ _fml4_procedure_keys() }) {
	# "#name" is fml4's internal representation, not a command.
	next if $k =~ /^\#/;

	# l# is a request limit, r# a report flag, d#/dbd# a debug hook.
	next if $k =~ /^(l|r|d|dbd)\#/;

	# confirm#foo and r2a#foo are the confirmation and
	# reply-to-author variants of foo, which is listed on its own.
	next if $k =~ /^(confirm|confirm_r2a|r2a)\#/;

	$seen{ $k } = 1;
    }

    return [ sort keys %seen ];
}


# Descriptions: the prefixes fml4 attaches to a command name, with the
#               set of commands carrying each.
#    Arguments: none
# Side Effects: none
# Return Value: HASH_REF
sub fml4_command_prefixes
{
    my %by_prefix = ();

    for my $k (@{ _fml4_procedure_keys() }) {
	next unless $k =~ /^([a-z_0-9]+)\#(.+)$/;
	push @{ $by_prefix{ $1 } }, $2;
    }

    for my $p (keys %by_prefix) {
	my %u = map { $_ => 1 } @{ $by_prefix{ $p } };
	$by_prefix{ $p } = [ sort keys %u ];
    }

    return \%by_prefix;
}


# Descriptions: the subcommands makefml dispatches on.
#               %MakeFmlProc pairs a name with its handler, and mixes in
#               'NNN#name args' => 'description' entries that drive the
#               usage message.  Only the first kind is a subcommand.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub fml4_makefml_subcommands
{
    my $src  = _slurp('sbin/makefml');
    my %seen = ();

    if ($src =~ /%MakeFmlProc\s*=\s*\((.*?)^\s*\);/ms) {
	my $table = $1;
	while ($table =~ /'([a-z][a-z0-9_.-]*)'\s*,\s*'(do_[a-z0-9_]+|&?[A-Za-z][A-Za-z0-9_:]*)'/g) {
	    $seen{ $1 } = 1;
	}
    }

    return [ sort keys %seen ];
}


# Descriptions: makefml subcommand => handler function.  Two names
#               sharing a handler are the same command spelled twice,
#               which is how makefml states its own synonyms.
#    Arguments: none
# Side Effects: none
# Return Value: HASH_REF
sub fml4_makefml_handlers
{
    my $src  = _slurp('sbin/makefml');
    my %fp   = ();

    if ($src =~ /%MakeFmlProc\s*=\s*\((.*?)^\s*\);/ms) {
	my $table = $1;
	while ($table =~ /'([a-z][a-z0-9_.-]*)'\s*,\s*'(do_[a-z0-9_]+|&?[A-Za-z][A-Za-z0-9_:]*)'/g) {
	    $fp{ $1 } = $2;
	}
    }

    return \%fp;
}


# Descriptions: makefml's own subcommand aliases (%MakeFmlProcAlias).
#    Arguments: none
# Side Effects: none
# Return Value: HASH_REF
sub fml4_makefml_aliases
{
    my $src   = _slurp('sbin/makefml');
    my %alias = ();

    if ($src =~ /%MakeFmlProcAlias\s*=\s*\((.*?)^\s*\);/ms) {
	my $table = $1;
	while ($table =~ /'([a-z][a-z0-9_-]*)'\s*=>\s*"?'?([^",';]+)/g) {
	    my ($k, $v) = ($1, $2);
	    $v =~ s/\s+$//;
	    $alias{ $k } = $v;
	}
    }

    return \%alias;
}


# Descriptions: the commands fmlserv offers.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub fml4_fmlserv_commands
{
    my $src  = _slurp('libexec/fmlserv.pl');
    my %seen = ();

    while ($src =~ /'fmlserv:([a-z0-9_]+)'/g) { $seen{ $1 } = 1 }

    return [ sort keys %seen ];
}


# Descriptions: every configuration variable fml4 reads or assigns.
#               fml4 has no single defaults file; the variables are
#               global and set across kern/, proc/ and libexec/, so the
#               tree itself is the list.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub fml4_config_variables
{
    my %seen = ();

    for my $dir (qw(kern proc libexec)) {
	my $d = fml4_dir() . "/$dir";
	next unless -d $d;

	opendir(my $dh, $d) or next;
	my @f = grep { /\.pl$/ } readdir($dh);
	closedir($dh);

	for my $f (@f) {
	    my $src = _slurp("$dir/$f");

	    # an assignment at the start of a line, which is how fml4
	    # states a default.  $Foo and $FOO_BAR both count; the
	    # lowercase and mixed-case ones are internal state, so keep
	    # to the all-caps convention fml4 uses for configuration.
	    while ($src =~ /^\s*\$([A-Z][A-Z0-9_]{2,})\s*=[^=~]/mg) {
		$seen{ $1 } = 1;
	    }
	}
    }

    return [ sort keys %seen ];
}


# Descriptions: the character class __SecureP() accepts, taken from the
#               source rather than by running fml4, which would need its
#               whole kernel loaded.
#    Arguments: none
# Side Effects: none
# Return Value: STR
sub fml4_secure_class
{
    my $body = _sub_body('kern/libkernsubr.pl', '__SecureP');

    # the live test, not the commented-out older one above it.
    return $1 if $body =~ /^\s{4}if \(\$s =~ \/\^\[(.+?)\]\+\$\/\)/m;
    return '';
}


# Descriptions: the subject tag layouts SubjectTagDef() understands.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub fml4_subject_tag_modes
{
    my $body = _sub_body('proc/libtagdef.pl', 'SubjectTagDef');
    my %seen = ();

    while ($body =~ /\$mode eq '([^']*)'/g) { $seen{ $1 } = 1 }

    return [ sort keys %seen ];
}


# Descriptions: fml8's user command modules.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub fml8_user_commands
{
    return _fml8_commands('User');
}


# Descriptions: fml8's admin command modules.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY_REF
sub fml8_admin_commands
{
    return _fml8_commands('Admin');
}


# Descriptions: module basenames under FML/Command/$class.
#    Arguments: STR($class)
# Side Effects: none
# Return Value: ARRAY_REF
sub _fml8_commands
{
    my ($class) = @_;
    my $dir     = "fml/lib/FML/Command/$class";

    return [] unless -d $dir;

    opendir(my $dh, $dir) or return [];
    my @f = grep { /\.pm$/ } readdir($dh);
    closedir($dh);

    return [ sort map { my $x = $_; $x =~ s/\.pm$//; $x } @f ];
}


# Descriptions: fml8's user command aliases, as the modules declare them
#               in their own POD ("Alias of C<...>").
#    Arguments: none
# Side Effects: none
# Return Value: HASH_REF
sub fml8_user_aliases
{
    my %alias = ();

    for my $c (@{ fml8_user_commands() }) {
	open(my $fh, '<', "fml/lib/FML/Command/User/$c.pm") or next;
	local $/ = undef;
	my $src = <$fh>;
	close($fh);

	# "Alias of C<subscribe>.", "An alias of C<FML::Command::User::get>.",
	# "an alias of "guide" module." -- all three forms occur.
	if ($src =~ /alias\s+of\s+C<(?:FML::Command::User::)?(\w+)>/i ||
	    $src =~ /alias\s+of\s+"(\w+)"/i) {
	    $alias{ $c } = $1;
	}
    }

    return \%alias;
}


# Descriptions: run $code in a separate perl with the fml4 tree as its
#               working directory, and return what it printed.
#
#               fml4 is Perl 4: its libraries put everything in main::,
#               assign package globals at load time and expect &Log() and
#               friends to exist.  Loading them into the test process
#               would collide with fml8, which is in the same process, so
#               they get a process of their own and answer over stdout.
#
#               $code is perl source; it may require() fml4 libraries by
#               relative path and should print its results.
#    Arguments: STR($code)
# Side Effects: forks a perl(1).
# Return Value: STR (empty if fml4 is not available or the child failed)
sub run_in_fml4
{
    my ($code) = @_;
    my $dir    = fml4_dir() || return '';

    # fml4 logs and mails from inside the routines under test.  Give it
    # somewhere harmless to do that and record it, so a side effect can
    # be asserted rather than merely avoided.
    my $preamble = q{
	our (@FML4_LOG, @FML4_WARN);
	*main::Log   = sub { push @FML4_LOG,  join(" ", @_); 1 };
	*main::WarnE = sub { push @FML4_WARN, join(" ", @_); 1 };
	*main::Mesg  = sub { 1 };
	*main::Debug = sub { 1 };
    };

    my $pid = open(my $fh, '-|');
    return '' unless defined $pid;

    unless ($pid) {
	# child: fml4 libraries require() each other by relative path.
	chdir($dir) or exit 1;
	open(STDERR, '>', '/dev/null');
	exec('perl', '-e', $preamble . "\n" . $code);
	exit 1;
    }

    local $/ = undef;
    my $out = <$fh>;
    close($fh);

    return defined $out ? $out : '';
}


# Descriptions: is a separate-process fml4 usable at all?
#    Arguments: none
# Side Effects: forks a perl(1).
# Return Value: NUM(1 or 0)
sub fml4_is_runnable
{
    my $out = run_in_fml4(q{print "ok\n"});

    return $out =~ /^ok$/m ? 1 : 0;
}


1;
