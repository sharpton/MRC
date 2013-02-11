#!/usr/bin/perl -w

#mrc_handler.pl - The control script responsible for executing an MRC run.
#Usage: 
#perl mrc_handler.pl -u <username> -p <password> -d <path_to_flat_file_db> -s <path_to_mrc_scripts_directory> -i <path_to_metagenome_data> -h <hmm_database_name> > <path_to_out_log> 2> <path_to_error_log>
#
#Example Usage:
#nohup perl mrc_handler.pl -u username -p password -d /bueno_not_backed_up/sharpton/MRC_ffdb -s ./ -i ../data/randsamp_subset_perfect_2 -h OPFs_all_v1.0 > randsamp_perfect_2.all.out 2> randsamp_perfect_2.all.err &

## ================================================================================
## ================================================================================
## FAQ for problems encountered while running mrc_handler.pl:
##
## 1) To solve: 'Can't locate MRC.pm in @INC ...'
## IF YOU GET AN ERROR about MRC or Sfams::Schema not being find-able,
## THEN YOU MAY BE ABLE TO FIX THIS BY TYPING:
##         export MRC_LOCAL=/your/location/of/MRC           <-- replace that path with the actual one
## For example, if MRC is in your home directory, you would type:
##         export MRC_LOCAL=~/MRC
## Please note: do not use spaces around the EQUALS SIGN (=), or it won't work!
##
## ================================================================================
## ================================================================================

# Note that Perl "use" takes effect at compile time!!!!!!!! So you can't put any control logic to detect whether the ENV{'MRC_LOCAL'}
# exists --- that logic will happen AFTER 'use' has already been invoked. From here: http://perldoc.perl.org/functions/use.html
# Added by Alex Williams, Feb 2013.
use lib ($ENV{'MRC_LOCAL'} . "/scripts"); ## Allows "MRC.pm" to be found in the MRC_LOCAL directory
use lib ($ENV{'MRC_LOCAL'} . "/lib"); ## Allows "Schema.pm" to be found in the MRC_LOCAL directory. DB.pm needs this.
## Note: you may want to set MRC_LOCAL with the following commands in your shell:
##       export MRC_LOCAL=/home/yourname/MRC          (assumes your MRC directory is in your home directory!)
##       You can also add that line to your ~/.bashrc so that you don't have ot set MRC_LOCAL every single time!
#use if ($ENV{'MRC_LOCAL'}), "MRC";

use strict;
use warnings;
use MRC;
use MRC::DB;
use MRC::Run;
use Getopt::Long;
use Data::Dumper;
use Bio::SeqIO;
use File::Basename;
use IPC::System::Simple qw(capture $EXITVAL);
use Benchmark;

sub dieWithUsageError($) { print("[TERMINATED DUE TO USAGE ERROR]: " . $_[0] . "\n"); print STDOUT <DATA>; die("[TERMINATED DUE TO USAGE ERROR]: " . $_[0] . "\n"); }

sub warnPrint($) { print("[WARNING]: " . $_[0] . "\n"); }

print STDERR ">> ARGUMENTS TO mrc_handler.pl: perl mrc_handler.pl @ARGV\n";

## "ffdb" = "flat file data base"
my $local_ffdb           = undef; #/bueno_not_backed_up/sharpton/MRC_ffdb/"; #where will we store project, result and HMM/blast DB data created by this software?
my $local_reference_ffdb = "/bueno_not_backed_up/sharpton/sifting_families/"; # Location of the reference flatfile data (HMMs, aligns, seqs for each family). The subdirectories for the above should be fci_N, where N is the family construction_id in the Sfams database that points to the families encoded in the dir. Below that are HMMs/ aligns/ seqs/ (seqs for blast), with a file for each family (by famid) within each.

if (!exists($ENV{'MRC_LOCAL'})) {
    print STDOUT ("[ERROR]: The MRC_LOCAL environment variable was NOT EXPORTED and is UNDEFINED.\n");
    print STDOUT ("[ERROR]: MRC_LOCAL needs to be defined as the local code directory where the MRC files are located.\n");
    print STDOUT ("[ERROR]: This is where you'll do the github checkout, if you haven't already.\n");
    print STDOUT ("[ERROR]: I recommend setting it to a location in your home directory. Example: export MRC_LOCAL='/some/location/MRC'\n");
    die "Environment variable MRC_LOCAL must be EXPORTED. Example: export MRC_LOCAL='/path/to/your/directory/for/MRC'\n";
}


my $localScriptDir   = $ENV{'MRC_LOCAL'} . "/scripts" ; # <-- point to the location of the MRC scripts. Auto-detected from MRC_LOCAL variable.

my $project_file   = ""; #where are the project files to be processed?
my $family_subset_list; # path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction, e.g. /home/sharpton/projects/MRC/data/subset_perfect_famids.txt

my $db_username   = undef;
my $db_pass       = undef;
my $db_hostname   = undef;


#remote compute (e.g., SGE) vars
my $is_remote        = 1; # By default, assume we ARE using a remote compute cluster
my $stage            = 0; # By default, do NOT stage the database (this takes a long time)!
my $remote_hostname  = undef; #"chef.compbio.ucsf.edu";
my $remote_user      = undef; #"sharpton";
my $remoteMRCdir     = "/netapp/home/sharpton/projects/MRC"; # added by Alex
my $rffdb            = "/scrapp2/sharpton/MRC/MRC_ffdb/";
#my $rscripts       = "/netapp/home/sharpton/projects/MRC/scripts/"; # this should probably be automatically set to a subdir of rffdb





my $hmm_db_split_size    = 500; #how many HMMs per HMMdb split?
my $blast_db_split_size  = 500; #how many reference seqs per blast db split?
my $nseqs_per_samp_split = 100000; #how many seqs should each sample split file contain?
my @fcis                 = ( 0, 1 ); #what family construction ids are allowed to be processed?
my $db_basename          = "SFams_all_v0"; #set the basename of your database here.
my $hmmdb_name           = $db_basename . "_" . $hmm_db_split_size;
#"SFams_all_v1.03_500"; #e.g., "perfect_fams", what is the name of the hmmdb we'll search against? look in $local_ffdb/HMMdbs/ Might change how this works. If you don't want to use an hmmdb, leave undefined
my $reps_only            = 0; #should we only use representative seqs for each family in the blast db? decreases db size, decreases database diversity
my $nr_db                = 1; #should we build a non-redundant version of the sequence database?
my $blastdb_name; #e.g., "perfect_fams", what is the name of the hmmdb we'll search against? look in $local_ffdb/BLASTdbs/ Might change how this works. If you don't want to use a blastdb, leave undefined

# Auto-generated blast_db name
$blastdb_name = $db_basename . '_' . ($reps_only ? 'reps_' : '') . ($nr_db ? 'nr_' : '') . $blast_db_split_size;

my $hmmdb_build    = 0;
my $blastdb_build  = 0;
my $force_db_build = 0;
my $check          = 0;

#Right now, a single evalue, coverage threshold and strict/tophit are applied to both algorithms
my $evalue         = 0.001; #a float
#my $coverage       = 0.8;
my $coverage       = 0; #between 0-1
my $score          = 85; #optionally set
my $is_strict      = 1; #strict (single classification per read, e.g. top hit) v. fuzzy (all hits passing thresholds) clustering. 1 = strict. 0 = fuzzy. Fuzzy not yet implemented!
my $top_hit        = 1;
my $top_hit_type   = "read"; # "orf" or "read" Read means each read can have one hit. Orf means each orf can have one hit.

my $use_hmmscan    = 0; #should we use hmmscan to compare profiles to reads?
my $use_hmmsearch  = 0; #should we use hmmsearch to compare profiles to reads?
my $use_blast      = 0; #should we use blast to compare SFam reference sequences to reads?
my $use_last       = 1; #should we use last to compare SFam reference sequences to reads?

my $waittime       = 30;
my $input_pid      = undef;
my $goto           = undef; #B=Build HMMdb

my $scratch              = 0; #should we use scratch space on remote machine?
my $multi                = 1; #should we multiload our inserts to the database?
my $bulk_insert_count    = 1000;
my $database_name        = "Sfams_hmp"; #lite";   #might have multiple DBs with same schema.  Which do you want to use here
my $schema_name          = "Sfams"; #eventually, we'll need to disjoin schema and DB name (they'll all use Sfams schema, but have diff DB names)
my $split_orfs           = 1; #should we split translated reads on stop codons? Split seqs are inserted into table as orfs

my $verbose              = 0; # Print extra diagnostic info?
my $dryRun             = 0; # Is this just a "fake" run, not a real one?

#hacky hardcoding on mh_scaffold pilot 2 to test random die bug...
my %skip_samps = ();

#Need to set up command line args for running blast

#	   ,    "s=s"   => \$localScriptDir  # specify this with the environment variable MRC_LOCAL instead of using a parameter


# example command:


# --dbuser=alexgw --dbpass=$PASS --dbhost=lighthouse.ucsf.edu

GetOptions("ffdb|d=s"        => \$local_ffdb
	   , "refdb=s"       => \$local_reference_ffdb
	   , "projdir|i=s"   => \$project_file

	   # Database-server related variables
	   , "dbuser|u=s"   => \$db_username
	   , "dbpass|p=s"   => \$db_pass
	   , "dbhost=s"     => \$db_hostname

	   # Remote computational cluster server related variables
	   , "rhost=s"     => \$remote_hostname
	   , "ruser=s"     => \$remote_user
	   , "rdir=s"      => \$rffdb

	   , 's' => sub { dieWithUsageError("-s is no longer a valid option. Instead, remove it from the command line and export the 'MRC_LOCAL' environment variable to point to your local MRC directory.\nExample of what you could type in bash:  export MRC_LOCAL=/your/home/location/MRC\n"); }
	   ,    "hmmdb|h=s"   => \$hmmdb_name
	   ,    "blastdb|b=s"   => \$blastdb_name

	   ,    "sub=s" => \$family_subset_list

	   ,    "stage!"      => \$stage # should we "stage" the database onto the remote machine?
	   ,    "hdb!"   => \$hmmdb_build
	   ,    "bdb!"   => \$blastdb_build
	   ,    "forcedb!"     => \$force_db_build

	   ,    "hmmsplit|n=i"   => \$hmm_db_split_size
	   ,    "wait|w=i"   => \$waittime        #   <-- in seconds
	   ,    "remote!"     => \$is_remote
	   ,    "pid=i"      => \$input_pid
	   ,    "goto|g=s"   => \$goto
	   ,    "z=i"          => \$nseqs_per_samp_split

	   ,    "e=f"  => \$evalue
	   ,    "c=f"  => \$coverage
	   ,    "verbose|v!" => \$verbose
	   
	   ,    "dryrun|dry!" => \$dryRun
    );


my $remoteScriptDir       = "${remoteMRCdir}/scripts"; # this should probably be automatically set to a subdir of rffdb


### =========== SANITY CHECKING OF INPUT ARGUMENTS ==========

# perl ./MRC/scripts/mrc_handler.pl --dbuser=alexgw --dbpass=$PASS --dbhost=lighthouse.ucsf.edu --rhost=chef.compbio.ucsf.edu --ruser=alexgw  -i ./MRC/data/randsamp_subset_perfect_2/

(defined($local_ffdb)) or dieWithUsageError("--ffdb (local flat-file database directory path) must be specified! Example: --ffdb=/some/local/path/MRC_ffdb (or use the shorter '-d' option to specify it. This used to be hard-coded as being in /bueno_not_backed_up/sharpton/MRC_ffdb/");
(-d ($local_ffdb)) or dieWithUsageError("--ffdb (local flat-file database directory path) was specified as --ffdb='$local_ffdb', but that directory appeared not to exist! Specify a directory that exists.");

(defined($local_reference_ffdb)) or dieWithUsageError("--refdb (local REFERENCE flat-file database directory path) must be specified! Example: --ffdb=/some/local/path/MRC_ffdb (or use the shorter '-d' option to specify it. This used to be hard-coded as being in /bueno_not_backed_up/sharpton/sifting_families/");
(-d ($local_reference_ffdb)) or dieWithUsageError("--refdb (local REFERENCE flat-file database directory path) was specified as --ffdb='$local_ffdb', but that directory appeared not to exist! Specify a directory that exists.");

(defined($db_hostname)) or dieWithUsageError("--dbhost (remote database hostname: example --dbhost='data.youruniversity.edu') MUST be specified!");
(defined($db_username)) or dieWithUsageError("--dbuser (remote database mysql username: example --dbuser='dataperson') MUST be specified!");
(defined($db_pass))     or dieWithUsageError("--dbpass (remote database mysql password for user --dbpass='$db_username') MUST be specified here in super-insecure plaintext,\nunless your database does not require a password, which is unusual. If it really is the case that you require NO password, you should specify --dbpass='' . ...");

(defined($remote_hostname)) or dieWithUsageError("--rhost (remote computational cluster primary note) must be specified. Example --rhost='main.cluster.youruniversity.edu')!");
(defined($remote_user))     or dieWithUsageError("--ruser (remote computational cluster username) must be specified. Example username: --ruser='someguy'!");

if ((defined($goto) && $goto) && !defined($input_pid)) { dieWithUsageError("If you specify --goto=SOMETHING, you must ALSO specify the --pid to goto!"); }

### =========== SANITY CHECKING OF INPUT ARGUMENTS ==========

#try to detect if we need to stage the database or not on the remote server based on runtime options
if ($is_remote and ($hmmdb_build or $blastdb_build)) {
    #$stage = 1;
    dieWithUsageError("If you specify hmm_build or blastdb_build AND you are using a remote server, you MUST specify the --stage option to copy/re-stage the database on the remote machine!");
}

print(printhead("Starting classification run, processing $project_file\n"));

#Initialize the project
my $analysis = MRC->new();
$analysis->set_scripts_dir( $localScriptDir );

#Get a DB connection 
$analysis->set_dbi_connection( "DBI:mysql:$database_name:$db_hostname" );
$analysis->set_username( $db_username );
$analysis->set_password( $db_pass );
$analysis->schema_name( $schema_name );
$analysis->build_schema();
$analysis->multi_load( $multi );
$analysis->bulk_insert_count( $bulk_insert_count );

#Connect to the flat file database
$analysis->set_ffdb( $local_ffdb );
$analysis->set_ref_ffdb( $local_reference_ffdb );
$analysis->set_fcis( \@fcis );

#constrain analysis to a set of families of interest
$analysis->set_family_subset( $family_subset_list, $check );
if ($use_hmmscan || $use_hmmsearch) {
    $analysis->set_hmmdb_name( $hmmdb_name );
}

if ($use_blast || $use_last) {
    $analysis->set_blastdb_name( $blastdb_name );
}

$analysis->is_remote($is_remote);
#set some clustering definitions here
$analysis->is_strict_clustering( $is_strict );
$analysis->set_evalue_threshold( $evalue );
$analysis->set_coverage_threshold( $coverage );
$analysis->set_score_threshold( $score );

#if using a remote server for compute, set vars here
if ($is_remote) {
    $analysis->set_remote_server( $remote_hostname );
    $analysis->set_remote_username( $remote_user );
    $analysis->set_remote_ffdb( $rffdb );
    $analysis->set_remote_scripts( $remoteScriptDir );
    $analysis->build_remote_ffdb( $verbose ); #checks if necessary to build and then builds
}

print("Starting a classification run using the following settings:\n");
($use_last) && print("* Algorithm: last\n");
($use_blast) && print("* Algorithm: blast\n");
($use_hmmscan) && print("* Algorithm: hmmscan\n");
($use_hmmsearch) && print("* Algorithm: hmmsearch\n");
print("* Evalue threshold: ${evalue}\n");
print("* Coverage threshold: ${coverage}\n");



## If the user has specified something in the --goto option, then we skip some parts of the analysis and go directly
## to the "skip to this part" part.
## Note that this is only useful if we have a process ID! 
## block tries to jump to a module in handler for project that has already done some work
if (defined($input_pid) && $input_pid && defined($goto) && $goto) {
    $analysis->MRC::Run::back_load_project($input_pid);
    #this is a little hacky...come clean this up!
    #$analysis->MRC::Run::get_part_samples( $project_file );
    $analysis->MRC::Run::back_load_samples();
    $goto = uc($goto); ## upper case it
    if ($goto eq "B" or $goto eq "BUILD"){ warn "Skipping to HMMdb building step!\n"; goto BUILDHMMDB; }
    if ($goto eq "R" or $goto eq "REMOTE"){ warn "Skipping to staging remote server step!\n"; goto REMOTESTAGE; }
    if ($goto eq "S" or $goto eq "SCRIPT"){ warn "Skipping to building hmmscan script step!\n"; goto BUILDHMMSCRIPT; }
    if ($goto eq "H" or $goto eq "HMM"){ warn "Skipping to hmmscan step!\n"; goto HMMSCAN; }
    if ($goto eq "G" or $goto eq "GET"){ warn "Skipping to get remote hmmscan results step!\n"; goto GETRESULTS; }
    if ($goto eq "C" or $goto eq "CLASSIFY"){ warn "Skipping to classifying reads step!\n"; goto CLASSIFYREADS; }
    if ($goto eq "O" or $goto eq "OUTPUT"){ warn "Skipping to producing output step!\n"; goto CALCDIVERSITY; }
    
    die "Invalid --goto option (specifically, the option was \"$goto\"). If we got to here in the code, it means there was an INVALID FLAG PASSED TO THE GOTO OPTION.";
}


#LOAD PROJECT, SAMPLES, METAREADS
#Grab the samples associated with the project
if (-d $project_file) {
    print printhead( "LOADING PROJECT" );
    #Partitioned samples project
    #get the samples associated with project. a project description can be left in DESCRIPT.txt
    $analysis->MRC::Run::get_partitioned_samples( $project_file );
    ############
    #come back and add a check that ensures sequences associated with samples
    #are of the proper format. We should check data before loading.
    ############
    #Load Data. Project id becomes a project var in load_project
    $analysis->MRC::Run::load_project( $project_file, $nseqs_per_samp_split );
    if ($is_remote){
	$analysis->MRC::Run::load_project_remote( $analysis->get_project_id() );
	$analysis->set_remote_hmmscan_script( $analysis->get_remote_project_path() . "run_hmmscan.sh" );
	$analysis->set_remote_hmmsearch_script( $analysis->get_remote_project_path() . "run_hmmsearch.sh" );
	$analysis->set_remote_blast_script( $analysis->get_remote_project_path() . "run_blast.sh" );
	$analysis->set_remote_last_script( $analysis->get_remote_project_path() . "run_last.sh" );
	$analysis->set_remote_formatdb_script( $analysis->get_remote_project_path() . "run_formatdb.sh" );
	$analysis->set_remote_lastdb_script( $analysis->get_remote_project_path() . "run_lastdb.sh" );
	$analysis->set_remote_project_log_dir( $analysis->get_remote_project_path() . "/logs/" );
    }
} else {
    die("Must provide a properly structured project directory. Sadly, the specified directory <$project_file> did not appear to exist! Cannot continue!\n");
}

#TRANSLATE READS
#at this point, project, samples and metareads are loaded into the DB.
#translate the metareads
if ($is_remote) {
    #run transeq remotely, check on SGE job status, pull results back locally once job complete.
    print printhead( "TRANSLATING READS" );
    my $remote_logs = $analysis->get_remote_project_path() . "/logs/";
    if ($dryRun) { print "[Dry run]: in a real run, we would have translated reads here.\n"; }
    else { $analysis->MRC::Run::translate_reads_remote( $waittime, $remote_logs, $split_orfs );	}
} else {
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	my $projID = $analysis->get_project_id();
	my $sample_reads = "${local_ffdb}/projects/$projID/${sample_id}/raw/";
	my $orfs_file     = "${local_ffdb}/projects/$projID/${sample_id}/orfs/";
	#could do some file splitting here to speed up the remote compute
	if ($dryRun) { print "[Dry run]: in a real run, we would have translated reads here.\n"; }
	else { $analysis->MRC::Run::translate_reads( $sample_reads, $orfs_file ); }
    }
}

#LOAD ORFS
#reads are translated, now load them into the DB
print printhead( "LOADING TRANSLATED READS" );
foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
    my $projID = $analysis->get_project_id();
    my $in_orf_dir = "$local_ffdb/projects/$projID/$sample_id/orfs/";
    my $orfCount = 0;
    foreach my $in_orfs( @{ $analysis->MRC::DB::get_split_sequence_paths( $in_orf_dir, 1 ) } ){
	print "Processing orfs in $in_orfs\n";
	my $orfs = Bio::SeqIO->new( -file => $in_orfs, -format => 'fasta' );
	if ( $analysis->multi_load ){
	    my $trans_algo = ($split_orfs) ? "transeq_split" : "transeq";
	    $analysis->MRC::Run::load_multi_orfs( $orfs, $sample_id, $trans_algo );
	}
	else{
	    while(my $orf = $orfs->next_seq()) {
		my $orf_alt_id  = $orf->display_id();
		my $read_alt_id = MRC::Run::parse_orf_id( $orf_alt_id, "transeq" );
		$analysis->MRC::Run::load_orf( $orf_alt_id, $read_alt_id, $sample_id );
		$orfCount++;
		print "Added $orfCount orfs to the DB\n";
	    }
	}
    }
}

    
### ====================================================================
BUILDHMMDB:
    ; # <-- this keeps emacs from indenting the code stupidly. Ugh!
if (!$hmmdb_build) {
    if (! (-d $analysis->MRC::DB::get_hmmdb_path())) {
	print "The hmm database path did not exist, BUT we did not specify the --hdb option to build a database.";
	print "Apparently we MUST create the database if it does not already exist? Quitting now.";
	die "The hmm database path did not exist, BUT we did not specify the --hdb option to build a database. We should specify --hdb probably.";
	#$hmmdb_build = 1;
    }
}

if ($hmmdb_build){
    if (!$use_hmmscan && !$use_hmmsearch ){
	warn("It seems that you want to build an hmm database, but you aren't invoking hmmscan or hmmsearch. While I will continue, you should check your settings to make certain you aren't making a mistake.\n" );
    }
    print printhead( "BUILDING HMM DATABASE" );
    $analysis->MRC::Run::build_search_db( $hmmdb_name, $hmm_db_split_size, $force_db_build, "hmm" );
}

if (!$blastdb_build) {
    if (! -d $analysis->MRC::DB::get_blastdb_path() ) {
	print "The blast database path did not exist, BUT we did not specify the --bdb option to build a database.";
	print "Apparently we MUST create the database if it does not already exist? Quitting now.";
	die "The blast database path did not exist, BUT we did not specify the --bdb option to build a database. We should specify --bdb probably.";
	#$blastdb_build = 1;
    }	
}

if ($blastdb_build) {
    if ( !$use_blast && !$use_last){
	warn( "It seems that you want to build a blast database, but you aren't invoking blast or last. While I will continue, you should check your settings to make certain you aren't making a mistake.\n" );
    }
    print printhead( "BUILDING BLAST DATABASE" );
    #need to build the nr module here
    $analysis->MRC::Run::build_search_db( $blastdb_name, $blast_db_split_size, $force_db_build, "blast", $reps_only, $nr_db );
}

### ====================================================================
REMOTESTAGE:
if ($is_remote && $stage){
    print printhead("STAGING REMOTE SEARCH DATABASE");
    if ( defined( $hmmdb_name ) && ( $use_hmmsearch || $use_hmmscan ) ){
	$analysis->MRC::Run::remote_transfer_search_db( $hmmdb_name, "hmm" );
	if (!$scratch){
	    print "Not using remote scratch space, apparently... I guess there is some gunzipping going on?\n";
	    #should do optimization here
	    $analysis->MRC::Run::gunzip_remote_dbs( $hmmdb_name, "hmm" );
	} else {
	    print "Using remote scratch space, apparently...\n";
	}
    }

    my $projID = $analysis->get_project_id();
    if ( defined( $blastdb_name ) && ( $use_blast || $use_last ) ){
	$analysis->MRC::Run::remote_transfer_search_db( $blastdb_name, "blast" );
	#should do optimization here. Also, should roll over to blast+
	$analysis->MRC::Run::gunzip_remote_dbs( $blastdb_name, "blast" );
	if ($use_blast){
	    print "Building remote formatdb script...\n";
	    my $formatdb_script_path = "$local_ffdb/projects/$projID/run_formatdb.sh";
	    my $r_script_path        = $analysis->get_remote_formatdb_script();
	    my $n_blastdb_splits     = $analysis->MRC::DB::get_number_db_splits( "blast" );
	    build_remote_formatdb_script( $formatdb_script_path, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch );
	    $analysis->MRC::Run::remote_transfer( $formatdb_script_path, $analysis->get_remote_username . "@" . $analysis->get_remote_server . ":" . $r_script_path, "f" );
	    $analysis->MRC::Run::format_remote_blast_dbs( $r_script_path );
	}
	if ($use_last){
	    print "Building remote lastdb script...\n";
	    my $lastdb_script     = "$local_ffdb/projects/$projID/run_lastdb.sh";
	    my $r_script_path     = $analysis->get_remote_lastdb_script();
	    my $n_blastdb_splits  = $analysis->MRC::DB::get_number_db_splits( "blast" );
	    build_remote_lastdb_script( $lastdb_script, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch );
	    $analysis->MRC::Run::remote_transfer( $lastdb_script, $analysis->get_remote_username . "@" . $analysis->get_remote_server . ":" . $r_script_path, "f" );
	    #we can use the blast code here 
	    $analysis->MRC::Run::format_remote_blast_dbs( $r_script_path );
	}
    }
}

### ====================================================================
BUILDHMMSCRIPT:
if ($is_remote) {
    my $projID = $analysis->get_project_id();
    if ( $use_hmmscan ){
	print printhead( "BUILDING REMOTE HMMSCAN SCRIPT" );
	my $h_script_path   = "$local_ffdb/projects/$projID/run_hmmscan.sh";
	my $r_h_script_path = $analysis->get_remote_hmmscan_script();
	my $n_hmm_searches  = $analysis->MRC::DB::get_number_hmmdb_scans( $hmm_db_split_size );
	print "number of hmm searches: $n_hmm_searches\n";
	my $n_hmmdb_splits  = $analysis->MRC::DB::get_number_db_splits( "hmm" );
	print "number of hmm splits: $n_hmmdb_splits\n";
	build_remote_hmmscan_script( $h_script_path, $n_hmm_searches, $hmmdb_name, $n_hmmdb_splits, $analysis->get_remote_project_path() );
	$analysis->MRC::Run::remote_transfer( $h_script_path, $analysis->get_remote_username . "@" . $analysis->get_remote_server . ":" . $r_h_script_path, "f" );
    }
    if ( $use_hmmsearch ){
	print printhead( "BUILDING REMOTE HMMSEARCH SCRIPT" );
	my $h_script_path   = "$local_ffdb/projects/$projID/run_hmmsearch.sh";
	my $r_h_script_path = $analysis->get_remote_hmmsearch_script();
#	my $n_hmm_searches  = $analysis->MRC::DB::get_number_hmmdb_scans( $hmm_db_split_size );
	my $n_sequences     = $analysis->MRC::DB::get_number_sequences( $nseqs_per_samp_split );
	print "number of searches: $n_sequences\n";
	my $n_hmmdb_splits  = $analysis->MRC::DB::get_number_db_splits( "hmm" );
	print "number of hmmdb splits: $n_hmmdb_splits\n";
	build_remote_hmmsearch_script( $h_script_path, $n_sequences, $hmmdb_name, $n_hmmdb_splits, $analysis->get_remote_project_path(), $scratch );
	$analysis->MRC::Run::remote_transfer( $h_script_path, $analysis->get_remote_username . "@" . $analysis->get_remote_server . ":" . $r_h_script_path, "f" );
    }
    if ( $use_blast ){
	print printhead( "BUILDING REMOTE BLAST SCRIPT" );
	my $b_script_path     = "$local_ffdb/projects/$projID/run_blast.sh";
	my $r_b_script_path   = $analysis->get_remote_blast_script();
	my $db_length         = $analysis->MRC::DB::get_blast_db_length( $blastdb_name );
	print "database length is $db_length\n";
	my $n_blastdb_splits  = $analysis->MRC::DB::get_number_db_splits( "blast" );
	print "number of blast db splits: $n_blastdb_splits\n";
	build_remote_blastsearch_script( $b_script_path, $db_length, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch );
	$analysis->MRC::Run::remote_transfer( $b_script_path, $analysis->get_remote_username . "@" . $analysis->get_remote_server . ":" . $r_b_script_path, "f" );
    }
    if ( $use_last ){
	print printhead( "BUILDING REMOTE LAST SCRIPT" );
	#we use the blast script code as a template given the similarity between the methods, so there are some common var names between the block here and above
	my $b_script_path     = "$local_ffdb/projects/$projID/run_last.sh";
	my $r_b_script_path   = $analysis->get_remote_last_script();
	my $db_length         = $analysis->MRC::DB::get_blast_db_length( $blastdb_name );
	print "database length is $db_length\n";
	my $n_blastdb_splits  = $analysis->MRC::DB::get_number_db_splits( "blast" );
	print "number of last db splits: $n_blastdb_splits\n";
	#built
	build_remote_lastsearch_script( $b_script_path, $db_length, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch );
	$analysis->MRC::Run::remote_transfer( $b_script_path, $analysis->get_remote_username . "@" . $analysis->get_remote_server . ":" . $r_b_script_path, "f" );
    }
}

### ====================================================================
#RUN HMMSCAN
HMMSCAN:
if ($is_remote){
    print printhead( "RUNNING REMOTE SEARCH" );
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	($use_hmmscan)   && $analysis->MRC::Run::run_search_remote( $sample_id, "hmmscan",   $waittime, $verbose);
	($use_blast)     && $analysis->MRC::Run::run_search_remote( $sample_id, "blast",     $waittime, $verbose);
	($use_hmmsearch) && $analysis->MRC::Run::run_search_remote( $sample_id, "hmmsearch", $waittime, $verbose);
	($use_last)      && $analysis->MRC::Run::run_search_remote( $sample_id, "last",      $waittime, $verbose);
	print "Progress report: finished ${sample_id} on " . `date` . "\n";
    }  
} else {
    print printhead( "RUNNING LOCAL SEARCH" );
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	my $sample_path = $local_ffdb . "/projects/" . $analysis->get_project_id() . "/" . $sample_id . "/";
	my $orfs        = "orfs.fa";
	my $results_dir = "search_results";
	my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs( $hmmdb_name ) };
	warn "Running hmmscan for sample ID ${sample_id}...\n";
	foreach my $hmmdb( keys( %hmmdbs ) ){
	    my $results = "${results_dir}/${sample_id}_v_${hmmdb}.hsc";
	    #run with tblast output format (e.g., --domtblout )
	    $analysis->MRC::Run::run_hmmscan( $orfs, $hmmdbs{$hmmdb}, $results, 1 );
#	    $analysis->MRC::Run::run_hmmscan( $orfs, $hmmdbs{$hmmdb}, $results );
	}
    }
}

### ====================================================================
#GET REMOTE RESULTS
GETRESULTS:
if ($is_remote){
    print printhead("GETTING REMOTE RESULTS");
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	($use_hmmscan)   && $analysis->MRC::Run::get_remote_search_results( $sample_id, "hmmscan");
	($use_blast)     && $analysis->MRC::Run::get_remote_search_results( $sample_id, "blast");
	($use_hmmsearch) && $analysis->MRC::Run::get_remote_search_results( $sample_id, "hmmsearch");
	($use_last)      && $analysis->MRC::Run::get_remote_search_results( $sample_id, "last");
    }
}

### ====================================================================
#PARSE AND LOAD RESULTS
CLASSIFYREADS:
if ($is_remote){
    print printhead( "CLASSIFYING REMOTE SEARCH RESULTS" );
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	if ( defined( $skip_samps{ $sample_id } ) ){
	    print( "skipping $sample_id because it has been processed\n" );
	    next;
	}
	print "Classifying reads for sample $sample_id\n";
	my $path_to_split_orfs = $analysis->get_sample_path( $sample_id ) . "/orfs/";
	foreach my $orf_split_file_name( @{ $analysis->MRC::DB::get_split_sequence_paths( $path_to_split_orfs , 0 ) } ) {
	    if ( $use_hmmscan ){
		my $algo = "hmmscan";
		my $class_id = $analysis->MRC::DB::get_classification_id( 
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		$analysis->MRC::Run::classify_reads( $sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type );
	    }
	    if ( $use_hmmsearch ){
		my $algo = "hmmsearch";
		my $class_id = $analysis->MRC::DB::get_classification_id( 
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		$analysis->MRC::Run::classify_reads( $sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type );
	    }
	    if ( $use_blast ){
		my $algo = "blast";
		my $class_id = $analysis->MRC::DB::get_classification_id( 
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $blastdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		$analysis->MRC::Run::classify_reads( $sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type );
	    }	    
	    if ( $use_last ){
		my $algo = "last";
		my $class_id = $analysis->MRC::DB::get_classification_id( 
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $blastdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		#build this routine
		$analysis->MRC::Run::classify_reads( $sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type );
	    }	    
	}
   }
} else{
    print printhead("CLASSIFYING LOCAL SEARCH RESULTS ?? This is 'deprecated' apparently and maybe hasn't been tested recently?");
    #this block is deprecated...
    foreach my $sample_id( @{ $analysis->get_sample_ids() } ){
	my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs( $hmmdb_name ) };
	foreach my $hmmdb( keys( %hmmdbs ) ){
	    my $projID = $analysis->get_project_id();
	    my $hsc_results = "$local_ffdb/projects/$projID/$sample_id/search_results/${sample_id}_v_${hmmdb}.hsc";
	    $analysis->MRC::Run::classify_reads( $sample_id, $hsc_results, $evalue, $coverage );
	}
    }
}

#die "apparently we die here before calculating diversity statistics for some reason";

### ====================================================================
#calculate diversity statistics
CALCDIVERSITY:
print printhead( "CALCULATING DIVERSITY STATISTICS" );
#note, we could decrease DB pings by merging some of these together (they frequently leverage same hash structure)
#might need to include classification_id as a call here;
if ( $use_hmmscan ){
    print "Calculating hmmscan diversity\n";
    my $algo = "hmmscan";
    my $class_id = $analysis->MRC::DB::get_classification_id( 
	$analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
	)->classification_id();
    calculate_diversity( $analysis, $class_id );
}

if ( $use_hmmsearch ){
    print "Calculating hmmsearch diversity\n";
    my $algo = "hmmsearch";
    my $class_id = $analysis->MRC::DB::get_classification_id( 
	$analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
	)->classification_id();
    calculate_diversity( $analysis, $class_id );
}

if ( $use_blast ){
    print "Calculating blast diversity\n";
    my $algo = "blast";
    my $class_id = $analysis->MRC::DB::get_classification_id( 
	$analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $blastdb_name, $algo, $top_hit_type,
	)->classification_id();
    calculate_diversity( $analysis, $class_id );
}
### ====================================================================




printhead("ANALYSIS COMPLETED!\n");


### ============== MAIN CODE THAT GETS CALLED EVERY TIME: ABOVE =========================

### ================================== FUNCTIONS BELOW ==================================

sub calculate_diversity {
    my($analysis, $class_id) = @_;
    print "project richness...\n";
    $analysis->MRC::Run::calculate_project_richness( $class_id );
    print "project relative abundance...\n";
    $analysis->MRC::Run::calculate_project_relative_abundance( $class_id );
    print "per-sample richness...\n";
    $analysis->MRC::Run::calculate_sample_richness( $class_id );
    print "per-sample relative abundance..\n";
    $analysis->MRC::Run::calculate_sample_relative_abundance( $class_id );
    print "building classification map...\n";
    $analysis->MRC::Run::build_classification_map( $class_id );
    print "building PCA dataframe...\n";
    $analysis->MRC::Run::build_PCA_data_frame( $class_id );
}


sub build_remote_hmmscan_script{
    my($h_script_path, $n_searches, $hmmdb_basename, $n_splits, $project_path, $scratch) = @_;
    my @args = ( "build_remote_hmmscan_script.pl", "-z $n_searches", "-o $h_script_path", "-n $n_splits", "--name $hmmdb_basename", "-p $project_path", "-s $scratch" );
    my $results = IPC::System::Simple::capture( "perl " . "@args" );
    if ( $EXITVAL != 0 ){
	warn( $results );
	exit(0);
    }
    return $results;
}

sub build_remote_hmmsearch_script{
    my ($h_script_path, $n_searches, $hmmdb_basename, $n_splits, $project_path, $scratch) = @_;
    my @args = ( "build_remote_hmmsearch_script.pl", "-z $n_searches", "-o $h_script_path", "-n $n_splits", "--name $hmmdb_basename", "-p $project_path", "-s $scratch" );
    print("perl " . "@args\n" );
    my $results = IPC::System::Simple::capture( "perl " . "@args" );
    if ( $EXITVAL != 0 ){
	warn( $results );
	exit(0);
    }
    return $results;
}

sub build_remote_blastsearch_script{
    my ( $b_script_path, $db_length, $blastdb_basename, $n_splits, $project_path, $scratch ) = @_;
    my @args = ( "build_remote_blast_script.pl", "-z $db_length", "-o $b_script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch" );
    print("perl @args\n");
    my $results = IPC::System::Simple::capture( "perl " . "@args" );
    if ( $EXITVAL != 0 ){
	warn( $results );
	exit(0);
    }
    return $results;
}

#need to build
sub build_remote_lastsearch_script {
    my ( $b_script_path, $db_length, $blastdb_basename, $n_splits, $project_path, $scratch ) = @_;
    my @args = ( "build_remote_last_script.pl", "-z $db_length", "-o $b_script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch" );
    print("perl @args\n");
    my $results = IPC::System::Simple::capture( "perl " . "@args" );
    if ( $EXITVAL != 0 ){
	warn( $results );
	exit(0);
    }
    return $results;
}

sub build_remote_formatdb_script {
    my ( $script_path, $blastdb_basename, $n_splits, $project_path, $scratch ) = @_;
    my @args = ( "build_remote_formatdb_script.pl", "-o $script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch" );
    print( "perl " . "@args\n" );
    my $results = IPC::System::Simple::capture( "perl " . "@args" );
    if ( $EXITVAL != 0 ){
	warn( $results );
	exit(0);
    }
    return $results;    
}

sub build_remote_lastdb_script {
    my ( $script_path, $blastdb_basename, $n_splits, $project_path, $scratch ) = @_;
    my @args = ( "build_remote_lastdb_script.pl", "-o $script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch" );
    print( "perl " . "@args\n" );
    my $results = IPC::System::Simple::capture( "perl " . "@args" );
    if ( $EXITVAL != 0 ){
	warn( $results );
	exit(0);
    }
    return $results;    
}

sub printhead {
    my ($string) = @_;
    my $dateStr = `date`;
    chomp($string); # remove any ending-of-string newline that might be there
    chomp($dateStr); # remote always-there newline from the `date` command
    my $stringWithDate = $string . " ($dateStr)";
    my $pad  = "#" x (length($stringWithDate) + 4); # add four to account for extra # and whitespce on either side of string
    return("$pad\n" . "# " . $stringWithDate . " #\n" . "$pad\n");
}


__DATA__

mrc_handler.pl  [OPTIONS]

Last updated Feb 2013.

MRC (Metagenomics Read Classifier) program by Tom Sharpton.

Handles a bunch of database and cluster stuff.

See the examples below for more information.

EXAMPLES:

perl mrc_handler.pl --something --something

(put some examples here)

OPTIONS:

--ffdb=/PATH/TO/FLATFILES  (or -d /PATH/TO/FLATFILES)     (REQUIRED argument)
    local flat file database path


--refdb=/PATH/TO/REFERENCE/FLATFILES     (REQUIRED argument)
    Location of the reference flatfile data (HMMs, aligns, seqs for each family). The subdirectories for the above should be fci_N, where N is the family construction_id in the Sfams database that points to the families encoded in the dir. Below that are HMMs/ aligns/ seqs/ (seqs for blast), with a file for each family (by famid) within each.

--projdir=/PATH/TO/PROJECT/DIR (or -i /PATH/TO/PROJECT/DIR)     (REQUIRED argument)
    project directory? Local?

DATABASE ARGUMENTS:

--dbhost=YOUR.DATABASE.SERVER.COM           (REQUIRED argument)
    The machine that hosts the remote MySQL database.

--dbuser=MYSQL_USERNAME                     (REQUIRED argument)
    MySQL username for logging into mysql on the remote database server.

--dbpass=MYSQL_PASSWORD (in plain text)     (REQUIRED argument)
    The MySQL password for <dbuser>, on the remote database server.
    This is NOT VERY SECURE!!! Note, in particular, that it gets saved in your teminal history.

REMOTE COMPUTATIONAL CLUSTER ARGUMENTS:

--rhost=SOME.CLUSTER.HEAD.NODE.COM     (REQUIRED argument)
    The machine that manages the remote computational cluster. Usually this is a cluster head node.

--ruser=USERNAME                       (REQUIRED argument)
    Remote username for logging into the remote computational cluster / machine.
    Note that you have to set up passphrase-less SSH for this to work. Google it!

--rdir=/PATH/ON/REMOTE/SERVER
    Remote path where we will save results

--remote  (Default: ENABLED)
    (or --noremote to disable it)
    Use a remote compute cluster. Specify --noremote to run locally (note: local running has NOT BEEN DEBUGGED much!)



--hmmdb=STRING (or -h STRING)
   HMM database name

--blastdb=STRING (or -b STRING)
   BLAST database name

--sub=STRING
    Not sure what this is. ("FAMILY SUBSET LIST")

--stage  (Default: disabled (no staging))
    Causes the remote database to get copied, I think. Slow!

--dryrun or --dry (Default: disabled)
    If this is specified, then we do not ACTUALLY run any commands, we just print what we WOULD have ideally run.

--hdb
    Should we build the hmm db?

--bdb
    Should we build the blast db?

--forcedb
    Force database build.

-n INTEGER
    HMM database split size.

--wait=SECONDS (or -w SECONDS)
    How long to wait for... something.


--pid=INTEGER
    Process ID for something (?)

--goto=STRING
    Go to a specific step in the computation.
    Valid options are:
      * 'B' or 'BUILD'
      * 'R' or 'REMOTE'
      * 'S' or 'SCRIPT'
      * 'H' or 'HMM'
      * 'G' or 'GET'
      * 'C' or 'CLASSIFY'
      * 'O' or 'OUTPUT'

-z INTEGER
    n seqs per sample split (??)

-e FLOAT
    E-value

-c FLOAT
    Coverage (?)

--verbose (or -v)
    Output verbose messages.


KNOWN BUGS:

  None known at the moment...

--------------
