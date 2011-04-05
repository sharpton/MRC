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
my $project_file   = ""; #where is the project files to be processed?
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
    "i=s" => \$project_file,
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

#LOAD PROJECT, SAMPLES, METAREADS
#Grab the samples associated with the project
if( -d $project_file ){
    #Partitioned samples project
    #get the samples associated with project. a project description can be left in 
    #DESCRIPT.txt
    $analysis->MRC::Run::get_part_samples( $project_file );
    ############
    #come back and add a check that ensures sequences associated with samples
    #are of the proper format. We should check data before loading.
    ############
    #Load Data. Project id becomes a project var in load_project
    $analysis->MRC::Run::load_project( $project_file );
}
else{
  warn "Must provide a properly structured project DB. Cannot continue!\n";
  die;
}

#TRANSLATE READS
#at this point, project, samples and metareads are loaded into the DB.
#translate the metareads
foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
    my $sample_reads = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/raw.fa";
    my $orfs_file     = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/orfs.fa";
    $analysis->MRC::Run::translate_reads( $sample_reads, $orfs_file );
}

#LOAD ORFS
#reads are translated, now load them into the DB
foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
    my $in_orfs = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/orfs.fa";
    my $orfs = Bio::SeqIO->new( -file => $in_orfs, -format => 'fasta' );
    my $count = 0;
    while( my $orf = $orfs->next_seq() ){
	my $orf_alt_id  = $orf->display_id();
	my $read_alt_id = MRC::Run::parse_orf_id( $orf_alt_id, "transeq" );
	$analysis->MRC::Run::load_orf( $orf_alt_id, $read_alt_id, $sample_id );
	$count++;			
    }
    print "Added $count orfs to the DB\n";
}

#BUILD HMMDB
if( $hmmdb_build == 1 ){
    $analysis->MRC::Run::build_hmm_db( $hmmdb_name, $n_hmmdb_splits, $force_hmmdb_build );
}

#RUN HMMSCAN
#should fold this into a standalone method
foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
    my $orfs        = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/orfs.fa";
    my $results_dir = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/search_results/";
    my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs( $hmmdb_name ) };
    warn "Running hmmscan\n";
    foreach my $hmmdb( keys( %hmmdbs ) ){
	my $results = $results_dir . $sample_id . "_v_" . $hmmdb . ".hsc";
	$analysis->MRC::Run::run_hmmscan( $orfs, $hmmdbs{$hmmdb}, $results );
    }
}

#PARSE AND LOAD RESULTS
foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
    my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs( $hmmdb_name ) };
    foreach my $hmmdb( keys( %hmmdbs ) ){
	my $hsc_results = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/search_results/" . $sample_id . "_v_" . $hmmdb . ".hsc";
	$analysis->MRC::Run::classify_reads( $sample_id, $hsc_results, $evalue, $coverage );
    }
}
