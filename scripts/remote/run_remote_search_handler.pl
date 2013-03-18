#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use File::Path qw(make_path rmtree);
use IPC::System::Simple qw(capture $EXITVAL);
use File::Spec;

#called by lighthouse, executes run_hmmsearch.sh, run_hmmscan.sh, or run_blast.sh
warn "This command was run: perl run_remote_search_handler.pl @ARGV";

my($result_dir, $db_dir, $query_seq_dir, $db_name, $scriptpath);
my $waitTimeInSeconds = 5; # default value is 5 seconds between job checks

GetOptions("resultdir|o=s"  => \$result_dir,
	   "dbdir|h=s"      => \$db_dir,
	   "querydir|i=s"   => \$query_seq_dir,	  
	   "dbname|n=s"     => \$db_name,
	   "scriptpath|s=s" => \$scriptpath,
	   "w=i"            => \$waitTimeInSeconds,  # between 1 and 60. More than 60 is too long! Check more frequently than that. 1 is a good value.
    );

(defined($result_dir) && (-d $result_dir)) or die "The result directory <$result_dir> was not valid on the REMOTE SERVER! Double check it.";
(defined($db_dir) && (-d $result_dir)) or die "The db directory <$db_dir> was not valid on the REMOTE SERVER! Double check it.";
(defined($query_seq_dir) && (-d $query_seq_dir)) or die "The query sequence directory <$query_seq_dir> was not valid on the REMOTE SERVER! Double check it.";
(defined($db_name)) or die "Database name <$db_name> was not valid!";
($waitTimeInSeconds >= 1 && $waitTimeInSeconds <= 600) or die "The wait time in seconds has to be between 1 and 60 (60 seconds = 1 minute). Yours was: ${waitTimeInSeconds}\n";
(defined($scriptpath) && (-f $scriptpath)) or die "The script at <$scriptpath> was not valid!";


#create a jobid storage log
my %jobs = ();
#open the query seq file directorie (e.g., /orfs/) and grab all of the orf splits
opendir( IN, $query_seq_dir ) || die "Can't opendir $query_seq_dir for read in run_remote_search_handler.pl\n";
my @query_files = readdir( IN );
closedir( IN );
#loop over the files, launching a queue job for each
foreach my $query_seq_file( @query_files ){
    next if( $query_seq_file =~ m/^\./ ); # skip the '.' and '..' and other dot files
    #modify result_dir here such that the output is placed into each split's subdir w/in $result_dir
    my $split_sub_result_dir = File::Spec->catdir($result_dir, $query_seq_file);

    warn "Making a subdirectory with the name <${split_sub_result_dir}/> . Note that it is INTENTIONAL that this actually has a file extension as if it is a filename and not a directory!";
    # Surprisingly, we appear to actually MAKE a new directory with a name like "somewhere/someplace/thing.fasta/"
    # Here is the original line from Tom's code: note that there was previously expected to be a '/' integrated with the results_dir: my $split_sub_results_dir = $results_dir . $query_seq_file . "/";

    #now let's see if that directory exists. If not, create it.
    check_and_make_path($split_sub_result_dir, 0);
    #run the jobs!
    print "-"x60 . "\n";
    print " RUN REMOTE SEARCH HANDLER.PL arguments for <$query_seq_file>\n";
    print "          SCRIPT PATH: $scriptpath\n";
    print "        QUERY SEQ DIR: $query_seq_dir\n";
    print "       QUERY SEQ FILE: $query_seq_file\n";
    print "               DB DIR: $db_dir\n";
    print "              DB NAME: $db_name\n";
    print " SPLIT SUB RESULT DIR: $split_sub_result_dir\n";
    print "-"x60 . "\n";
    my $results = run_remote_search($scriptpath, $query_seq_dir, $query_seq_file, $db_dir, $db_name, $split_sub_result_dir);
    
    if ($results =~ m/^Your job-array (\d+)\./) {
	my $job_id = $1;
	$jobs{$job_id}++;
    } else {
	die "Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!";
    }
}

#At this point, we have a lot ofjobs in the queue. Let's monitor the queue and report back to local when jobs are complete 
my @job_ids = keys(%jobs);
my $time = remote_job_listener(\@job_ids, $waitTimeInSeconds);

###############
# SUBROUTINES #
###############

sub run_remote_search {
    my($scriptpath, $query_seq_dir, $query_seq_file, $db_dir, $db_name, $result_dir) = @_;
    warn "Processing <$query_seq_file>. Running with array jobs...";

    (defined($scriptpath) && (length($scriptpath) > 0)) or die "Script path ($scriptpath) was undefined or zero-len!";
    (defined($query_seq_dir) && (length($query_seq_dir) > 0)) or die "Query seq dir ($query_seq_dir) was undefined or zero-len!";
    (defined($query_seq_file) && (length($query_seq_file) > 0)) or die "Query seq file ($query_seq_file) was undefined or zero-len!";
    (defined($db_dir) && (length($db_dir) > 0)) or die "DB dir ($db_dir) was undefined or zero-len!";
    (defined($db_name) && (length($db_name) > 0)) or die "DB name ($db_name) was undefined or zero-len!";
    (defined($result_dir) && (length($result_dir) > 0)) or die "Result dir ($result_dir) was undefined or zero-len!";

    my $out_stem = "${query_seq_file}-${db_name}"; # <-- this really better not have any whitespace in it!!!


    # Interestingly, we give "$scriptpath" as just a path, no need to say "perl ____" or anything.
    # I guess 'qsub' is able to figure it out.

    # Arg names as seen in "run_last.sh", below in all-caps:
    #                          INPATH         INPUT           DBPATH     OUTPATH     OUTSTEM
    my @args = ($scriptpath, $query_seq_dir, $query_seq_file, $db_dir, $result_dir, $out_stem );
    warn("We will attempt to execute the following job: qsub @args");

    (-d $query_seq_dir) or die "Query seq dir $query_seq_dir did not already exist on the REMOTE CLUSTER machine! It must be a DIRECTORY that already exists.";
    (-f "${query_seq_dir}/${query_seq_file}") or die "Query seq file in ${query_seq_dir}/${query_seq_file} did not already exist on the REMOTE CLUSTER machine!";
    (-f $scriptpath) or die "Script $scriptpath did not already exist on the REMOTE CLUSTER machine! It must already exist.";

    my $results = capture("qsub @args");
    (0 == $EXITVAL) or die "Error running the script: $results ";
    return $results;
}

sub remote_job_listener{
    my ($jobs, $waitTimeInSeconds) = @_;
    my $numwaits = 0;
    my %status   = ();
    while (1){
        last if(scalar(keys(%status)) == scalar(@{$jobs}) );         #stop checking if every job has a finished status
        my $results = execute_qstat();         #call qstat and grab the output
        foreach my $jobid( @{ $jobs } ){         #see if any of the jobs are complete. pass on those we've already finished
            next if( exists( $status{$jobid} ) );
            if( $results !~ m/$jobid/ ){
                $status{$jobid}++;
            }
        }
        sleep($waitTimeInSeconds);
        $numwaits++
    }
    my $time = $numwaits * $waitTimeInSeconds;
    return $time;
}

sub execute_qstat{
    my ($cmd) = @_;
    my $results = capture( "qstat" );
    (0 == $EXITVAL) or die "Error running execute_qstat: $results ";
    return $results;
}

sub check_and_make_path{
    my($path, $should_force) = @_;
    if (not -d $path) {
        warn("Directory did not already exist, so creating a directory at $path\n");
	make_path($path) || die "can't make_path: $!";
    } else {
	# directory ALREADY EXISTS if we are here
	if (defined($should_force) && $should_force) {
	    warn( "<$path> already existed, so we are REMOVING it first!\n");
	    rmtree( $path ) || die "can't rmtree:$!";
	    warn( "...creating $path\n" );
	    make_path( $path ) || die "can't make_path: $!";
	} else {
	    # if the file exists but there's NO forcing
	    die( "Directory exists at $path, will not overwrite without the 'force' argument being set to 1! " );
	}
    }
}
