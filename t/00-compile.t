#!perl
#
# This file is part of Bloomd-Client
#
# This software is copyright (c) 2013 by Damien "dams" Krotkine.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#

use strict;
use warnings;

use Test::More;



use File::Find;
use File::Temp qw{ tempdir };

my @modules;
find(
  sub {
    return if $File::Find::name !~ /\.pm\z/;
    my $found = $File::Find::name;
    $found =~ s{^lib/}{};
    $found =~ s{[/\\]}{::}g;
    $found =~ s/\.pm$//;
    # nothing to skip
    push @modules, $found;
  },
  'lib',
);

sub _find_scripts {
    my $dir = shift @_;

    my @found_scripts = ();
    find(
      sub {
        return unless -f;
        my $found = $File::Find::name;
        # nothing to skip
        open my $FH, '<', $_ or do {
          note( "Unable to open $found in ( $! ), skipping" );
          return;
        };
        my $shebang = <$FH>;
        return unless $shebang =~ /^#!.*?\bperl\b\s*$/;
        push @found_scripts, $found;
      },
      $dir,
    );

    return @found_scripts;
}

my @scripts;
do { push @scripts, _find_scripts($_) if -d $_ }
    for qw{ bin script scripts };

my $plan = scalar(@modules) + scalar(@scripts);
$plan ? (plan tests => $plan) : (plan skip_all => "no tests to run");

print STDERR "Start ".localtime(time)."\n";

{
    # fake home for cpan-testers
    # no fake requested ## local $ENV{HOME} = tempdir( CLEANUP => 1 );

    use Parallel::ForkManager;
    my $pm = new Parallel::ForkManager(4);
    $pm->run_on_finish(
        sub {
            my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_structure_reference) = @_;
            if (defined($data_structure_reference)) {  # children are not forced to send anything
                my $string = $data_structure_reference->{string};  # child passed a string reference
                my $module = $data_structure_reference->{module};  # child passed a string reference
                like( $string, qr/^\s*$module ok/s, "$module loaded ok" );
            } else {  # problems occuring during storage or retrieval will throw a warning
                print qq|No message received from child process $pid!\n|;
            }
        }
    );
    for (sort @modules) {
        my $pid = $pm->start and next;
        #like( qx{ $^X -Ilib -e "require $_; print '$_ ok'" }, qr/^\s*$_ ok/s, "$_ loaded ok" );
        my $string = qx { $^X -Ilib -e "require $_;print '$_ ok'"};
        my %to_test = (module=>$_,string=>$string);
        $pm->finish(0,\%to_test);
    }
    $pm->wait_all_children;

    SKIP: {
        eval "use Test::Script 1.05; 1;";
        skip "Test::Script needed to test script compilation", scalar(@scripts) if $@;
        foreach my $file ( @scripts ) {
            my $script = $file;
            $script =~ s!.*/!!;
            script_compiles( $file, "$script script compiles" );
        }
    }
}
print STDERR "End ".localtime(time)."\n";
