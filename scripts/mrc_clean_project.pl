#!/usr/bin/perl -w

use strict;
use MRC;
use MRC::Run;
use MRC::DB;
use Getopt::Long;

my( $project_id, $username, $password, $ffdb );
$ffdb = "/db/projects/sharpton/MRC_ffdb/";
GetOptions(
    "i=i" => \$project_id,
    "u=s" => \$username,
    "p=s" => \$password,
    "f:s" => \$ffdb,
    );

my $analysis = MRC->new();
$analysis->set_dbi_connection( "DBI:mysql:IMG:lighthouse.ucsf.edu" );
$analysis->set_username( $username );
$analysis->set_password( $password );
$analysis->build_schema();
$analysis->set_ffdb( $ffdb );
$analysis->MRC::Run::clean_project( $project_id );
