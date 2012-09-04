#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use IPC::System::Simple qw(capture $EXITVAL);

my( $indir, $outdir, $waittime );
my $remote_scripts_path = "/netapp/home/sharpton/projects/MRC/scripts/";
my $array = 1;

GetOptions(
    "i=s" => \$indir,
    "o=s" => \$outdir,
    "w=i" => \$waittime,
    "s:s" => \$remote_scripts_path,
);

print "working on remote server...\n";

opendir( IN, $indir ) || die "Can't opendir $indir for read: $!\n";
my @infiles = readdir( IN );
closedir( IN );
#create a jobid storage log
my %jobs = ();
#grab the files that we want to translate
my ( $inbasename, $outbasename );
my $array_length = 0;
foreach my $file( @infiles ){
    next if( $file =~ m/^\./ );
    if( $array ){
	#need to know how many array jobs to launch
	$array_length++;
	#only need to process the single file, because the array jobs do the rest of the work.
	if( !(defined( $inbasename ) ) ){
	    #let's set some vars, but we won't process until we've looped over the entire directory
	    my $basename;
	    if( $file =~ m/(.*)split\_*/ ){
		$basename = $1 . "split_";
	    }
	    else{
		warn "Can't grab $basename from $file\n";
	    }
	    $inbasename = $basename;
	    $outbasename = $basename;
	    $outbasename =~ s/\_raw\_/\_orf\_/;
	}
    }
    else{
	#set the full input file path
	my $input = $indir . "/" . $file;
	#need to change the basename for the output file
	my $outfile = $file;
	$outfile =~ s/\_raw\_/\_orf\_/;
	#set the full output file path
	my $output  = $outdir . "/" . $outfile; 
	#run transeq
	my $results = run_transeq( $input, $output, $remote_scripts_path );
	if( $results =~ m/^Your job (\d+) / ) {
	    my $job_id = $1;
	    $jobs{$job_id} = $file;
	}
	else{
	    warn( "Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!. Exiting.\n" );
	    exit(0);
	}
    }
}

#now we run the array job, if $array is set
if( $array ){
    my $results = run_transeq_array( $indir, $inbasename, $outdir, $outbasename, $array_length, $remote_scripts_path );
    #6971202.1-4:1
    #Your job-array 6971206.1-4:1 ("run_transeq_array.sh") has been submitted
    if( $results =~ m/^Your job-array (\d+)\./ ) {
	my $job_id = $1;
	$jobs{$job_id}++;
    }
    else{
	warn( "Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!. Exiting.\n" );
	exit(0);
    }
}

#At this point, we have a lot ofjobs in the queue. Let's monitor the queue and report back to local when jobs are complete 
my @job_ids = keys( %jobs );
my $time = remote_job_listener( \@job_ids, $waittime );

#later we'll come back here and add a job completion/relauncher check.

###############
# SUBROUTINES #
###############
sub run_transeq_array{
    my( $indir, $inbasename, $outdir, $outbasename, $array_length, $remote_scripts_path ) = @_;
    my $script = $remote_scripts_path . "/run_transeq_array.sh";
    my @args = ( "-t 1-" . $array_length, $script, $indir, $inbasename, $outdir, $outbasename);
    print( "qsub ", "@args\n" );
    my $results = capture( "qsub " . "@args" );
    if( $EXITVAL != 0 ){
        warn( "Error running transeq array on remote server: $results\n" );
        exit(0);
    }
    return $results;
}


sub run_transeq{
    my ( $input, $output, $remote_scripts_path ) = @_;
    my $script = $remote_scripts_path . "/run_transeq.sh";
    my @args = ( $script, $input, $output);
    print( "qsub ", "@args\n" );
    my $results = capture( "qsub " . "@args" );
    if( $EXITVAL != 0 ){
        warn( "Error running transeq on remote server: $results\n" );
        exit(0);
    }
    return $results;
}

sub remote_job_listener{
    my $jobs     = shift;
    my $waittime = shift;
    my $numwaits = 0;
    my %status   = ();
     while(1){
        #stop checking if every job has a finished status
        last if( scalar( keys( %status ) ) == scalar( @{ $jobs } ) );
        #call qstat and grab the output
        my $results = execute_qstat();
        #see if any of the jobs are complete. pass on those we've already finished
        foreach my $jobid( @{ $jobs } ){
            next if( exists( $status{$jobid} ) );
            if( $results !~ m/$jobid/ ){
                $status{$jobid}++;
            }
        }
        sleep( $waittime );
        $numwaits++
    }
    my $time = $numwaits * $waittime;
    return $time;
}

sub execute_qstat{
    my $cmd = shift;
    my $results = capture( "qstat" );
    if( $EXITVAL != 0 ){
	warn( "Error running execute_cmd: $results\n" );
    }
    return $results;
}
