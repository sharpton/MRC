#!/usr/bin/perl -w

use strict;
use MRC;
use MRC::Run;
use MRC::DB;
use Getopt::Long;

my( $project_id, $username, $password, $ffdb );
$ffdb             = "/mnt/data/home/sharpton/MRC_ffdb/";
my $db_hostname   = "localhost";
my $database_name = "SFams";
my $schema_name   = "SFams";
GetOptions(
    "i=i" => \$project_id,
    "u=s" => \$username,
    "p=s" => \$password,
    "f:s" => \$ffdb,
    "d:s" => \$database_name,
    "h:s" => \$db_hostname,
    );

my $analysis = MRC->new();
$analysis->set_dbi_connection( "DBI:mysql:$database_name:$db_hostname" );
$analysis->set_username( $username );
$analysis->set_password( $password );
$analysis->schema_name( $schema_name );
$analysis->build_schema();
$analysis->set_ffdb( $ffdb );
$analysis->MRC::Run::clean_project( $project_id );
