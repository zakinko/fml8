#-*- perl -*-
#
# IPv6 delivery, over the core Socket.
#
# Mail::Delivery::Net::INET6 used to reach IPv6 through Socket6, a
# separate XS distribution bundled under cpan/dist and built at install
# time.  Socket has carried getaddrinfo(), getnameinfo() and the
# AF_INET6 constants since 1.94 -- perl 5.14 -- so the bundle was doing
# nothing the core could not.
#
# The two are not interchangeable.  Socket6::getaddrinfo() returns five
# fields per address in one flat list; Socket::getaddrinfo() returns
# ($err, @res) with a hash reference per address and reports failure
# through $err rather than by returning a short list.  A rewrite that
# got that wrong would still compile, and would fail only when a message
# was actually delivered to an IPv6 host.
#
# So this connects.  A listening socket is opened on [::1], connect6()
# is pointed at it, and the peer is read back off the socket it hands
# over.  No network and no name service are involved.
#

use strict;
use warnings;
use Test::More;
use IO::Socket;
use Socket qw(AF_INET6 SOCK_STREAM SOL_SOCKET SO_REUSEADDR);

# cpan/lib and img/lib must be APPENDED, never prepended: cpan/lib ships
# File::Spec 0.7, which lacks splitdir()/splitpath()/rel2abs() that both
# fml8 and prove(1) call.
BEGIN {
    for my $d (qw(fml/lib cpan/lib img/lib)) {
	push @INC, $d if -d $d;
    }
}

# A host with IPv6 disabled cannot answer any of this, and that is not a
# defect in fml8.
my $probe = IO::Socket->new();
plan skip_all => "no IPv6 on this host"
    unless socket($probe, AF_INET6, SOCK_STREAM, 0);
close($probe);


# The caller INET6.pm expects: it logs and stores the socket through
# the enclosing delivery object.
{
    package t::Peer;
    use Mail::Delivery::Net::INET6;

    sub new        { return bless { log => [] }, shift }
    sub logdebug   { push @{ $_[0]->{ log } }, "debug: $_[1]"; 1 }
    sub logerror   { push @{ $_[0]->{ log } }, "error: $_[1]"; 1 }
    sub set_error  { $_[0]->{ error } = $_[1]; 1 }
    sub get_error  { return $_[0]->{ error } }
    sub set_socket { $_[0]->{ socket } = $_[1]; 1 }
    sub get_socket { return $_[0]->{ socket } }
    sub log_lines  { return @{ $_[0]->{ log } } }
}


# Descriptions: open a listening socket on [::1] and return it with the
#               port the kernel chose.
#    Arguments: none
# Side Effects: none
# Return Value: ARRAY(HANDLE, NUM) or empty on failure
sub listener_on_loopback
{
    my $srv = IO::Socket->new();

    socket($srv, AF_INET6, SOCK_STREAM, 0)                or return ();
    setsockopt($srv, SOL_SOCKET, SO_REUSEADDR, 1);
    my $addr = Socket::inet_pton(AF_INET6, '::1')         or return ();
    bind($srv, Socket::pack_sockaddr_in6(0, $addr))       or return ();
    listen($srv, 5)                                       or return ();

    my ($port) = Socket::unpack_sockaddr_in6(getsockname($srv));
    return ($srv, $port);
}


# ---------------------------------------------------------------------
# 1. the core provides what Socket6 used to
# ---------------------------------------------------------------------
subtest 'Socket carries the address family independent resolution' => sub {
    for my $f (qw(getaddrinfo getnameinfo pack_sockaddr_in6
		  inet_ntop inet_pton AF_INET6 AF_UNSPEC
		  NI_NUMERICHOST NI_NUMERICSERV)) {
	ok(Socket->can($f), "Socket::$f");
    }

    cmp_ok($Socket::VERSION, '>=', 1.94,
	   "Socket $Socket::VERSION is new enough");
};


# ---------------------------------------------------------------------
# 2. and INET6.pm no longer wants Socket6
# ---------------------------------------------------------------------
subtest 'INET6.pm does not reach for Socket6' => sub {
    my $file = 'fml/lib/Mail/Delivery/Net/INET6.pm';
    ok(-f $file, "$file exists");

    open(my $fh, '<', $file) or do { fail("cannot read $file"); return };
    local $/ = undef;
    my $src = <$fh>;
    close($fh);

    # Comments and POD mention it on purpose, explaining what changed.
    my $code = join("\n", grep { !/^\s*#/ } split(/\n/, $src));
    $code =~ s/^=\w+.*?^=cut//msg;

    unlike($code, qr/\buse\s+Socket6\b/,  'no use Socket6');
    like($code,   qr/\buse\s+Socket\b/,   'it uses Socket instead');

    ok(!exists $INC{ 'Socket6.pm' }, 'Socket6 is not loaded either');
};


# ---------------------------------------------------------------------
# 3. it says this host is IPv6 ready
# ---------------------------------------------------------------------
subtest 'is_ipv6_ready() answers yes on a host with IPv6' => sub {
    my $peer = t::Peer->new();

    ok($peer->is_ipv6_ready(), 'IPv6 ready');
    like(join(' ', $peer->log_lines()), qr/IPv6 ready/,
	 'and says so in the log');
};


# ---------------------------------------------------------------------
# 4. it actually connects
#
# The part a compile check cannot reach: getaddrinfo() returning a
# different shape would only show up here.
# ---------------------------------------------------------------------
subtest 'connect6() reaches a listener on [::1]' => sub {
    my ($srv, $port) = listener_on_loopback();
    plan skip_all => 'cannot listen on [::1] here' unless $srv;

    my $peer = t::Peer->new();
    $peer->connect6("[::1]:$port");

    my $sock = $peer->get_socket();
    ok(defined $sock, 'a socket came back')
	or do { diag(join("\n", $peer->log_lines())); return };

    my $sa = getpeername($sock);
    ok(defined $sa, 'the socket is connected');

    my ($got_port, $got_addr) = Socket::unpack_sockaddr_in6($sa);
    is($got_port, $port, "connected to port $port");
    is(Socket::inet_ntop(AF_INET6, $got_addr), '::1',
       'and the peer really is ::1');

    close($sock);
    close($srv);
};


# ---------------------------------------------------------------------
# 5. a refused connection is reported, not mistaken for success
#
# The old loop decided success by counting how many fields were left in
# a flat list.  The rewrite decides it by whether connect() worked, so
# check that a port with nothing behind it comes back empty-handed.
# ---------------------------------------------------------------------
subtest 'connect6() to a closed port yields no socket' => sub {
    my ($srv, $port) = listener_on_loopback();
    plan skip_all => 'cannot listen on [::1] here' unless $srv;

    # take the port, then give it up, so nothing is listening on it
    close($srv);

    my $peer = t::Peer->new();
    $peer->connect6("[::1]:$port");

    is($peer->get_socket(), undef, 'no socket handed over');
    ok(defined $peer->get_error(), 'and an error was recorded')
	or diag(join("\n", $peer->log_lines()));
};


# ---------------------------------------------------------------------
# 6. a name that does not resolve is reported too
#
# Socket::getaddrinfo() reports failure in $err; Socket6's returned a
# short list.  Reading the new one as though it were the old would treat
# the error string as an address family.
# ---------------------------------------------------------------------
subtest 'connect6() to an unresolvable name yields no socket' => sub {
    my $peer = t::Peer->new();

    # .invalid is reserved by RFC 2606 and must never resolve.
    $peer->connect6("[nonexistent.invalid]:25");

    is($peer->get_socket(), undef, 'no socket handed over');

    my $log = join(' ', $peer->log_lines());
    ok(defined $peer->get_error() || $log =~ /cannot/,
       'and it was reported rather than passed over')
	or diag($log);
};

done_testing();
