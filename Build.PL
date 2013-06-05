
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601",
    "Test::Most" => 0,
    "Test::Pretty" => 0
  },
  "configure_requires" => {
    "ExtUtils::MakeMaker" => "6.30",
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Perl client to the bloomd server",
  "dist_author" => [
    "Damien \"dams\" Krotkine"
  ],
  "dist_name" => "Bloomd-Client",
  "dist_version" => "0.10",
  "license" => "perl",
  "module_name" => "Bloomd::Client",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Moo" => 0,
    "namespace::autoclean" => 0
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
