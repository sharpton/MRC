#!/usr/bin/perl -w

#mrc_handler.pl - The control script responsible for executing an MRC run.
#Usage: 
#perl mrc_handler.pl -u <username> -p <password> -d <path_to_flat_file_db> -s <path_to_mrc_scripts_directory> -i <path_to_metagenome_data> -h <hmm_database_name> > <path_to_out_log> 2> <path_to_error_log>
#
#Example Usage:
#nohup perl mrc_handler.pl -u username -p password -d /bueno_not_backed_up/sharpton/MRC_ffdb -s ./ -i ../data/randsamp_subset_perfect_2 -h OPFs_all_v1.0 > randsamp_perfect_2.all.out 2> randsamp_perfect_2.all.err &

## examples:
# perl ./MRC/scripts/mrc_handler.pl --dbuser=alexgw --dbpass=$PASS --dbhost=lighthouse.ucsf.edu --rhost=chef.compbio.ucsf.edu --ruser=alexgw --ffdb=/home/alexgw/MRC_ffdb --refdb=/home/alexgw/sifting_families  --projdir=./MRC/data/randsamp_subset_perfect_2/ 

# perl ./MRC/scripts/mrc_handler.pl --dbuser=alexgw --dbpass=$PASS --dbhost=lighthouse.ucsf.edu --rhost=chef.compbio.ucsf.edu --ruser=alexgw --ffdb=/home/alexgw/MRC_ffdb --refdb=/home/alexgw/sifting_families  --projdir=./MRC/data/randsamp_subset_perfect_2/ --dryrun
# perl ./MRC/scripts/mrc_handler.pl --dbuser=alexgw --dbpass=$PASS --dbhost=lighthouse.ucsf.edu --rhost=chef.compbio.ucsf.edu --ruser=alexgw --rdir=/scrapp2/alexgw/MRC --ffdb=/home/alexgw/MRC_ffdb --refdb=/home/alexgw/sifting_families --projdir=./MRC/data/randsamp_subset_perfect_2/

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

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) }; # prints a STACK TRACE whenever there is a fatal error! Very handy

sub dieWithUsageError($) {
    my ($msg) = @_;
    chomp($msg);
    print("[TERMINATED DUE TO USAGE ERROR]: " . $msg . "\n");
    print STDOUT <DATA>;
    die(MRC::safeColor("[TERMINATED DUE TO USAGE ERROR]: " . $msg . " ", "yellow on_red"));
}

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

my $project_dir   = ""; #where are the project files to be processed?
my $family_subset_list; # path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction, e.g. /home/sharpton/projects/MRC/data/subset_perfect_famids.txt

my $db_username   = undef;
my $db_pass       = undef;
my $db_hostname   = undef;

#remote compute (e.g., SGE) vars
my $is_remote        = 1; # By default, assume we ARE using a remote compute cluster
my $stage            = 0; # By default, do NOT stage the database (this takes a long time)!
my $remote_hostname  = undef; #"chef.compbio.ucsf.edu";
my $remote_user      = undef; #"sharpton";
my $remoteDir        = undef;
#my $rscripts       = "/netapp/home/sharpton/projects/MRC/scripts/"; # this should probably be automatically set to a subdir of remote_ffdb

my $hmm_db_split_size    = 500; #how many HMMs per HMMdb split?
my $blast_db_split_size  = 500; #how many reference seqs per blast db split?
my $nseqs_per_samp_split = 100000; #how many seqs should each sample split file contain?
my @fcis                 = (0, 1); #what family construction ids are allowed to be processed?
my $db_prefix_basename   = undef; # "SFams_all_v0"; #set the basename of your database here.
my $hmmdb_name           = undef;
#"SFams_all_v1.03_500"; #e.g., "perfect_fams", what is the name of the hmmdb we'll search against? look in $local_ffdb/HMMdbs/ Might change how this works. If you don't want to use an hmmdb, leave undefined
my $reps_only            = 0; #should we only use representative seqs for each family in the blast db? decreases db size, decreases database diversity
my $nr_db                = 1; #should we build a non-redundant version of the sequence database? For some reason, this is coded to ALWAYS be true.
my $blastdb_name         = undef; #e.g., "perfect_fams", what is the name of the hmmdb we'll search against? look in $local_ffdb/BLASTdbs/ Might change how this works. If you don't want to use a blastdb, leave undefined

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
my $dbname               = undef; #"Sfams_hmp"; #lite";   #might have multiple DBs with same schema.  Which do you want to use here
my $schema_name          = undef; #"Sfams::Schema"; #eventually, we'll need to disjoin schema and DB name (they'll all use Sfams schema, but have diff DB names)
my $split_orfs           = 1; #should we split translated reads on stop codons? Split seqs are inserted into table as orfs

my $verbose              = 0; # Print extra diagnostic info?
my $dryRun               = 0; # <-- (Default: disabled) If this is specified, then we do not ACTUALLY run any commands, we just print what we WOULD have ideally run.

#hacky hardcoding on mh_scaffold pilot 2 to test random die bug...
my %skip_samps = ();

my $extraBrutalClobberingOfDirectories = 0; # By default, don't clobber (meaning "overwrite") directories that already exist.
my $sWasSpecified = undef; # The "s" parameter is no longer valid, so we specially detect it with this variable. This is sorta required; "sub {...}" doesn't actually allow program exit it seems.


#Need to set up command line args for running blast
GetOptions("ffdb|d=s"        => \$local_ffdb
	   , "refdb=s"       => \$local_reference_ffdb
	   , "projdir|i=s"   => \$project_dir

	   # Database-server related variables
	   , "dbuser|u=s"   => \$db_username
	   , "dbpass|p=s"   => \$db_pass
	   , "dbhost=s"     => \$db_hostname
	   , "dbname=s"     => \$dbname
	   , "dbschema=s"   => \$schema_name
	   , "dbprefix=s"   => \$db_prefix_basename

	   # Remote computational cluster server related variables
	   , "rhost=s"     => \$remote_hostname
	   , "ruser=s"     => \$remote_user
	   , "rdir=s"      => \$remoteDir

	   ,              's=s' => \$sWasSpecified #interestingly, you can't have a "sub" here that dies, as execution continues on
	   ,    "hmmdb|h=s"     => \$hmmdb_name
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
	   
	   ,    "clobber" => \$extraBrutalClobberingOfDirectories
	   ,    "dryrun|dry!" => \$dryRun
   );


#warn($dryRun);

#/scrapp2/alexgw/MRC/MRC_ffdb/


### =========== SANITY CHECKING OF INPUT ARGUMENTS ==========

(defined($remoteDir)) or dieWithUsageError("--rdir (remote computational server scratch/flatfile location. Example: --rdir=/cluster/share/yourname/MRC). This is mandatory!");

(!$dryRun) or dieWithUsageError("Sorry, --dryrun is actually not supported, as it's a huge mess right now! My apologies.");
(!defined($sWasSpecified) && !$sWasSpecified) or dieWithUsageError("-s is no longer a valid option. Instead, remove it from the command line and export the 'MRC_LOCAL' environment variable to point to your local MRC directory.\nExample of what you could type in bash instead of the -s option:  export MRC_LOCAL=/your/home/location/MRC");
(defined($local_ffdb)) or dieWithUsageError("--ffdb (local flat-file database directory path) must be specified! Example: --ffdb=/some/local/path/MRC_ffdb (or use the shorter '-d' option to specify it. This used to be hard-coded as being in /bueno_not_backed_up/sharpton/MRC_ffdb");
(-d $local_ffdb)       or dieWithUsageError("--ffdb (local flat-file database directory path) was specified as --ffdb='$local_ffdb', but that directory appeared not to exist! Note that Perl does NOT UNDERSTAND the tilde (~) expansion for home directories, so please specify the full path in that case. You must specify a directory that already exists.");

(defined($local_reference_ffdb)) or dieWithUsageError("--refdb (local REFERENCE flat-file database directory path) must be specified! Example: --ffdb=/some/local/path/MRC_ffdb (or use the shorter '-d' option to specify it. This used to be hard-coded as being in /bueno_not_backed_up/sharpton/sifting_families");
(-d $local_reference_ffdb)       or dieWithUsageError("--refdb (local REFERENCE flat-file database directory path) was specified as --ffdb='$local_ffdb', but that directory appeared not to exist! Note that Perl does NOT UNDERSTAND the tilde (~) expansion for home directories, so please specify the full path in that case. Specify a directory that exists.");

(defined($db_hostname)) or dieWithUsageError("--dbhost (remote database hostname: example --dbhost='data.youruniversity.edu') MUST be specified!");
(defined($db_username)) or dieWithUsageError("--dbuser (remote database mysql username: example --dbuser='dataperson') MUST be specified!");
(defined($db_pass))     or dieWithUsageError("--dbpass (remote database mysql password for user --dbpass='$db_username') MUST be specified here in super-insecure plaintext,\nunless your database does not require a password, which is unusual. If it really is the case that you require NO password, you should specify --dbpass='' . ...");

(defined($remote_hostname)) or dieWithUsageError("--rhost (remote computational cluster primary note) must be specified. Example --rhost='main.cluster.youruniversity.edu')!");
(defined($remote_user))     or dieWithUsageError("--ruser (remote computational cluster username) must be specified. Example username: --ruser='someguy'!");

if ((defined($goto) && $goto) && !defined($input_pid)) { dieWithUsageError("If you specify --goto=SOMETHING, you must ALSO specify the --pid to goto!"); }

#try to detect if we need to stage the database or not on the remote server based on runtime options
if ($is_remote and ($hmmdb_build or $blastdb_build) and !$stage) {
    #$stage = 1;
    dieWithUsageError("If you specify hmm_build or blastdb_build AND you are using a remote server, you MUST specify the --stage option to copy/re-stage the database on the remote machine!");
}

(-d $project_dir) or dieWithUsageError("You must provide a properly structured project directory! Sadly, the specified directory <$project_dir> did not appear to exist, so we cannot continue!\n");



### =========== END OF SANITY CHECKING OF INPUT ARGUMENTS ==========
### =========== Automatic setting of default parameters ========

if (!defined($dbname)) {
    $dbname = "Sfams_hmp";
    warn("Note: --dbname=NAME was not specified on the command line, so we are using the default database name, which is \"$dbname\".");
}

if (!defined($schema_name)) {
    $schema_name = "Sfams::Schema";
    warn("Note: --dbschema=SCHEMA was not specified on the command line, so we are using the default schema name, which is \"$schema_name\".");
}

# Automatically set the blast database name, if the user didn't specify something already.
if (!defined($blastdb_name)) {
    $blastdb_name = $db_prefix_basename . '_' . ($reps_only?'reps_':'') . ($nr_db?'nr_':'') . $blast_db_split_size;
    warn("Note: blastdb_name was not specified on the command line (--blastdb=NAME). Using the default value, which is <$blastdb_name>.");
} 

if (!defined($db_prefix_basename)) {
    $db_prefix_basename = "SFams_all_v0";
    warn("Note: db_prefix_basename (database basename/prefix) was not specified on the command line (--dbprefix=PREFIX). Using the default value, which is <$db_prefix_basename>.");
}

if (!defined($hmmdb_name)) {
    $hmmdb_name = "${db_prefix_basename}_${hmm_db_split_size}";
    warn("Note: hmmdb_name was not specified on the command line (--hmmdb=NAME). Using the default value, which is <$hmmdb_name>.");
}

my $remote_script_dir   = "${remoteDir}/scripts"; # this should probably be automatically set to a subdir of remote_ffdb
my $remote_ffdb_dir     = "${remoteDir}/MRC_ffdb"; #  used to be = "/scrapp2/sharpton/MRC/MRC_ffdb/";
### =========== Automatic setting of default parameters ========



### =========== Warn the user about passphrase-less SSH being a requirement ============
print STDERR "Please remember that you will need passphrase-less SSH set up already.\nNote that if you see a prompt for a password in your connection to <$remote_hostname> below, that would mean that you did not have passphrase-less SSH set up properly. Instructions for setting it up can be found by searching google for the term \"passphraseless ssh\".\n";
my $likely_location_of_ssh_public_key = $ENV{'HOME'} . "/.ssh/id_rsa.pub";
if (!(-s $likely_location_of_ssh_public_key)) {
    print "WARNING: I notice that you do not have an SSH public key (expected to be found in <$likely_location_of_ssh_public_key>), which means you most likely do not have passphrase-less ssh set up with the remote machine (<$remote_hostname>).\n";
}

### =========== Done with pre-processing steps ================

printBanner("Starting classification run, processing $project_dir\n");

my $analysis = MRC->new();  #Initialize the project

$analysis->set_scripts_dir($localScriptDir);
$analysis->set_dbi_connection("DBI:mysql:$dbname:$db_hostname", $dbname, $db_hostname); $analysis->set_username($db_username); $analysis->set_password($db_pass); $analysis->set_schema_name($schema_name);
$analysis->build_schema();
$analysis->set_multiload($multi);
$analysis->set_bulk_insert_count($bulk_insert_count);
$analysis->set_ffdb($local_ffdb); $analysis->set_ref_ffdb($local_reference_ffdb); $analysis->set_fcis(\@fcis); #Connect to the flat file database
$analysis->set_family_subset($family_subset_list, $check); #constrain analysis to a set of families of interest
$analysis->set_hmmdb_name($hmmdb_name); # always set it; why not, right?
$analysis->set_blastdb_name($blastdb_name); # just always set it; why not, right?
$analysis->is_strict_clustering($is_strict); $analysis->set_evalue_threshold($evalue); $analysis->set_coverage_threshold($coverage); $analysis->set_score_threshold($score); 



### =========== NOW THAT THE MRC OBJECT "Analysis" HAS BEEN CREATED, DO SOME SANITY CHECKING ON THE FINAL PARAMETERS =============================
if (!$hmmdb_build && !(-d $analysis->MRC::DB::get_hmmdb_path())) {
    warn("The hmm database path did not exist, BUT we did not specify the --hdb option to build a database.");
    die("The hmm database path did not exist, BUT we did not specify the --hdb option to build a database. We should specify --hdb probably.");
}

if (!$blastdb_build && !(-d $analysis->MRC::DB::get_blastdb_path())) {
    warn("The blast database path did not exist, BUT we did not specify the --bdb option to build a database.");
    die("The blast database path did not exist, BUT we did not specify the --bdb option to build a database. We should specify --bdb probably.");
}
### =========== END OF SANITY CHECKING FOR "Analaysis" ===========================================================================================

#if using a remote server for compute, set vars here

$analysis->is_remote($is_remote);
$analysis->{"clobber"} = $extraBrutalClobberingOfDirectories; # Set a local variable in this "MRC" object

if ($is_remote) {
    $analysis->set_remote_server($remote_hostname);
    $analysis->set_remote_username($remote_user);
    $analysis->set_remote_ffdb($remote_ffdb_dir);
    $analysis->set_remote_script_dir($remote_script_dir);
    if (!$dryRun) {
	$analysis->build_remote_ffdb($verbose); #checks if necessary to build and then builds
    } else {
	MRC::dryNotify("Not setting the remote credentials.");
    }
}

MRC::notify("Starting a classification run using the following settings:\n");
($use_last)      && MRC::notify("   * Algorithm: last\n");
($use_blast)     && MRC::notify("   * Algorithm: blast\n");
($use_hmmscan)   && MRC::notify("   * Algorithm: hmmscan\n");
($use_hmmsearch) && MRC::notify("   * Algorithm: hmmsearch\n");
($stage)         && MRC::notify("   * Staging: Stage the remote database\n");
($is_remote)     && MRC::notify("   * Use the remote server <$remote_hostname>\n");
MRC::notify("   * Evalue threshold: ${evalue}\n");
MRC::notify("   * Coverage threshold: ${coverage}\n");

## If the user has specified something in the --goto option, then we skip some parts of the analysis and go directly
## to the "skip to this part" part.
## Note that this is only useful if we have a process ID! 
## block tries to jump to a module in handler for project that has already done some work
if (defined($goto) && $goto) {
    (defined($input_pid) && $input_pid) or die "You CANNOT specify --goto without also specifying an input PID (--pid=NUMBER).\n";
    if (!$dryRun) {
	$analysis->MRC::Run::back_load_project($input_pid);
	#$analysis->MRC::Run::get_part_samples($project_dir);
	$analysis->MRC::Run::back_load_samples();
    } else {
	MRC::dryNotify("Skipped loading samples.");
    }

    $goto = uc($goto); ## upper case it
    if ($goto eq "B" or $goto eq "BUILD"){ warn "Skipping to HMMdb building step!\n"; goto BUILDHMMDB; }
    if ($goto eq "R" or $goto eq "REMOTE"){ warn "Skipping to staging remote server step!\n"; goto REMOTESTAGE; }
    if ($goto eq "S" or $goto eq "SCRIPT"){ warn "Skipping to building hmmscan script step!\n"; goto BUILDHMMSCRIPT; }
    if ($goto eq "H" or $goto eq "HMM"){ warn "Skipping to hmmscan step!\n"; goto HMMSCAN; }
    if ($goto eq "G" or $goto eq "GET"){ warn "Skipping to get remote hmmscan results step!\n"; goto GETRESULTS; }
    if ($goto eq "C" or $goto eq "CLASSIFY"){ warn "Skipping to classifying reads step!\n"; goto CLASSIFYREADS; }
    if ($goto eq "O" or $goto eq "OUTPUT"){ warn "Skipping to producing output step!\n"; goto CALCDIVERSITY; }
    die "QUITTING DUE TO INVALID --goto OPTION: (specifically, the option was \"$goto\"). If we got to here in the code, it means there was an INVALID FLAG PASSED TO THE GOTO OPTION.";
}

## ================================================================================
## ================================================================================
#LOAD PROJECT, SAMPLES, METAREADS
#Grab the samples associated with the project
printBanner("LOADING PROJECT");
#Partitioned samples project
#get the samples associated with project. a project description can be left in DESCRIPT.txt

if (!$dryRun) { $analysis->MRC::Run::get_partitioned_samples($project_dir); }
else { MRC::dryNotify("Skipped getting the partitioned samples for $project_dir."); }

############
#come back and add a check that ensures sequences associated with samples
#are of the proper format. We should check data before loading.
############
#Load Data. Project id becomes a project var in load_project

if (!$dryRun) {
    $analysis->MRC::Run::load_project($project_dir, $nseqs_per_samp_split);
} else {
    $analysis->set_project_id(-99); # Dummy project ID
    MRC::dryNotify("Skipping the local load of the project.");
}

if ($is_remote){
    if (!$dryRun) {
	$analysis->MRC::Run::load_project_remote($analysis->get_project_id());
    } else {
	MRC::dryNotify("Skipping the REMOTE loading of the project.");
    }
    $analysis->set_remote_hmmscan_script($analysis->get_remote_project_path()   . "/run_hmmscan.sh");
    $analysis->set_remote_hmmsearch_script($analysis->get_remote_project_path() . "/run_hmmsearch.sh");
    $analysis->set_remote_blast_script($analysis->get_remote_project_path()     . "/run_blast.sh");
    $analysis->set_remote_last_script($analysis->get_remote_project_path()      . "/run_last.sh");
    $analysis->set_remote_formatdb_script($analysis->get_remote_project_path()  . "/run_formatdb.sh");
    $analysis->set_remote_lastdb_script($analysis->get_remote_project_path()    . "/run_lastdb.sh");
    $analysis->set_remote_project_log_dir($analysis->get_remote_project_path()  . "/logs");
}

## ================================================================================
## ================================================================================
#TRANSLATE READS
# At this point, project, samples and metareads have been loaded into the DB. Now translate the metareads!
printBanner("TRANSLATING READS");

if (!$dryRun) {
    if ($is_remote) {
	#run transeq remotely, check on SGE job status, pull results back locally once job complete.
	my $remote_logs = $analysis->get_remote_project_path() . "/logs/";
	if (!$dryRun) { $analysis->MRC::Run::translate_reads_remote($waittime, $remote_logs, $split_orfs);	}
	else { MRC::dryNotify("[Dry run]: in a real run, we would have translated reads here."); }
    } else {
	my $projID = $analysis->get_project_id();
	foreach my $sampleID (@{$analysis->get_sample_ids()}){
	    my $sample_reads = "${local_ffdb}/projects/$projID/${sampleID}/raw";
	    my $orfs_file    = "${local_ffdb}/projects/$projID/${sampleID}/orfs";
	    # We could potentially do some file splitting here to speed up the remote compute...
	    if (!$dryRun) { $analysis->MRC::Run::translate_reads($sample_reads, $orfs_file); }
	    else { MRC::dryNotify("[Dry run]: in a real run, we would have translated reads here.\n"); }
	}
    }
} else {
    MRC::dryNotify("Skipping translation of reads.");
}

## ================================================================================
## ================================================================================
#LOAD ORFS: reads have been translated, now load them into the DB
printBanner("LOADING TRANSLATED READS");
foreach my $sample_id(@{ $analysis->get_sample_ids() }){
    my $projID = $analysis->get_project_id();
    my $in_orf_dir = "$local_ffdb/projects/$projID/$sample_id/orfs/";
    my $orfCount = 0;
    foreach my $in_orfs(@{ $analysis->MRC::DB::get_split_sequence_paths($in_orf_dir, 1) }){
	print "Processing orfs in $in_orfs\n";
	my $orfs = Bio::SeqIO->new(-file => $in_orfs, -format => 'fasta');
	if ($analysis->is_multiload()){
	    my $trans_algo = ($split_orfs) ? "transeq_split" : "transeq";
	    if (!$dryRun) { $analysis->MRC::Run::load_multi_orfs($orfs, $sample_id, $trans_algo); }
	    else { MRC::dryNotify(); }
	} else {
	    while (my $orf = $orfs->next_seq()) {
		my $orf_alt_id  = $orf->display_id();
		my $read_alt_id = MRC::Run::parse_orf_id($orf_alt_id, "transeq");
		if (!$dryRun) { $analysis->MRC::Run::load_orf($orf_alt_id, $read_alt_id, $sample_id); }
		else { MRC::dryNotify(); }
		print "Added " . ($orfCount++) . " orfs to the DB...\n";
	    }
	}
    }
}

## ================================================================================
## ================================================================================
BUILDHMMDB:
    ; # <-- this keeps emacs from indenting the code stupidly. Ugh!

if ($hmmdb_build){
    if (!$use_hmmscan && !$use_hmmsearch) {
	warn("WARNING: It seems that you want to build an hmm database, but you aren't invoking hmmscan or hmmsearch. While I will continue, you should check your settings to make certain you aren't making a mistake.");
    }
    printBanner("BUILDING HMM DATABASE");
    $analysis->MRC::Run::build_search_db($hmmdb_name, $hmm_db_split_size, $force_db_build, "hmm");
}

if ($blastdb_build) {
    if (!$use_blast && !$use_last) {
	warn("It seems that you want to build a blast database, but you aren't invoking blast or last. While I will continue, you should check your settings to make certain you aren't making a mistake.");
    }
    printBanner("BUILDING BLAST DATABASE");
    #need to build the nr module here
    $analysis->MRC::Run::build_search_db($blastdb_name, $blast_db_split_size, $force_db_build, "blast", $reps_only, $nr_db);
}

### ====================================================================
REMOTESTAGE:
if ($is_remote && $stage){
    printBanner("STAGING REMOTE SEARCH DATABASE");
    if (defined($hmmdb_name) && ($use_hmmsearch || $use_hmmscan)){
	$analysis->MRC::Run::remote_transfer_search_db($hmmdb_name, "hmm");
	if (!$scratch){
	    print "Not using remote scratch space, apparently... I guess there is some gunzipping going on?\n";
	    #should do optimization here
	    $analysis->MRC::Run::gunzip_remote_dbs($hmmdb_name, "hmm");
	} else {
	    print "Using remote scratch space, apparently...\n";
	}
    }

    my $projID = $analysis->get_project_id();
    if (defined($blastdb_name) && ($use_blast || $use_last)){
	$analysis->MRC::Run::remote_transfer_search_db($blastdb_name, "blast");
	#should do optimization here. Also, should roll over to blast+
	$analysis->MRC::Run::gunzip_remote_dbs($blastdb_name, "blast");

	my $project_path = $analysis->get_remote_project_path();
	my $nsplits  = $analysis->MRC::DB::get_number_db_splits("blast");

	if ($use_blast){
	    print "Building remote formatdb script...\n";
	    my $formatdb_script_path = "$local_ffdb/projects/$projID/run_formatdb.sh";
	    my $remote_script_path   = $analysis->get_remote_formatdb_script(); # a file and not a directory!
	    #build_remote_formatdb_script($formatdb_script_path, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch);
	    #my @args = ("build_remote_lastdb_script.pl", "-o $script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch");
	    build_remote_script_generic("perl $localScriptDir/build_remote_formatdb_script.pl -o $formatdb_script_path -n $nsplits --name $blastdb_name -p $project_path -s $scratch");
	    MRC::Run::transfer_file($formatdb_script_path, $analysis->get_remote_connection() . ":" . $remote_script_path);
	    $analysis->MRC::Run::format_remote_blast_dbs($remote_script_path);
	}
	if ($use_last){
	    print "Building remote lastdb script...\n";
	    my $lastdb_script       = "$local_ffdb/projects/$projID/run_lastdb.sh";
	    my $remote_script_path  = $analysis->get_remote_lastdb_script(); # a file and not a directory!
	    #build_remote_lastdb_script($lastdb_script, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch);
	    build_remote_script_generic("perl $localScriptDir/build_remote_lastdb_script.pl -o $lastdb_script -n $nsplits --name $blastdb_name -p $project_path -s $scratch");
	    MRC::Run::transfer_file($lastdb_script, $analysis->get_remote_connection() . ":" . $remote_script_path);
	    $analysis->MRC::Run::format_remote_blast_dbs($remote_script_path);
	}
    }
}

### ====================================================================
BUILDHMMSCRIPT:
if ($is_remote) {
    my $projID = $analysis->get_project_id();
    my $project_path = $analysis->get_remote_project_path();
    if ($use_hmmscan){
	printBanner("BUILDING REMOTE HMMSCAN SCRIPT");
	my $h_script       = "$local_ffdb/projects/$projID/run_hmmscan.sh";
	my $n_hmm_searches = $analysis->MRC::DB::get_number_hmmdb_scans($hmm_db_split_size);
	my $nsplits        = $analysis->MRC::DB::get_number_db_splits("hmm");
	print "number of hmm searches: $n_hmm_searches\n";
	print "number of hmm splits: $nsplits\n";

	build_remote_script_generic("perl $localScriptDir/build_remote_hmmscan_script.pl -z $n_hmm_searches -o $h_script -n $nsplits --name $hmmdb_name -p $project_path -s $scratch");
	#build_remote_hmmscan_script($h_script, $n_hmm_searches, $hmmdb_name, $nsplits, $analysis->get_remote_project_path());
	MRC::Run::transfer_file($h_script, $analysis->get_remote_connection() . ":" . $analysis->get_remote_hmmscan_script());
    }
    if ($use_hmmsearch){
	printBanner("BUILDING REMOTE HMMSEARCH SCRIPT");
	my $h_script   = "$local_ffdb/projects/$projID/run_hmmsearch.sh";
#	my $n_hmm_searches  = $analysis->MRC::DB::get_number_hmmdb_scans($hmm_db_split_size);
	my $n_sequences = $analysis->MRC::DB::get_number_sequences($nseqs_per_samp_split);
	my $nsplits     = $analysis->MRC::DB::get_number_db_splits("hmm");
	print "number of searches: $n_sequences\n";
	print "number of hmmdb splits: $nsplits\n";
	#build_remote_hmmsearch_script($h_script, $n_sequences, $hmmdb_name, $nsplits, $analysis->get_remote_project_path(), $scratch);
	build_remote_script_generic("perl $localScriptDir/build_remote_hmmsearch_script.pl -z $n_sequences -o $h_script -n $nsplits --name $hmmdb_name -p $project_path -s $scratch");
	MRC::Run::transfer_file($h_script, $analysis->get_remote_connection() . ":" . $analysis->get_remote_hmmsearch_script());
    }
    if ($use_blast){
	printBanner("BUILDING REMOTE BLAST SCRIPT");
	my $b_script   = "$local_ffdb/projects/$projID/run_blast.sh";
	my $db_length  = $analysis->MRC::DB::get_blast_db_length($blastdb_name);
	my $nsplits    = $analysis->MRC::DB::get_number_db_splits("blast");
	print "database length is $db_length\n";
	print "number of blast db splits: $nsplits\n";
	#build_remote_blastsearch_script($b_script, $db_length, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch);
	build_remote_script_generic("perl $localScriptDir/build_remote_blast_script.pl -z $db_length -o $b_script -n $nsplits --name $blastdb_name -p $project_path -s $scratch");
	MRC::Run::transfer_file($b_script, $analysis->get_remote_connection() . ":" . $analysis->get_remote_blast_script());
    }
    if ($use_last){
	printBanner("BUILDING REMOTE LAST SCRIPT");
	#we use the blast script code as a template given the similarity between the methods, so there are some common var names between the block here and above
	my $b_script     = "$local_ffdb/projects/$projID/run_last.sh";
	my $db_length    = $analysis->MRC::DB::get_blast_db_length($blastdb_name);
	my $nsplits      = $analysis->MRC::DB::get_number_db_splits("blast");
	print "database length is $db_length\n";
	print "number of last db splits: $nsplits\n";
	build_remote_script_generic("perl $localScriptDir/build_remote_last_script.pl -z $db_length -o $b_script -n $nsplits --name $blastdb_name -p $project_path -s $scratch");
	#build_remote_lastsearch_script($b_script, $db_length, $blastdb_name, $n_blastdb_splits, $analysis->get_remote_project_path(), $scratch);
	#my @args = ("build_remote_blast_script.pl -z $db_length", "-o $b_script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch");
	MRC::Run::transfer_file($b_script, $analysis->get_remote_connection() . ":" . $analysis->get_remote_last_script());
    }
}

### ====================================================================
#RUN HMMSCAN
HMMSCAN:
if ($is_remote){
    printBanner("RUNNING REMOTE SEARCH");
    foreach my $sample_id(@{ $analysis->get_sample_ids() }){
	($use_hmmscan)   && $analysis->MRC::Run::run_search_remote($sample_id, "hmmscan",   $waittime, $verbose);
	($use_blast)     && $analysis->MRC::Run::run_search_remote($sample_id, "blast",     $waittime, $verbose);
	($use_hmmsearch) && $analysis->MRC::Run::run_search_remote($sample_id, "hmmsearch", $waittime, $verbose);
	($use_last)      && $analysis->MRC::Run::run_search_remote($sample_id, "last",      $waittime, $verbose);
	print "Progress report: finished ${sample_id} on " . `date` . "\n";
    }  
} else {
    printBanner("RUNNING LOCAL SEARCH");
    foreach my $sample_id(@{ $analysis->get_sample_ids() }){
	#my $sample_path = $local_ffdb . "/projects/" . $analysis->get_project_id() . "/" . $sample_id . "/";
	my $orfs        = "orfs.fa";
	my $results_dir = "search_results";
	my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs($hmmdb_name) };
	warn "Running hmmscan for sample ID ${sample_id}...";
	foreach my $hmmdb(keys(%hmmdbs)){
	    my $results_full_path = "${results_dir}/${sample_id}_v_${hmmdb}.hsc";
	    #run with tblast output format (e.g., --domtblout)
	    $analysis->MRC::Run::run_hmmscan($orfs, $hmmdbs{$hmmdb}, $results_full_path, 1);
	}
    }
}

### ====================================================================
#GET REMOTE RESULTS
GETRESULTS:
if ($is_remote){
    printBanner("GETTING REMOTE RESULTS");
    foreach my $sample_id(@{ $analysis->get_sample_ids() }){
	($use_hmmscan)   && $analysis->MRC::Run::get_remote_search_results($sample_id, "hmmscan");
	($use_blast)     && $analysis->MRC::Run::get_remote_search_results($sample_id, "blast");
	($use_hmmsearch) && $analysis->MRC::Run::get_remote_search_results($sample_id, "hmmsearch");
	($use_last)      && $analysis->MRC::Run::get_remote_search_results($sample_id, "last");
    }
}

### ====================================================================
#PARSE AND LOAD RESULTS
CLASSIFYREADS:
if ($is_remote){
    printBanner("CLASSIFYING REMOTE SEARCH RESULTS");
    foreach my $sample_id(@{ $analysis->get_sample_ids() }){
	if (defined($skip_samps{ $sample_id })){
	    print("skipping $sample_id because it has been processed\n");
	    next;
	}
	print "Classifying reads for sample $sample_id\n";
	my $path_to_split_orfs = $analysis->get_sample_path($sample_id) . "/orfs";
	foreach my $orf_split_file_name(@{ $analysis->MRC::DB::get_split_sequence_paths($path_to_split_orfs , 0) }) {
	    if ($use_hmmscan){
		my $algo = "hmmscan";
		my $class_id = $analysis->MRC::DB::get_classification_id(
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		$analysis->MRC::Run::classify_reads($sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type);
	    }
	    if ($use_hmmsearch){
		my $algo = "hmmsearch";
		my $class_id = $analysis->MRC::DB::get_classification_id(
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		$analysis->MRC::Run::classify_reads($sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type);
	    }
	    if ($use_blast){
		my $algo = "blast";
		my $class_id = $analysis->MRC::DB::get_classification_id(
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $blastdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		$analysis->MRC::Run::classify_reads($sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type);
	    }	    
	    if ($use_last){
		my $algo = "last";
		my $class_id = $analysis->MRC::DB::get_classification_id(
		    $analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $blastdb_name, $algo, $top_hit_type,
		)->classification_id();
		print "Classification_id for this run using $algo is $class_id\n";
		#build this routine
		$analysis->MRC::Run::classify_reads($sample_id, $orf_split_file_name, $class_id, $algo, $top_hit_type);
	    }	    
	}
   }
} else{
    printBanner("CLASSIFYING LOCAL SEARCH RESULTS ?? This is 'deprecated' apparently and maybe hasn't been tested recently?");
    #this block is deprecated...
    foreach my $sample_id(@{ $analysis->get_sample_ids() }){
	my %hmmdbs = %{ $analysis->MRC::DB::get_hmmdbs($hmmdb_name) };
	foreach my $hmmdb(keys(%hmmdbs)){
	    my $projID = $analysis->get_project_id();
	    my $hsc_results = "$local_ffdb/projects/$projID/$sample_id/search_results/${sample_id}_v_${hmmdb}.hsc";
	    $analysis->MRC::Run::classify_reads($sample_id, $hsc_results, $evalue, $coverage);
	}
    }
}

#die "apparently we die here before calculating diversity statistics for some reason";

### ====================================================================
#calculate diversity statistics
CALCDIVERSITY:
printBanner("CALCULATING DIVERSITY STATISTICS");
#note, we could decrease DB pings by merging some of these together (they frequently leverage same hash structure)
#might need to include classification_id as a call here;
if ($use_hmmscan){
    print "Calculating hmmscan diversity\n";
    my $algo = "hmmscan";
    my $class_id = $analysis->MRC::DB::get_classification_id(
	$analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
	)->classification_id();
    calculate_diversity($analysis, $class_id);
}

if ($use_hmmsearch){
    print "Calculating hmmsearch diversity\n";
    my $algo = "hmmsearch";
    my $class_id = $analysis->MRC::DB::get_classification_id(
	$analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $hmmdb_name, $algo, $top_hit_type,
	)->classification_id();
    calculate_diversity($analysis, $class_id);
}

if ($use_blast){
    print "Calculating blast diversity\n";
    my $algo = "blast";
    my $class_id = $analysis->MRC::DB::get_classification_id(
	$analysis->get_evalue_threshold(), $analysis->get_coverage_threshold(), $score, $blastdb_name, $algo, $top_hit_type,
	)->classification_id();
    calculate_diversity($analysis, $class_id);
}
### ====================================================================




printBanner("ANALYSIS COMPLETED!\n");


### ============== MAIN CODE THAT GETS CALLED EVERY TIME: ABOVE =========================

### ================================== FUNCTIONS BELOW ==================================

sub calculate_diversity {
    my($analysis, $class_id) = @_;
    print "project richness...\n";
    $analysis->MRC::Run::calculate_project_richness($class_id);
    print "project relative abundance...\n";
    $analysis->MRC::Run::calculate_project_relative_abundance($class_id);
    print "per-sample richness...\n";
    $analysis->MRC::Run::calculate_sample_richness($class_id);
    print "per-sample relative abundance..\n";
    $analysis->MRC::Run::calculate_sample_relative_abundance($class_id);
    print "building classification map...\n";
    $analysis->MRC::Run::build_classification_map($class_id);
    print "building PCA dataframe...\n";
    $analysis->MRC::Run::build_PCA_data_frame($class_id);
}



sub build_remote_script_generic {
    my ($cmd) = @_;
    my $results = IPC::System::Simple::capture($cmd);
    (0 == $EXITVAL) or die "Error:  non-zero exit value: $results";
    return($results);
}

# sub build_remote_hmmscan_script{
#     my($h_script_path, $n_searches, $hmmdb_basename, $n_splits, $project_path, $scratch) = @_;
#     my @args = ("build_remote_hmmscan_script.pl", "-z $n_searches", "-o $h_script_path", "-n $n_splits", "--name $hmmdb_basename", "-p $project_path", "-s $scratch");
#     my $results = IPC::System::Simple::capture("perl " . "@args");
#     if ($EXITVAL != 0){
# 	warn($results);
# 	exit(0);
#     }
#     return $results;
# }

# sub build_remote_hmmsearch_script{
#     my ($h_script_path, $n_searches, $hmmdb_basename, $n_splits, $project_path, $scratch) = @_;
#     my @args = ("build_remote_hmmsearch_script.pl", "-z $n_searches", "-o $h_script_path", "-n $n_splits", "--name $hmmdb_basename", "-p $project_path", "-s $scratch");
#     print("perl " . "@args\n");
#     my $results = IPC::System::Simple::capture("perl " . "@args");
#     if ($EXITVAL != 0){
# 	warn($results);
# 	exit(0);
#     }
#     return $results;
# }

# sub build_remote_blastsearch_script{
#     my ($b_script_path, $db_length, $blastdb_basename, $n_splits, $project_path, $scratch) = @_;
#     my @args = ("build_remote_blast_script.pl", "-z $db_length", "-o $b_script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch");
#     print("perl @args\n");
#     my $results = IPC::System::Simple::capture("perl " . "@args");
#     if ($EXITVAL != 0){
# 	warn($results);
# 	exit(0);
#     }
#     return $results;
# }

#need to build
# sub build_remote_lastsearch_script {
#     my ($b_script_path, $db_length, $blastdb_basename, $n_splits, $project_path, $scratch) = @_;
#     my @args = ("build_remote_last_script.pl", "-z $db_length", "-o $b_script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch");
#     print("perl @args\n");
#     my $results = IPC::System::Simple::capture("perl " . "@args");
#     if ($EXITVAL != 0){
# 	warn($results);
# 	exit(0);
#     }
#     return $results;
#}

# sub build_remote_formatdb_script {
#     my ($script_path, $blastdb_basename, $n_splits, $project_path, $scratch) = @_;
#     my @args = ("build_remote_formatdb_script.pl", "-o $script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch");
#     print("perl " . "@args\n");
#     my $results = IPC::System::Simple::capture("perl " . "@args");
#     if ($EXITVAL != 0){
# 	warn($results);
# 	exit(0);
#     }
#     return $results;    
# }

# sub build_remote_lastdb_script {
#     my ($script_path, $blastdb_basename, $n_splits, $project_path, $scratch) = @_;
#     my @args = ("build_remote_lastdb_script.pl", "-o $script_path", "-n $n_splits", "--name $blastdb_basename", "-p $project_path", "-s $scratch");
#     print("perl " . "@args\n");
#     my $results = IPC::System::Simple::capture("perl " . "@args");
#     if ($EXITVAL != 0){
# 	warn($results);
# 	exit(0);
#     }
#     return $results;    
# }


sub printBanner {
    my ($string) = @_;
    my $dateStr = `date`;
    chomp($string); # remove any ending-of-string newline that might be there
    chomp($dateStr); # remote always-there newline from the `date` command
    my $stringWithDate = $string . " ($dateStr)";
    my $pad  = "#" x (length($stringWithDate) + 4); # add four to account for extra # and whitespce on either side of string
    print STDERR MRC::safeColor("$pad\n" . "# " . $stringWithDate . " #\n" . "$pad\n", "cyan on_blue");
}


__DATA__

mrc_handler.pl  [OPTIONS]

Last updated Feb 2013.

MRC (Metagenomics Read Classifier) program by Tom Sharpton.

Handles a bunch of database and cluster stuff.

See the examples below for more information.

EXAMPLES:

1. You have to set your MRC_LOCAL environment variable.
export MRC_LOCAL=/my/home/directory/MRC       <-- this is your github-checked-out copy of MRC

2. Now you need to store your MySQL database password in a local variable, since we have to (insecurely!) use this.
I recommend typing this:
PASS=yourMysqlPassword

3. You have to set up passphrase-less SSH to your computational cluster. In this example, the cluster is "compute.cluster.university.edu".
Follow the links at "https://www.google.com/search?q=passphraseless+ssh" in order to find some solutions for setting this up. It is quite easy!

4. Then you can run mrc_handler.pl as follows. Sorry the command is so long!

Note that the FIRST TIME you run it, you need to calculat the HMM database (--hdb) and the blast database (--bdb), and you have to STAGE (i.e. copy) the files to the remote cluster with the --stage option.
So your first run will look something like this:
   perl $MRC_LOCAL/scripts/mrc_handler.pl --hdb --bdb --stage [...the rest of the options should be copied from the super long command below...]

On subsequent runs, you can omit "--hdb" and "--bdb" and "--stage" , and run just this:
   perl $MRC_LOCAL/scripts/mrc_handler.pl --dbuser=sqlusername --dbpass=$PASS --dbhost=data.your.university.edu --rhost=compute.cluster.university.edu --ruser=clusterusername --rdir=/cluster_temp_storage/MRC --ffdb=/local_database/MRC_ffdb --refdb=/local_home/sifting_families --projdir=./MRC/data/randsamp_subset_perfect_2/


(put some more examples here)

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

--dbname=DATABASENAME (OPTIONAL argument: default is "Sfams_hmp")
    The database name. Usually something like "Sfams_lite" or "Sfams_hmp".

--dbschema=SCHEMANAME (OPTIONAL argument: default is "Sfams::Schema")
    The schema name.

--dbprefix=STRING (Optional: default is "SFams_all_v0")
    Some kind of prefix/basename. I am confused.

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



--hmmdb=STRING (or -h STRING) (Optional: automatically set to a default value)
   HMM database name

--blastdb=STRING (or -b STRING)
   BLAST database name

--sub=STRING
    Not sure what this is. ("FAMILY SUBSET LIST")

--stage  (Default: disabled (no staging))
    Causes the remote database to get copied, I think. Slow!

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
