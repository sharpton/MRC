#!/usr/bin/perl -w
use strict;
use Getopt::Long;
use DBIx::Class::Schema::Loader qw/ make_schema_at /;

#build a DBIx::Class module for a given database.
#Setting username and password is required. Everything else defaults to mysql IMG.

my ( $username, $password );
my $dumppath = "./lib";
my $dbname   = "IMG";
my $hostname = "localhost";

GetOptions(
    "u=s" => \$username,
    "p=s" => \$password,
    "d:s" => \$dumppath,
    "n:s" => \$dbname,
    "h:s" => \$hostname,
    );

my $schemaname = $dbname . "::Schema";

make_schema_at(
    $schemaname,
    { debug => 1,
      dump_directory => $dumppath,
    },
    [ "dbi:mysql:dbname=$dbname:$hostname", $username, $password,
      #{ loader_class => 'MyLoader' } # optionally
    ],
);
