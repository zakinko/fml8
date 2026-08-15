#-*- perl -*-
#
#  Copyright (C) 2003,2004,2005,2006 Ken'ichi Fukamachi
#   All rights reserved. This program is free software; you can
#   redistribute it and/or modify it under the same terms as Perl itself.
#
# $FML: changepassword.pm,v 1.18 2006/03/04 13:48:28 fukachan Exp $
#

package FML::Command::Admin::changepassword;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;


=head1 NAME

FML::Command::Admin::changepassword - change remote administrator password.

=head1 SYNOPSIS

See C<FML::Command> for more details.

=head1 DESCRIPTION

set password for a new address or change password.

=head1 METHODS

=head2 new()

constructor.

=head2 need_lock()

need lock or not.

=head2 lock_channel()

return lock channel name.

=head2 verify_syntax($curproc, $command_context)

provide command specific syntax checker.

=head2 process($curproc, $command_context)

change remote administrator password.

=cut


# Descriptions: constructor.
#    Arguments: OBJ($self)
# Side Effects: none
# Return Value: OBJ
sub new
{
    my ($self) = @_;
    my ($type) = ref($self) || $self;
    my $me     = {};
    return bless $me, $type;
}


# Descriptions: need lock or not.
#    Arguments: none
# Side Effects: none
# Return Value: NUM( 1 or 0)
sub need_lock { 1;}


# Descriptions: lock channel.
#    Arguments: none
# Side Effects: none
# Return Value: STR
sub lock_channel { return 'command_serialize';}


# Descriptions: verify the syntax command string.
#    Arguments: OBJ($self) OBJ($curproc) OBJ($command_context)
# Side Effects: none
# Return Value: NUM(1 or 0)
sub verify_syntax
{
    my ($self, $curproc, $command_context) = @_;
    my $comname    = $command_context->get_cooked_command()    || '';
    my $comsubname = $command_context->get_cooked_subcommand() || '';
    my $options    = $command_context->get_options()           || [];
    my @test       = ($comname);
    my $command    = $options->[ 0 ] || '';
    my $address    = $options->[ 1 ] || '';
    my $passwd     = $options->[ 2 ] || '';
    push(@test, $command);

    # 1. check address syntax
    if ($address) {
        use FML::Restriction::Base;
        my $dispatch = new FML::Restriction::Base;
        unless ($dispatch->regexp_match('address', $address)) {
            $curproc->logerror("insecure address: <$address>");
            return 0;
        }
    }

    # 2. check syntax of (only) command name.
    use FML::Command;
    my $dispatch = new FML::Command;
    return $dispatch->safe_regexp_match($curproc, $command_context, \@test);
}


# Descriptions: change the admin password.
#    Arguments: OBJ($self) OBJ($curproc) OBJ($command_context)
# Side Effects: update $member_map $recipient_map
# Return Value: NUM
sub process
{
    my ($self, $curproc, $command_context) = @_;
    my $config  = $curproc->config();
    my $myname  = $curproc->myname();
    my $options = $command_context->get_options();

    # XXX The arguments differ for the cases.
    # 1. command mail: admin changepassword [$USER] $PASSWORD
    # 2. command line: makefml changepassword $ML $ADDR $PASSWORD
    #                  fml $ML changepassword     $ADDR $PASSWORD
    if ($myname eq 'makefml' || $myname eq 'fml' ||
	$myname eq 'loader'  ||
	$myname eq 'command' || $myname eq 'fml.pl') {
	my ($address, $password);

	if ($options->[2]) {
	    croak("wrong arguments");
	}
	elsif ($options->[0] && $options->[1]) {
	    $address  = $options->[ 0 ];
	    $password = $options->[ 1 ];
	}
	elsif ($options->[0]) {
	    # XXX-TODO really ???
	    # XXX special treatment only for command mails.
	    if ($myname eq 'command' || $myname eq 'fml.pl') {
		my $cred  = $curproc->credential();
		$address  = $cred->sender(); # From: in the header
		$password = $options->[ 0 ];
	    }
	    else {
		croak("wrong arguments");
	    }
	}
	else {
	    croak("wrong arguments");
	}

	use FML::Restriction::Base;
	my $safe = new FML::Restriction::Base;
	if ($safe->regexp_match('address', $address)) {
	    $self->_change_password($curproc,
				    $command_context,
				    $address,
				    $password);
	}
	else {
	    croak("unsafe address");
	    $curproc->logerror("unsafe address: $address");
	}
    }
    else {
	croak("this program not support this function");
	$curproc->logerror("myname=$myname not support this function");
    }
}


# Descriptions: change the remote admin password.
#    Arguments: OBJ($self) OBJ($curproc) OBJ($command_context)
#               STR($address) STR($password)
# Side Effects: update *admin_member_password_maps
# Return Value: NUM
sub _change_password
{
    my ($self, $curproc, $command_context, $address, $password) = @_;
    my $config = $curproc->config();
    my $cred   = $curproc->credential();

    # XXX We should always add/rewrite only $primary_*_map maps via
    # XXX command mail, CUI and GUI.
    # XXX Rewriting of maps not $primary_*_map is
    # XXX 1) may be not writable.
    # XXX 2) ambigous and dangerous
    # XXX    since the map is under controlled by other module.
    # XXX    for example, one of member_maps is under admin_member_maps.
    my $pri_map = $config->{ primary_admin_member_password_map };
    my $up_args = {
	map      => $pri_map,
	address  => $address,
	password => $password,
    };
    my $r = '';

    # XXX Refuse a password too short to be worth storing, before
    # XXX anything is written.  NIST SP 800-63B puts eight characters at
    # XXX the bottom of the range for any password at all; below that
    # XXX there is no reading of the requirement that permits it.  The
    # XXX remark about fifteen comes later, after the change succeeds,
    # XXX because that one is advice rather than a refusal.
    use FML::Crypt;
    my $crypt = new FML::Crypt;
    if ($crypt->is_too_short($password)) {
	my $n  = $crypt->password_length_hard_limit();
	my $r1 = "password too short: at least $n characters are required.";
	$curproc->reply_message_nl('error.password_too_short', $r1,
				   { _arg_limit => $n });
	$curproc->logerror("changepassword: $r1");
	croak($r1);
    }

    # XXX SP 800-63B: a verifier "SHALL compare the prospective secret
    # XXX against a blocklist that contains known commonly used,
    # XXX expected, or compromised passwords".  The context terms cost
    # XXX nothing and catch the guess anybody would make first; the file
    # XXX is whatever list the site points at; the breach service is off
    # XXX unless the site turns it on, because reaching the network
    # XXX while handling a mail is their decision to make.
    my ($local_part) = split(/\@/, $address);
    my $blk_args = {
	terms => [ $config->{ ml_name },
		   $config->{ ml_domain },
		   $local_part,
		   'fml',
		   'password' ],
	file  => $config->{ password_blocklist_file } || '',
	use_service =>
	    (($config->{ use_password_blocklist_service } || 'no') eq 'yes'),
	service_url => $config->{ password_blocklist_service_url } || '',
	timeout     => $config->{ password_blocklist_service_timeout } || 10,
    };

    my $why = $crypt->blocklist_reason($password, $blk_args);
    if ($why) {
	my $r1 = "password refused: $why";
	$curproc->reply_message_nl('error.password_is_blocklisted', $r1,
				   { _arg_reason => $why });
	$curproc->logerror("changepassword: $r1");
	croak($r1);
    }

    my $member_map = $config->{ primary_admin_member_map };
    unless ($cred->has_address_in_map($member_map, $config, $address)) {
	my $r  = "no such admin member";
	my $r0 = "firstly, please add the address as admin member.";
	$curproc->reply_message_nl('error.no_such_admin_member', $r);
	$curproc->reply_message_nl('command.please_add_admin_member',
				   $r0);
	$curproc->logerror($r);
	croak($r);
    }

    eval q{
	use FML::Command::Auth;
	my $passwd = new FML::Command::Auth;
	$passwd->change_password($curproc, $command_context, $up_args);
    };
    if ($r = $@) {
	croak($r);
    }

    # XXX the password is now stored.  Say so if it is shorter than NIST
    # XXX SP 800-63B asks of a password used on its own, which is what
    # XXX this one is.  It is a remark rather than a refusal: the
    # XXX command interface is mail, so there is nothing to answer, and
    # XXX refusing here would break whatever already calls "makefml
    # XXX changepassword".  See FML::Crypt.
    if ($crypt->is_short($password)) {
	my $n  = $crypt->password_length_lower_limit();
	my $r0 = "Your new password is shorter than $n characters. " .
	         "NIST SP 800-63B asks for at least $n for a password " .
	         "used on its own. Please consider setting a longer one.";
	$curproc->reply_message_nl('command.password_is_short', $r0,
				   { _arg_limit => $n });
	$curproc->log("changepassword: stored a password shorter than $n");
    }
}


# Descriptions: rewrite buffer to hide the password phrase in $rbuf.
#    Arguments: OBJ($self) OBJ($curproc) OBJ($command_context) STR_REF($rbuf)
# Side Effects: none
# Return Value: none
sub rewrite_prompt
{
    my ($self, $curproc, $command_context, $rbuf) = @_;

    if (defined $rbuf) {
	# XXX the first pattern keeps the word after the keyword, since in
	# XXX "changepassword ADDRESS PASSWORD" that word is the address
	# XXX and the password is what follows it.
	# XXX
	# XXX It was applied unconditionally, and process() above documents
	# XXX a form with no address in it: a command mail may say
	# XXX "admin changepassword PASSWORD" and the address is then taken
	# XXX from From:.  For that form the word it kept was the password
	# XXX itself, so the password was written out in full -- and the
	# XXX " ********" it appended afterwards satisfied the guard below,
	# XXX so the pattern that would have hidden it never ran.
	# XXX
	# XXX Decide which form this is before rewriting, rather than
	# XXX rewriting and then asking whether it worked.
	# XXX "passwd" has to be listed in its own right.  The alternation
	# XXX was (password|pass) and the keyword is followed by \s+, so
	# XXX "pass" cannot match inside "passwd" -- the next character is
	# XXX "w".  makefml passwd $ML $ADDR $PASSWORD therefore reached
	# XXX the log with the password in it and nothing blanked at all.
	# XXX Longest alternative first, or "pass" matches the front of
	# XXX "password" and the rest is kept.
	if ($$rbuf =~ /^.*(?:password|passwd|pass)\s+\S+\s+\S/) {
	    $$rbuf =~ s/^(.*(password|passwd|pass)\s+\S+).*/$1 ********/;
	}
	else {
	    $$rbuf =~ s/^(.*(password|passwd|pass)\s+).*/$1 ********/;
	}
    }
}


=head1 CODING STYLE

See C<http://www.fml.org/software/FNF/> on fml coding style guide.

=head1 AUTHOR

Ken'ichi Fukamachi

=head1 COPYRIGHT

Copyright (C) 2003,2004,2005,2006 Ken'ichi Fukamachi

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 HISTORY

FML::Command::Admin::changepassword
first appeared in fml8 mailing list driver package.
See C<http://www.fml.org/> for more details.

=cut


1;
