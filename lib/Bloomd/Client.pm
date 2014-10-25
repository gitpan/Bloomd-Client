#
# This file is part of Bloomd-Client
#
# This software is copyright (c) 2013 by Damien "dams" Krotkine.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
package Bloomd::Client;
{
  $Bloomd::Client::VERSION = '0.10';
}

# ABSTRACT: Perl client to the bloomd server

use feature ':5.12';
use Moo;
use Method::Signatures;
use autobox::Core;    
use List::MoreUtils qw(any mesh);
use Carp;
use IO::Socket::INET;
use POSIX qw(ETIMEDOUT EWOULDBLOCK EAGAIN strerror);
use Config;


has protocol => ( is => 'ro', default => sub {'tcp'} );


has host => ( is => 'ro', default => sub {'127.0.0.1'} );


has port => ( is => 'ro', default => sub {8673} );
has _socket => ( is => 'lazy', predicate => 1, clearer => 1 );


has timeout => ( is => 'ro', predicate => 1, default => sub { 10 } );


method _build__socket {
    my $socket = IO::Socket::INET->new(
        Proto => $self->protocol,
        PeerHost => $self->host,
        PeerPort => $self->port,
        Timeout  => $self->timeout,
    ) or die "Can't connect to server: $!";

    $self->has_timeout
      or return $socket;

    $Config{osname} eq 'netbsd'
      and croak "the timeout option is not yet supported on NetBSD";

    my $seconds  = int( $self->timeout );
    my $useconds = int( 1_000_000 * ( $self->timeout - $seconds ) );
    my $timeout  = pack( 'l!l!', $seconds, $useconds );

    $socket->setsockopt( SOL_SOCKET, SO_RCVTIMEO, $timeout )
      or croak "setsockopt(SO_RCVTIMEO): $!";

    $socket->setsockopt( SOL_SOCKET, SO_SNDTIMEO, $timeout )
      or croak "setsockopt(SO_SNDTIMEO): $!";

    return $socket;

}


method disconnect {
    $self->_has_socket
      and $self->_socket->close;
    $self->_clear_socket;
}


method create ($name, $capacity?, $prob?, $in_memory?) {
    my $args =
        ( $capacity ? "capacity=$capacity" : '' )
      . ( $prob ? "prob=$prob" : '' )
      . ( $in_memory ? "in_memory=$in_memory" : '' );
    $self->_execute("create $name $args" ) eq 'Done';
}


method list ($prefix? = '') {
    my @keys = qw(name prob size capacity items);
    [
     map {
         my @values = split / /;
         +{ mesh @keys, @values };
     }
     $self->_execute("list $prefix" )
    ];
}


method drop ($name) {
    $self->_execute("drop $name") eq 'Done';
}



method close ($name) {
    $self->_execute("close $name") eq 'Done';
}


method clear ($name) {
    $self->_execute("clear $name") eq 'Done';
}


method check ($name, $key) {
    $self->_execute("c $name $key") eq 'Yes';
}


method multi ($name, @keys) {
    @keys
      or return {};
    my @values = map { $_ eq 'Yes' } split / /, $self->_execute("m $name @keys");
    +{mesh @keys, @values };
}


method set ($name, $key) {
    $self->_execute("s $name $key") eq 'Yes';
}


method bulk ($name, @keys) {
    @keys
      or return;
    $self->_execute("b $name @keys");
    return;
}


method info ($name) {
    +{ map { split / / } $self->_execute("info $name") };
}


method flush ($name) {
    $self->_execute("info $name") eq "Done";
}

method _execute ($command) {
     my $socket = $self->_socket;

     $socket->print($command . "\r\n")
       or croak "couldn't write to socket";

     my $line = $self->_check_line($socket->getline);

     $line = $line->rtrim("\r\n");
     $line =~ /^Client Error:/
       and croak "$line: $command";

     $line eq 'START'
       or return $line;

     my @lines;
     push @lines, $line
       while ( ($line = $self->_check_line($socket->getline)->rtrim("\r\n")) ne 'END');
 
     return @lines;
}

method _check_line($line) {
    defined $line
      and return $line;
    my $e = $!;
    if (any { $e eq strerror($_) } ( EWOULDBLOCK, EAGAIN, ETIMEDOUT )) {
        $e = strerror(ETIMEDOUT);
        $self->disconnect;
    }
    undef $!;
    croak $e;
}

1;

__END__
=pod

=head1 NAME

Bloomd::Client - Perl client to the bloomd server

=head1 VERSION

version 0.10

=head1 SYNOPSIS

  use feature ':5.12';
  use Bloomd::Client;
  my $b = Bloomd::Client->new( timeout => 0.2 );
  my $filter = 'test_filter';
  $b->create($filter);
  my $array_ref = $b->list();
  my $hash_ref = $b->info($filter);
  $b->set($filter, 'u1');
  if ($b->check($filter, 'u1')) { say "it exists!" }
  my $hashref = $b->multi( $filter, qw(u1 u2 u3) );

=head1 ATTRIBUTES

=head2 protocol

The protocol. ro, defaults to 'tcp'

=head2 host

The host to connect to. ro, defaults to '127.0.0.1'

=head2 port

The port to connect to. ro, defaults to '8673'

=head2 timeout

The timeout (on read and write), in seconds. Can be a float. ro, defaults to 10.

=head1 METHODS

=head2 disconnect

Closes the connection and reset the internal socket

=head2 create

Creates a new bloom filter

  $b->create($name, $capacity?, $probability?, $in_memory=0|1?)

Only the name is mandatory. You can specify the initial capacity (if not the
filter will be enlarged as needed), the probability of maximum false positives
you want, and a flag to force the filter to not be in memory (by default it is).

Returns true if the filter didn't exist and was created successfully.

=head2 list

  my $array_ref = $b->list($prefix?)

Returns an ArrayRef of the existing filters. You can provide a prefix to filter
on them.

=head2 drop

  $b->drop($name)

Drops a filter. Returns true if the filter existed and was removed properly.

=head2 close

  $b->close($name)

Closes a filter. Returns true on success.

=head2 clear

  $b->clear($name)

Clears a filter. Returns tru on success.

=head2 check

  if ($b->check($name, $key)) {
    print "the element $key matched\n";
  }

Given a filter name and a key name, returns true if the key was previously
added in the filter (using C<set>).

=head2 multi

  my $hash_ref = $b->multi($name, $key1, key2, key3);

Given a filter name and a list of elements, returns a HashRef, which keys are
the elements, and the values are 1 or 0, depending if the element is present in
the filter or not.

=head2 set

  $b->set($name, $key);

Adds the element to the given filter. Returns 1 if the elements was not
previously in the filter and was properly added.

=head2 bulk

  $b->bulk($name, $key1, $key2, $key3);

Adds the elements to the given filter. Returns void

=head2 info

  my $hash_ref = $b->info($name);

Returns a HashRef giving informations about the given filter name.

=head2 flush

  $b->flush($name);

Flushes the filter. Returns true on success.

=head1 AUTHOR

Damien "dams" Krotkine

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Damien "dams" Krotkine.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

