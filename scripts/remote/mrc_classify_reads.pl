#!/usr/bin/perl -w

use strict;
use MRC;
use MRC::DB;
use MRC::Run;
use Getopt::Long;
use Data::Dumper;
use Bio::SeqIO;
use File::Basename;

my $ffdb           = ""; #point to the master directory path for the flat file database (aligns and HMMs)
my $scripts_path   = ""; #point to the location of the MRC scripts
my $project_id     = ""; 
my $family_subset_list = ""; #path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction
my $username       = "";
my $password       = "";
my $hmmdb_name     = ""; #what is the name of the hmmdb we'll search against?
my $hmmdb_build    = 0;
my $n_hmmdb_splits = 5;
my $force_hmmdb_build = 0;
my $check          = 0;
my $evalue         = 0.0001;
my $coverage       = 0.8;

GetOptions(
    "d=s" => \$ffdb,
    "s=s" => \$scripts_path,
    "i=s" => \$project_id,
    "u=s" => \$username,
    "p=s" => \$password,
    "h=s" => \$hmmdb_name,
    "sub:s" => \$family_subset_list,
    "hb"    => \$hmmdb_build,
    );

#Initialize the project
my $analysis = MRC->new();
#Get a DB connection 
$analysis->set_dbi_connection( "DBI:mysql:IMG" );
$analysis->set_username( $username );
$analysis->set_password( $password );
$analysis->build_schema();
#Connect to the flat file database
$analysis->set_ffdb( $ffdb );
#constrain analysis to a set of families of interest
$analysis->set_family_subset( $family_subset_list, $check );
$analysis->set_project_id( $project_id );

my $samples = $analysis->MRC::DB::get_samples_by_project_id( $project_id );
while( my $sample = $samples->next() ){
    my $sample_id = $sample->sample_id();
    my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs( $hmmdb_name ) };
    foreach my $hmmdb( keys( %hmmdbs ) ){
	my $hsc_results = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/search_results/" . $sample_id . "_v_" . $hmmdb . ".hsc";
	$analysis->MRC::Run::classify_reads( $hsc_results, $evalue, $coverage );
    }
}
