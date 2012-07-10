#!/usr/bin/perl -w

#mrc_handler.pl - The control script responsible for executing an MRC run.
#Usage: 
#perl mrc_handler.pl -u <username> -p <password> -d <path_to_flat_file_db> -s <path_to_mrc_scripts_directory> -i <path_to_metagenome_data> -h <hmm_database_name> > <path_to_out_log> 2> <path_to_error_log>
#
#Example Usage:
#nohup perl mrc_handler.pl -u username -p password -d /bueno_not_backed_up/sharpton/MRC_ffdb -s ./ -i ../data/randsamp_subset_perfect_2 -h OPFs_all_v1.0 > randsamp_perfect_2.all.out 2> randsamp_perfect_2.all.err &

use strict;
use MRC;
use MRC::DB;
use MRC::Run;
use Getopt::Long;
use Data::Dumper;
use Bio::SeqIO;
use File::Basename;
use IPC::System::Simple qw(capture $EXITVAL);

print "perl mrc_handler.pl @ARGV\n";
 
my $ffdb           = "/bueno_not_backed_up/sharpton/MRC_ffdb/";  #point to the master directory path for the flat file database (aligns and HMMs)
#my $ffdb           = "/db/projects/sharpton/MRC_ffdb/";
my $scripts_path   = "/home/sharpton/projects/MRC/scripts/"; #point to the location of the MRC scripts
my $project_file   = ""; #where is the project files to be processed?
my $family_subset_list; #path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction, e.g. /home/sharpton/projects/MRC/data/subset_perfect_famids.txt
my $username       = "";
my $password       = "";
my $hmmdb_name     = ""; #e.g., "perfect_fams", what is the name of the hmmdb we'll search against? look in $ffdb/HMMdbs Might change how this works
my $hmmdb_build    = 0;
my $force_hmmdb_build = 0;
my $check          = 0;
my $evalue         = 0.001;
#my $coverage       = 0.8;
my $coverage       = 0;
my $is_strict      = 1; #strict (top hit) v. fuzzy (all hits passing thresholds) clustering. 1 = strict. 0 = fuzzy. Fuzzy not yet implemented!
#remote compute (e.g., SGE) vars
my $remote         = 1;
my $remote_ip      = "chef.compbio.ucsf.edu";
my $remote_user    = "sharpton";
my $rffdb          = "/netapp/home/sharpton/projects/MRC/MRC_ffdb/";
my $rscripts       = "/netapp/home/sharpton/projects/MRC/scripts/";
my $waittime       = 30;
my $input_pid      = "";
my $goto           = ""; #B=Build HMMdb
my $hmm_db_split_size    = 500; #how many HMMs per HMMdb split?
my $nseqs_per_samp_split = 500; #how many seqs should each sample split file contain?
my $verbose        = 1;

#think about option naming conventions before release
GetOptions(
    "d=s"   => \$ffdb,
    "s=s"   => \$scripts_path,
    "i=s"   => \$project_file,
    "u=s"   => \$username,
    "p=s"   => \$password,
    "h=s"   => \$hmmdb_name,
    "sub:s" => \$family_subset_list,
    "b"     => \$hmmdb_build,
    "f"     => \$force_hmmdb_build,
    "n:i"   => \$hmm_db_split_size,
    "w:i"   => \$waittime, #in seconds
    "r"     => \$remote,
    "pid:i"      => \$input_pid,
    "goto|g:s"   => \$goto,
    "z"          => \$nseqs_per_samp_split,
    "v"          => \$verbose,
    );

#Initialize the project
my $analysis = MRC->new();
#Get a DB connection 
$analysis->set_dbi_connection( "DBI:mysql:IMG:lighthouse.ucsf.edu" );
$analysis->set_username( $username );
$analysis->set_password( $password );
$analysis->build_schema();
#Connect to the flat file database
$analysis->set_ffdb( $ffdb );
#constrain analysis to a set of families of interest
$analysis->set_family_subset( $family_subset_list, $check );
$analysis->set_hmmdb_name( $hmmdb_name );
$analysis->is_remote( $remote );
#set some clustering definitions here
$analysis->is_strict_clustering( $is_strict );
$analysis->set_evalue_threshold( $evalue );
$analysis->set_coverage_threshold( $coverage );
#if using a remote server for compute, set vars here
if( $remote ){
    $analysis->set_remote_server( $remote_ip );
    $analysis->set_remote_username( $remote_user );
    $analysis->set_remote_ffdb( $rffdb );
    $analysis->set_remote_scripts( $rscripts );
    $analysis->build_remote_ffdb( $verbose ); #checks if necessary to build and then builds
}

#block tries to jump to a module in handler for project that has already done some work
if( $input_pid && $goto ){
    $analysis->MRC::Run::back_load_project( $input_pid );
    #this is a little hacky...come clean this up!
    #$analysis->MRC::Run::get_part_samples( $project_file );
    $analysis->MRC::Run::back_load_samples();
    if( $goto eq "B" ){ warn "Skipping to HMMdb building step!\n"; goto BUILDHMMDB; }
    if( $goto eq "S" ){ warn "Skipping to building hmmscan script step!\n"; goto BUILDHMMSCRIPT; }
    if( $goto eq "H" ){ warn "Skipping to hmmscan step!\n"; goto HMMSCAN; }
    if( $goto eq "G" ){ warn "Skipping to get remote hmmscan results step!\n"; goto GETRESULTS; }
    if( $goto eq "C" ){ warn "Skipping to classifying reads step!\n"; goto CLASSIFYREADS; }
    if( $goto eq "O" ){ warn "Skipping to producing output step!\n"; goto CALCDIVERSITY; }
}

#LOAD PROJECT, SAMPLES, METAREADS
#Grab the samples associated with the project
if( -d $project_file ){
    print printhead( "LOADING PROJECT" );
    #Partitioned samples project
    #get the samples associated with project. a project description can be left in 
    #DESCRIPT.txt
    $analysis->MRC::Run::get_partitioned_samples( $project_file );
    ############
    #come back and add a check that ensures sequences associated with samples
    #are of the proper format. We should check data before loading.
    ############
    #Load Data. Project id becomes a project var in load_project
    $analysis->MRC::Run::load_project( $project_file, $nseqs_per_samp_split );
    if( $remote ){
	$analysis->MRC::Run::load_project_remote( $analysis->get_project_id() );
	$analysis->set_remote_hmmscan_script( $analysis->get_remote_project_path() . "run_hmmscan.sh" );
	$analysis->set_remote_project_log_dir( $analysis->get_remote_project_path() . "/logs/" );
    }
}
else{
  warn "Must provide a properly structured project directory. Cannot continue!\n";
  die;
}

#TRANSLATE READS
#at this point, project, samples and metareads are loaded into the DB.
#translate the metareads
if( $remote ){
    print printhead( "TRANSLATING READS" );
    #run transeq remotely, check on SGE job status, pull results back locally once job complete.
    $analysis->MRC::Run::translate_reads_remote( $waittime );	
}
else{
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	my $sample_reads = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/raw/";
	my $orfs_file     = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/orfs/";
	#could do some file splitting here to speed up the remote compute
	$analysis->MRC::Run::translate_reads( $sample_reads, $orfs_file );	
    }
}

#LOAD ORFS
#reads are translated, now load them into the DB
print printhead( "LOADING TRANSLATED READS" );
foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
    my $in_orf_dir = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/orfs/";
    my $count = 0;
    foreach my $in_orfs( @{ $analysis->MRC::DB::get_split_sequence_paths( $in_orf_dir, 1 ) } ){
	print "Processing orfs in $in_orfs\n";
	my $orfs = Bio::SeqIO->new( -file => $in_orfs, -format => 'fasta' );
	while( my $orf = $orfs->next_seq() ){
	    my $orf_alt_id  = $orf->display_id();
	    my $read_alt_id = MRC::Run::parse_orf_id( $orf_alt_id, "transeq" );
	    $analysis->MRC::Run::load_orf( $orf_alt_id, $read_alt_id, $sample_id );
	    $count++;			
	}
    }
    print "Added $count orfs to the DB\n";
}

#BUILD HMMDB
BUILDHMMDB:
if( $hmmdb_build ){
    print printhead( "BUILDING HMM DATABASE" );
    $analysis->MRC::Run::build_hmm_db( $hmmdb_name, $hmm_db_split_size, $force_hmmdb_build );
}

REMOTESTAGE:
if( $remote ){
    #need to do something here that clears the remote hmmdb
    $analysis->MRC::Run::remote_transfer_hmm_db( $hmmdb_name );
}

BUILDHMMSCRIPT:
if( $remote ){
    print printhead( "BUILDING REMOTE HMMSCAN SCRIPT" );
    my $h_script_path   = $ffdb . "/projects/" . $analysis->get_project_id() . "/run_hmmscan.sh";
    my $r_h_script_path = $analysis->get_remote_hmmscan_script();
    my $n_hmm_searches  = $analysis->MRC::DB::get_number_hmmdb_scans( $hmm_db_split_size );
    print "number of searches: $n_hmm_searches\n";
    my $n_hmmdb_splits  = $analysis->MRC::DB::get_number_hmmdb_splits( $hmmdb_name );
    print "number of splits: $n_hmmdb_splits\n";
    build_remote_hmmscan_script( $h_script_path, $n_hmm_searches, $hmmdb_name, $n_hmmdb_splits, $analysis->get_remote_project_path() );
    $analysis->MRC::Run::remote_transfer( $h_script_path, $analysis->get_remote_username . "@" . $analysis->get_remote_server . ":" . $r_h_script_path, "f" );
}

#RUN HMMSCAN
HMMSCAN:
if( $remote ){
    print printhead( "RUNNING REMOTE HMMSCAN" );
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	$analysis->MRC::Run::run_hmmscan_remote( $sample_id, $verbose );
    }
}
else{
    print printhead( "RUNNING LOCAL HMMSCAN" );
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	my $sample_path = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/";
	my $orfs        = "orfs.fa";
	my $results_dir = "search_results/";
	my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs( $hmmdb_name ) };
	warn "Running hmmscan\n";
	foreach my $hmmdb( keys( %hmmdbs ) ){
	    my $results = $results_dir . $sample_id . "_v_" . $hmmdb . ".hsc";
	    #run with tblast output format (e.g., --domtblout )
	    $analysis->MRC::Run::run_hmmscan( $orfs, $hmmdbs{$hmmdb}, $results, 1 );
#	    $analysis->MRC::Run::run_hmmscan( $orfs, $hmmdbs{$hmmdb}, $results );
	}
    }
}

#GET REMOTE RESULTS
GETRESULTS:
if( $remote ){
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	$analysis->MRC::Run::get_remote_hmmscan_results( $sample_id );
    }
}

#PARSE AND LOAD RESULTS
CLASSIFYREADS:
if( $remote ){
    print printhead( "CLASSIFYING REMOTE SEARCH RESULTS" );
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	my $path_to_split_orfs = $analysis->get_sample_path( $sample_id ) . "/orfs/";
	foreach my $orf_split_file_name( @{ $analysis->MRC::DB::get_split_sequence_paths( $path_to_split_orfs , 0 ) } ) {
	    $analysis->MRC::Run::classify_reads( $sample_id, $orf_split_file_name );
	}
    }
}
#the block below is depricated...
else{
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs( $hmmdb_name ) };
	foreach my $hmmdb( keys( %hmmdbs ) ){
	    my $hsc_results = $ffdb . "projects/" . $analysis->get_project_id() . "/" . $sample_id . "/search_results/" . $sample_id . "_v_" . $hmmdb . ".hsc";
	    $analysis->MRC::Run::classify_reads( $sample_id, $hsc_results, $evalue, $coverage );
	}
    }
}

#calculate diversity statistics
CALCDIVERSITY:
print printhead( "CALCULATING DIVERSITY STATISTICS" );
#note, we could decrease DB pings by merging some of these together (they frequently leverage same hash structure
print "project richness...\n";
$analysis->MRC::Run::calculate_project_richness();
print "project relative abundance...\n";
$analysis->MRC::Run::calculate_project_relative_abundance();
print "per sample richness...\n";
$analysis->MRC::Run::calculate_sample_richness();
print "per sample relative abundance..\n";
$analysis->MRC::Run::calculate_sample_relative_abundance();
print "building classification map...\n";
$analysis->MRC::Run::build_classification_map();
print "building PCA dataframe...\n";
$analysis->MRC::Run::build_PCA_data_frame();

print "ANALYSIS COMPLETE!\n";

sub build_remote_hmmscan_script{
    my( $h_script_path, $n_searches, $hmmdb_basename, $n_splits, $project_path ) = @_;
    my @args = ( "build_remote_hmmscan_script.pl", "-z $n_searches", "-o $h_script_path", "-n $n_splits", "--name $hmmdb_basename", "-p $project_path" );
    my $results = capture( "perl " . "@args" );
    if( $EXITVAL != 0 ){
	warn( $results );
	exit(0);
    }
    return $results;
}

sub printhead{
    my $string = shift;
    my $length = length( $string );
    #add four to account for extra # and whitespce on either side of string
    my $pad_length = $length + 4;
    my $pad  = "";
    my $plen = 0;
    while( $plen < $pad_length ){
	$pad .= "#";
	$plen++;
    }
    $string = "$pad\n" . "# " . $string . " #\n" . "$pad\n";
    return $string;
}
