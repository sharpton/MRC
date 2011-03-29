#!/usr/bin/perl -w

use strict;
use MRC;
use MRC::DB;
use MRC::Run;
use Getopt::Long;
use Data::Dumper;
use Bio::SeqIO;
use File::Basename;

my $flat_data_path = ""; #point to the master directory path for the flat file database (aligns and HMMs)
my $scripts_path   = ""; #point to the location of the MRC scripts
my $project_file   = ""; #where is the project files to be processed?
my $family_subset_list = ""; #path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction
my $username       = "";
my $password       = "";
my $hmm_db_name    = ""; #what is the name of the hmmdb we'll search against?
my $check          = 0;

GetOptions(
    "d=s" => \$flat_data_path,
    "s=s" => \$scripts_path,
    "i=s" => \$project_file,
    "u=s" => \$username,
    "p=s" => \$password,
    "h=s" => \$hmm_db_name,
    "sub:s" => \$family_subset_list,
    );

#Initialize the project
my $analysis = MRC->new();
#Get a DB connection 
$analysis->set_dbi_connection( "DBI:mysql:IMG" );
$analysis->set_username( $username );
$analysis->set_password( $password );
$analysis->build_schema();
#Connect to the flat file database
$analysis->set_ffdb( $flat_data_path );
#constrain analysis to a set of families of interest
$analysis->set_family_subset( $family_subset_list, $check );

#LOAD PROJECT, SAMPLES, METAREADS
#Grab the samples associated with the project
if( -d $project_file ){
    #Partitioned samples project
    #get the samples associated with project. a project description can be left in 
    #DESCRIPT.txt
    $analysis->get_part_samples( $project_file );
    ############
    #come back and add a check that ensures sequences associated with samples
    #are of the proper format. We should check data before loading.
    ############
    #Load Data. Project id becomes a project var in load_project
    $analysis->load_project( $project_file );
}
else{
  warn "Must provide a properly structured project DB. Cannot continue!\n";
  die;
}
#TRANSLATE READS
#at this point, project, samples and metareads are loaded into the DB.
#translate the metareads
foreach my $sample( keys( %sample_ids ) ){
  my $sample_reads = $ffdb . "projects/" . $self->get_project_id() . "/" . $sample_id . "/raw.fa"
  my $in_orfs      = $ffdb . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs.fa"
  $analysis->translate_reads( $sample_reads, $orf_file );
}
#LOAD ORFS
#reads are translated, now load them into the DB
#$project->set_project_id( $project_id );
#get the sample ids associated with project. maybe unnecessary
#my $samples = $project->get_samples_by_project_id();
#my %sample_lookup = ();
#while( my $sample = $samples->next() ){
#    my $sid = $sample->sample_id();
#    my $alt_id = $sample->sample_alt_id();
#    $sample_lookup{$sid} = $alt_id;
#}
#now let's get our hands dirty with the orfs
#each sample has its own orf file sitting in the ffdb
foreach my $sample( keys( %samples ) ){
  my $in_orfs = $ffdb . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs.fa"
  my $orfs = Bio::SeqIO->new( -file => $in_orfs, -format => 'fasta' );
  my $count = 0;
  while( my $orf = $orfs->next_seq() ){
    my $orf_alt_id = $orf->display_id();
    my $read_alt_id    = parse_orf_id( $orf_alt_id, "transeq" );
    #this is currently an inefficient method, but will work for now. need to use sample_id in file name so that 
    #we can assume sample_id and not have to check per read!
    $project->load_orf( $orf_alt_id, $read_alt_id, \%sample_lookup );
    $count++;			
  }
  print "Added $count orfs to the DB\n";
}
#BUILD HMMDB
$analysis->build_hmm_db( $hmmdb_name, $n_hmmdb_splits, $force_hmmdb_build );

#RUN HMMSCAN
$analysis->run_hmmscan( $orfs, $hmmdb_name, $output );

#PARSE AND LOAD RESULTS
