package Lighttpd::Control;
use Moose;
use MooseX::Types::Path::Class;
use Path::Class;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

has 'config_file' => (
    is       => 'rw',
    isa      => 'Path::Class::File',
    coerce   => 1,
);

has 'binary_path' => (
    is      => 'rw',
    isa     => 'Path::Class::File',
    coerce  => 1,
    lazy    => 1,
    builder => '_find_binary_path'
);

has 'pid_file' => (
    is      => 'rw',
    isa     => 'Path::Class::File',
    coerce  => 1,
    lazy    => 1,
    builder => '_find_pid_file',
);

has 'server_pid' => (
    init_arg => undef,
    is       => 'ro',
    isa      => 'Int',
    lazy     => 1,
    builder  => '_find_server_pid',
);

sub log { shift; warn @_, "\n" }

## ---------------------------------
## events

sub pre_startup   { inner() }
sub post_startup  { inner() }

sub pre_shutdown  { inner() }
sub post_shutdown { inner() }

## ---------------------------------

sub _find_server_pid {
    my $self = shift;
    my $pid  = $self->pid_file->slurp(chomp => 1);
    ($pid)
        || confess "No PID found in pid_file (" . $self->pid_file . ")";
    $pid;
}

sub _find_pid_file {
    my $self = shift;
    
    my $config_file = $self->config_file;
    
    (-f $config_file)
        || confess "Could not find pid_file because could not find config file ($config_file)";
    
    # the two possible approaches to
    # find the pid file (that I know of)
    my @approaches = (
        sub { $config_file->slurp(chomp => 1) },
        sub {
            # NOTE:
            # if we couldn't get the full path 
            # from the config file itself, then 
            # we use the -p option on the lighttpd
            # binary to give us the parsed config
            # which will have the full path in it.
            # - SL
            my $cli = join " " => $self->_construct_command_line('-p');
            `$cli`;            
        }
    );
    
    foreach my $approach (@approaches) {    
        my @config = $approach->();
        foreach my $line (@config) {
            if ($line =~ /server\.pid\-file\s*\=\s*(.*)/) {
                my $pid_file = $1;
                # NOTE:
                # pid file from the config must 
                # be a valid path, which means 
                # it must start and end with quotes
                # - SL
                if ($pid_file =~ /^\"(.*)\"$/) {
                    return Path::Class::File->new($1);
                }
            }
        }
    }
    
    confess "Could not locate the pid-file information, please supply it manually";
}

sub _find_binary_path {
    my $self = shift;

    my $lighttpd = do {
        my $bin = `which lighttpd`;
        chomp($bin);
        Path::Class::File->new($bin)
    };

    return $lighttpd if -x $lighttpd;

    for my $prefix (qw(/usr /usr/local /opt/local /sw)) {
        for my $bindir (qw(bin sbin)) {
            my $lighttpd = Path::Class::File->new($prefix, $bindir, 'lighttpd');
            return $lighttpd if -x $lighttpd;
        }
    }

    confess "can't find lighttpd anywhere tried => (" . ($lighttpd || 'nothing') . ")";
}

sub _construct_command_line {
    my $self = shift;
    my @opts = @_;
    my $conf = $self->config_file;
    
    (-f $conf)
        || confess "Could not locate configuration file ($conf)";
    
    ($self->binary_path, @opts, '-f', $conf->stringify);
}

## ---------------------------------

sub is_server_running {
    my $self = shift;
    # no pid file, no server running ...
    return 0 unless -s $self->pid_file;
    # has pid file, then check it ...
    kill(0, $self->server_pid) ? 1 : 0;
}

sub start {
    my $self = shift;

    $self->log("Starting lighttpd ...");
    $self->pre_startup;

    # NOTE:
    # do this after startup so that it
    # would be possible to write the 
    # config file in the pre_startup
    # hook if we wanted to.
    # - SL
    my @cli = $self->_construct_command_line;

    unless (system(@cli) == 0) {
        $self->log("Could not start lighttpd (@cli) exited with status $?");
        return;
    }

    $self->post_startup;
    $self->log("Lighttpd started.");    
}

sub stop {
    my $self    = shift;
    my $pid_file = $self->pid_file;

    if (-f $pid_file) {
        
        if (!$self->is_server_running) {
            $self->log("Found pid_file($pid_file), but process does not seem to be running.");
            return;
        }
        
        $self->log("Stoping lighttpd ...");
        $self->pre_shutdown;
        
        kill 2, $self->server_pid;
        
        $self->post_shutdown;
        $self->log("Lighttpd stopped.");    
        
        return;
    }

    $self->log("... pid_file($pid_file) not found.");
}

no Moose; 1;

__END__

=pod

=head1 NAME

Lighttpd::Control - Simple class to manage a Lighttpd server

=head1 SYNOPSIS

  #!perl
  
  use strict;
  use warnings;
  
  use Lighttpd::Control;
  
  my ($command) = @ARGV;
  
  my $ctl = Lighttpd::Control->new(
      config_file => [qw[ conf lighttpd.conf ]],
      # PID file can also be discovered automatically 
      # from the conf, or if you prefer you can specify
      pid_file    => 'lighttpd.control.pid',    
  );
  
  $ctl->start if lc($command) eq 'start';
  $ctl->stop  if lc($command) eq 'stop';

=head1 DESCRIPTION

This is a packaging and cleaning up of a script we have been using 
for a while now to manage our Lighttpd servers. This is an early 
release with only the bare bones functionality we needed, future 
releases will surely include more functionality. Suggestions and 
crazy ideas welcomed, especially in the form of patches with tests.

=head1 ATTRIBUTES

=over 4

=item I<config_file>

This is a L<Path::Class::File> instance for the configuration file.

=item I<binary_path>

This is a L<Path::Class::File> instance pointing to the Lighttpd 
binary. This can be autodiscovered or you can specify it via the 
constructor.

=item I<pid_file>

This is a L<Path::Class::File> instance pointing to the Lighttpd 
pid file. This can be autodiscovered from the config file or you 
can specify it via the constructor.

=item I<server_pid>

This is the PID of the live server.

=back

=head1 METHODS 

=over 4

=item B<start>

Starts the Lighttpd server that is currently being controlled by this 
instance. It will also run the pre_startup and post_startup hooks.

=item B<stop>

Stops the Lighttpd server that is currently being controlled by this 
instance. It will also run the pre_shutdown and post_shutdown hooks.

=item B<is_server_running>

Checks to see if the Lighttpd server that is currently being controlled 
by this instance is running or not (based on the state of the PID file).

=item B<log>

Simple logger that you can use, it just sends the output to STDERR via
the C<warn> function.

=back

=head1 AUGMENTABLE METHODS

These methods can be augmented in a subclass to add extra functionality 
to your control script. Here is an example of how they might be used
to integrate with L<FCGI::Engine::Manager> (For a complete, working 
version of this, take a look at the file F<003_basic_with_fcgi_engine.t> 
in the test suite).

  package My::Lighttpd::Control;
  use Moose;
  
  extends 'Lighttpd::Control';
  
  has 'fcgi_manager' => (
      is      => 'ro',
      isa     => 'FCGI::Engine::Manager',   
      default => sub {
          FCGI::Engine::Manager->new(
              conf => 'conf/fcgi.engine.yml'
          )            
      },
  );
  
  augment post_startup => sub {
      my $self = shift;
      $self->log('Starting the FCGI Engine Manager ...');
      $self->fcgi_manager->start;        
  };
  
  augment post_shutdown => sub {
      my $self = shift;
      $self->log('Stopping the FCGI Engine Manager ...');
      $self->fcgi_manager->stop; 
  };    

=over 4

=item B<pre_startup>

=item B<post_startup>

=item B<pre_shutdown>

=item B<post_shutdown>

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no 
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

Based on code originally developed by Chris Prather.

=head1 COPYRIGHT AND LICENSE

Copyright 2008 Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
