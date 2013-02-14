#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use IPC::System::Simple qw(capture $EXITVAL);

my($indir, $outdir, $waittime, $unsplit_orfs_dir, $logsdir);
my $remote_scripts_path = undef; # = "/netapp/home/sharpton/projects/MRC/scripts/";


my $array = 1; # apparently it is ALWAYS an array job no matter what??

GetOptions(
    "i=s" => \$indir,
    "o=s" => \$outdir,
    "w=i" => \$waittime,
    "s=s" => \$remote_scripts_path,
    "u=s" => \$unsplit_orfs_dir, #if defined, we will split translated reads on stop. put unsplit data here.
    "l=s" => \$logsdir,
);


defined($remote_scripts_path) or die "remote scripts path must be defined!";

my $split_orfs = 0;
my $split_outdir;

if( defined( $unsplit_orfs_dir ) ){
    $split_orfs = 1;
}
#reset some vars to integrate orf splitting into the code below
if( $split_orfs ){
    $split_outdir = $outdir;
    $outdir = $unsplit_orfs_dir;
}

print "working on remote server...\n";

opendir( IN, $indir ) || die "Can't opendir $indir for read: $!";
my @infiles = readdir(IN);
closedir( IN );

my %jobs = ();  #create a jobid storage log (hash)
my ($inbasename, $outbasename); #grab the files that we want to translate
my $array_length = 0;

warn("We got a total of " . scalar(@infiles) . " candidate input files from the input directory <$indir> to check through. Note that this includes the special files '.' and '..', which are not actually input files.");

if (scalar(@infiles) == 2) {
    warn("There is probably a serious problem here; it appears that we did not have any valid input files! Better double-check that input directory: $indir\nProbably something broke EARLIER in the process, leading that directory to be empty!");
}

foreach my $file( @infiles ){
    warn "Checking through the input files, specifically, the file <$file>...";
    next if ($file =~ m/^\./ ); # Skip any files starting with a dot, including the special ones: "." and ".."

    if ($array) { #need to know how many array jobs to launch
	$array_length++; 
	#only need to process the single file, because the array jobs do the rest of the work.
	if(!(defined($inbasename) ) ){
	    #let's set some vars, but we won't process until we've looped over the entire directory
	    my $modified_basename = undef;
	    if( $file =~ m/(.*)split\_*/ ){
		$modified_basename = $1 . "split_";
	    } else {
		die "Can't grab $modified_basename from $file";
	    }
	    $inbasename  = $modified_basename;
	    $outbasename = $modified_basename;
	    $outbasename =~ s/\_raw\_/\_orf\_/; # change "/raw/" to "/orf/"
	}
    } else{
	my $input   = "$indir/$file"; 	#set the full input file path
	my $outfile = $file; 	#need to change the basename for the output file
	$outfile =~ s/\_raw\_/\_orf\_/; ## change "/raw/" to "/orf/"
	my $output  = "$outdir/$outfile";  	#set the full output file path
	my $results;

	#run transeq
	if( $split_orfs ) {
	    my $split_output = "$split_outdir/$outfile"; # confusing...
	    $results = run_transeq($input, $output, $remote_scripts_path, $logsdir, $split_output);
	} else{
	    $results = run_transeq($input, $output, $remote_scripts_path, $logsdir);
	}

	if( $results =~ m/^Your job (\d+) / ) {
	    my $job_id = $1;
	    $jobs{$job_id} = $file;
	} else{
	    die("Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!. Exiting.");
	}
    }
}

#now we run the array job, if $array is set
if ($array){
    my $results;
    if ($split_orfs) {
	$results = run_transeq_array( $indir, $inbasename, $outdir, $outbasename, $array_length, $remote_scripts_path, $logsdir, $split_outdir);
    } else{
	$results = run_transeq_array( $indir, $inbasename, $outdir, $outbasename, $array_length, $remote_scripts_path, $logsdir );
    }
    #6971202.1-4:1
    #Your job-array 6971206.1-4:1 ("run_transeq_array.sh") has been submitted
    if( $results =~ m/^Your job-array (\d+)\./ ) {
	my $job_id = $1;
	$jobs{$job_id}++;
    }
    else{
	die( "Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!. Exiting.");
    }
}

#At this point, we have a lot ofjobs in the queue. Let's monitor the queue and report back to local when jobs are complete 
my @job_ids = keys( %jobs );
my $time = remote_job_listener( \@job_ids, $waittime );

###############
# SUBROUTINES #
###############
sub run_transeq_array {
    my( $indir, $inbasename, $outdir, $outbasename, $array_length, $remote_scripts_path, $logsdir, $split_outdir) = @_;
    defined($indir) or die "missing indir!";
    defined($inbasename) or die "missing inbasename!";
    defined($outdir) or die "missing outdir!";
    defined($outbasename) or die "missing outbasename!";
    defined($array_length) or die "missing array_length!";
    defined($remote_scripts_path) or die "missing remote_scripts_path!";
    defined($logsdir) or die "missing logsdir!";
    # The final variable, $split_outdir, is OPTIONAL and does not need to be defined

    my $script = "$remote_scripts_path/run_transeq_array.sh";

    ($array_length > 1) or die "qsub requires that the second array length parameter CANNOT be less than the first one. However, in our case, the array length is: $array_length (which is less than 1!).";

    my $qsubArrayJobArgument = "t 1-${array_length}";
    my @args = ($qsubArrayJobArgument, $script, $indir, $inbasename, $outdir, $outbasename, $remote_scripts_path, $logsdir);
    if (defined($split_outdir) && $split_outdir) { push(@args, $split_outdir); } ## add $split_outdir to the argument list, if it was specified

    warn("run_transeq_handler.pl: (run_transeq_array): About to execute this command: qsub @args");
    my $results = IPC::System::Simple::capture("qsub " . "@args");
    if( $EXITVAL != 0 ) { die("Error in run_transeq_array (running transeq array) on remote server: $results "); }
    return $results;
}


sub run_transeq {
    my ( $input, $output, $remote_scripts_path, $logsdir, $split_output ) = @_;
    my $script = "$remote_scripts_path/run_transeq.sh";
    my @args = ($script, $input, $output, $logsdir);
    if (defined($split_output) && $split_output) { push(@args, $split_output); } ## add it to the argument list, if it was specified

    warn("run_transeq_handler.pl: (run_transeq): About to execute this command: qsub @args");
    my $results = IPC::System::Simple::capture("qsub " . "@args");
    if($EXITVAL != 0) { die( "Error running transeq (run_transeq) on remote server: $results "); }
    return $results;
}

sub remote_job_listener{
    my $jobs     = shift;
    my $waittime = shift;
    my %status   = ();
    my $startTimeInSeconds = time();
    while(1){
        last if( scalar( keys( %status ) ) == scalar( @{ $jobs } ) ); #stop checking if every job has a finished status
        my $results = execute_qstat(); #call qstat and grab the output
        foreach my $jobid( @{ $jobs } ){ #see if any of the jobs are complete. pass on those we've already finished
            next if( exists( $status{$jobid} ) );
            if($results !~ m/$jobid/) {
                $status{$jobid}++; # I am not sure if this is robust against jobs having the same SUB-string in them. Like "199" versus "1999"
            }
        }
        sleep($waittime);
    }
    return (time() - $startTimeInSeconds); # return amount of wall-clock time this took
}

sub execute_qstat {
    my ($cmd) = @_;
    my $results = IPC::System::Simple::capture("qstat");
    if ($EXITVAL != 0) {
	warn( "Error running execute_cmd: $results" );
    }
    return $results;
}
