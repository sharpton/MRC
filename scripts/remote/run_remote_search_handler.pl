#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use File::Path qw(make_path rmtree);
use IPC::System::Simple qw(capture $EXITVAL);
use File::Spec;

#called by remote, executes run_hmmsearch.sh, run_hmmscan.sh, or run_blast.sh, etc.
warn "This command was run:\n perl run_remote_search_handler.pl @ARGV";

my($result_dir, $db_dir, $query_seq_dir, $db_name, $scriptpath, $nsplits );
my $waitTimeInSeconds = 5; # default value is 5 seconds between job checks

my $loop_number  = 2; #how many times should we check that the data was run to completion? we restart failed jobs here
my $force_search = 0;

GetOptions("resultdir|o=s"  => \$result_dir,
	   "dbdir|h=s"      => \$db_dir,
	   "querydir|i=s"   => \$query_seq_dir,	  
	   "dbname|n=s"     => \$db_name,
	   "scriptpath|s=s" => \$scriptpath,
	   "w=i"            => \$waitTimeInSeconds,  # between 1 and 60. More than 60 is too long! Check more frequently than that. 1 is a good value.
	   "nsplits=i"      => \$nsplits, #how many db splits? used to determine number of job arrays to set up.
	   "forcesearch!"    => \$force_search
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
    next if( $query_seq_file =~ m/^\./  ); # skip the '.' and '..' and other dot files
    if( $query_seq_file =~ m/\.tmp\d*$/ ){ #if we have an old rapsearch run that we're reprocessing, we can't process the *.tmp files!
	next; #this is safer than unlink; what is user has strange file extention? let's just pass. can delete by hand if abs. necessary
	#unlink( $query_seq_file );
    }
    #modify result_dir here such that the output is placed into each split's subdir w/in $result_dir
    my $split_sub_result_dir = File::Spec->catdir($result_dir, $query_seq_file);
    if( -d $split_sub_result_dir && !$force_search ){
	warn( "I found results in $split_sub_result_dir. I will not overwrite them without the --forcesearch option!\n");
	next;
    }
    warn "Making a subdirectory with the name <${split_sub_result_dir}/> . Note that it is INTENTIONAL that this actually has a file extension as if it is a filename and not a directory!";
    # Surprisingly, we appear to actually MAKE a new directory with a name like "somewhere/someplace/thing.fasta/"
    # Here is the original line from Tom's code: note that there was previously expected to be a '/' integrated with the results_dir: my $split_sub_results_dir = $results_dir . $query_seq_file . "/";

    #now let's see if that directory exists. If not, create it.
    check_and_make_path($split_sub_result_dir, 1);
    #prep the array string for the array job option
    my $array_string = "1-${nsplits}";
    #run the jobs!
    print "-"x60 . "\n";
    print " RUN REMOTE SEARCH HANDLER.PL arguments for <$query_seq_file>\n";
    print "          LOOP NUMBER: 0\n";
    print "          SCRIPT PATH: $scriptpath\n";
    print "        QUERY SEQ DIR: $query_seq_dir\n";
    print "       QUERY SEQ FILE: $query_seq_file\n";
    print "               DB DIR: $db_dir\n";
    print "              DB NAME: $db_name\n";
    print "         ARRAY STRING: $array_string\n";
    print " SPLIT SUB RESULT DIR: $split_sub_result_dir\n";
    print "-"x60 . "\n";
    my $results = run_remote_search($scriptpath, $query_seq_dir, $query_seq_file, $db_dir, $db_name, $split_sub_result_dir, $array_string);
    
    if ($results =~ m/^Your job-array (\d+)\./) { #an array job
	my $job_id = $1;
	$jobs{$job_id}++;
    } #Your job 8119214 ("run_rapsearch.sh") has been submitted 
    elsif ($results =~ m/^Your job (\d+) /) { #not an array job
	my $job_id = $1;
	$jobs{$job_id}++;
    } 
    else {
	die "Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!";
    }
}

#At this point, we have a lot ofjobs in the queue. Let's monitor the queue and report back to local when jobs are complete 
my @job_ids = keys(%jobs);
my $time = remote_job_listener(\@job_ids, $waitTimeInSeconds);

#all of the jobs are done. Let's make sure they've all produced output. If not, rerun those jobs
my $count = 1;
while( $count <= $loop_number + 1 ){ #the last loop will just report any sets that still look broken despite the attempt to restart them
    #get get the search_results
    foreach my $query_seq_file( @query_files ){
	my $task_count = 0;
	my $split_array = '';
	next if( $query_seq_file =~ m/^\./  ); # skip the '.' and '..' and other dot files
	if( $query_seq_file =~ m/\.tmp\d*$/ ){ #if we have an old rapsearch run that we're reprocessing, we can't process the *.tmp files!
	    next; #this is safer than unlink; what is user has strange file extention? let's just pass. can delete by hand if abs. necessary
	    #unlink( $query_seq_file );
	}
	my $split_sub_result_dir = File::Spec->catdir($result_dir, $query_seq_file);
	for( my $i=1; $i<=$nsplits; $i++ ){
	    #does the output file exist? This may not be a pefect check for crashed jobs! Future search algs may break this logic
	    my $has_match = 0;
	    my @split_res_files = glob( "${split_sub_result_dir}/${query_seq_file}-${db_name}_${i}.tab*" ); #we have to glob because rapsearch
	    for my $file( @split_res_files ){
		next if( $query_seq_file =~ m/\.tmp\d*$/ ); #don't want to count rapsearch tmp files, which are incomplete outputs from what we can tell
		if( -e $file ){
		    $has_match = 1;
		}
	    }
	    next if $has_match;
	    #if not, add the split to the list of array jobs to run
	    if( !$has_match ){
		if( $count == $loop_number + 1 ){
		    print "Despite $loop_number tries, I can't generate results for ${split_sub_result_dir}/${query_seq_file}-${db_name}_${i}.tab\n";
		}
		print "Looks like we need to retry ${query_seq_file} against database split ${i}...\n";
		$split_array .= "${i},";
		$task_count++;
	    }
	}	
	next if( $task_count == 0 || $count == $loop_number + 1 ); #there were no failed jobs, it seems... or we're past the number of requested loops	
	my $sub_array_string = "1-${task_count}";
	$split_array         =~ s/\,$//;
	#submit the jobs!
	print "-"x60 . "\n";
	print " RUN REMOTE SEARCH HANDLER.PL arguments for <$query_seq_file>\n";
	print "          LOOP NUMBER: $count\n";
	print "          SCRIPT PATH: $scriptpath\n";
	print "        QUERY SEQ DIR: $query_seq_dir\n";
	print "       QUERY SEQ FILE: $query_seq_file\n";
	print "               DB DIR: $db_dir\n";
	print "              DB NAME: $db_name\n";
	print "         ARRAY STRING: $sub_array_string\n";
	print "          SPLIT ARRAY: $split_array\n";
	print " SPLIT SUB RESULT DIR: $split_sub_result_dir\n";
	print "-"x60 . "\n";
	my $results = run_remote_search($scriptpath, $query_seq_dir, $query_seq_file, $db_dir, $db_name, $split_sub_result_dir, $sub_array_string, $split_array);
	
	if ($results =~ m/^Your job-array (\d+)\./) { #an array job
	    my $job_id = $1;
	    $jobs{$job_id}++;
	} #Your job 8119214 ("run_rapsearch.sh") has been submitted 
	elsif ($results =~ m/^Your job (\d+) /) { #not an array job
	    my $job_id = $1;
	    $jobs{$job_id}++;
	} 
	else {
	    die "Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!";
	}
    }
    #At this point, we have a lot ofjobs in the queue. Let's monitor the queue and report back to local when jobs are complete 
    #this is a loop specific listener
    my @job_ids = keys(%jobs);
    if( scalar( @job_ids ) < 1 || $count == $loop_number + 1 ){
	print "It looks like all query-db pairs have output files, so I think I'm done with the cluster for this sample for now.\n";
	last;
    }
    my $time = remote_job_listener(\@job_ids, $waitTimeInSeconds);
    $count++;
}


###############
# SUBROUTINES #
###############

sub run_remote_search {
    my($scriptpath, $query_seq_dir, $query_seq_file, $db_dir, $db_name, $result_dir, $array_string, $split_array) = @_;
    warn "Processing <$query_seq_file>. Running with array jobs...";

    (defined($scriptpath) && (length($scriptpath) > 0)) or die "Script path ($scriptpath) was undefined or zero-len!";
    (defined($query_seq_dir) && (length($query_seq_dir) > 0)) or die "Query seq dir ($query_seq_dir) was undefined or zero-len!";
    (defined($query_seq_file) && (length($query_seq_file) > 0)) or die "Query seq file ($query_seq_file) was undefined or zero-len!";
    (defined($db_dir) && (length($db_dir) > 0)) or die "DB dir ($db_dir) was undefined or zero-len!";
    (defined($db_name) && (length($db_name) > 0)) or die "DB name ($db_name) was undefined or zero-len!";
    (defined($result_dir) && (length($result_dir) > 0)) or die "Result dir ($result_dir) was undefined or zero-len!";
    (defined($array_string)) or warn "You haven't specified an array string to use - I assume you don't want an array job?";
    my $out_stem = "${query_seq_file}-${db_name}"; # <-- this really better not have any whitespace in it!!!

    if( !defined($split_array ) ){
	$split_array = '';
    }

    # Interestingly, we give "$scriptpath" as just a path, no need to say "perl ____" or anything.
    # I guess 'qsub' is able to figure it out.

    # Arg names as seen in "run_last.sh", below in all-caps:
    #                          INPATH         INPUT           DBPATH     OUTPATH     OUTSTEM
    my $array_opt = "-t ${array_string}";
    my @args = ( $array_opt, $scriptpath, $query_seq_dir, $query_seq_file, $db_dir, $result_dir, $out_stem, $split_array );
    warn("We will attempt to execute the following job:\n qsub @args");

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
