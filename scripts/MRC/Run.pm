#!/usr/bin/perl -w

#MRC::Run.pm - Handles workhorse methods in the MRC workflow
#Copyright (C) 2011  Thomas J. Sharpton 
#author contact: thomas.sharpton@gladstone.ucsf.edu
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#    
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#    
#You should have received a copy of the GNU General Public License
#along with this program (see LICENSE.txt).  If not, see 
#<http://www.gnu.org/licenses/>.

package MRC::Run;

use strict;
use MRC;
use MRC::DB;
use Data::Dumper;
use Sfams::Schema;
use File::Basename;
use File::Cat;
use IPC::System::Simple qw(capture $EXITVAL);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError);
use Bio::SearchIO;
use DBIx::Class::ResultClass::HashRefInflator;
use Benchmark;

# ServerAliveInterval : in SECONDS
# ServerAliveCountMax : number of times to keep the connection alive
# Total keep-alive time in minutes = (ServerAliveInterval*ServerAliveCountMax)/60 minutes
my $GLOBAL_SSH_TIMEOUT_OPTIONS_STRING = '-o TCPKeepAlive=no -o ServerAliveInterval=30 -o ServerAliveCountMax=480';

my $HMMDB_DIR = "HMMdbs";
my $BLASTDB_DIR = "BLASTdbs";


sub _remote_transfer_internal($$$) {
    my ($src_path, $dest_path, $path_type) = @_;
    ($path_type eq 'directory' or $path_type eq 'file') or die "unsupported path type! must be 'file' or 'directory'. Yours was: '$path_type'.";
    my $COMPRESSION_FLAG = '-C';
    my $RECURSIVE_FLAG = ($path_type eq 'directory') ? '-r' : ''; # only specify recursion if DIRECTORIES are being transferred!
    my $FLAGS = "$COMPRESSION_FLAG $RECURSIVE_FLAG";
    my @args = ($FLAGS, $GLOBAL_SSH_TIMEOUT_OPTIONS_STRING, $src_path, $dest_path);
    MRC::notifyAboutScp("remote_transfer ($path_type): scp @args");
    my $results = IPC::System::Simple::capture("scp @args");
    (0 == $EXITVAL) or die("Error transferring $src_path to $dest_path using $path_type: $results");
    return $results;
}

sub ends_in_a_slash($) { return ($_[0] =~ /\/$/); } # return whether or not the first (and only) argument to this function ends in a forward slash (/)

sub remote_transfer_directory($$) {
    my ($src_path, $dest_path) = @_;
    return(_remote_transfer_internal($src_path, $dest_path, 'directory'));
}

sub remote_transfer_file($$) {
    my ($src_path, $dest_path) = @_;
    (!ends_in_a_slash($src_path)) or die "Since you are transferring a FILE, the source must not end in a slash (the slash indicates that the source is a DIRECTORY, which is probably incorrect). Your source file was <$src_path> and destination file was <$dest_path>.";
    return(_remote_transfer_internal($src_path, $dest_path, 'file'));
}


sub transfer_file($$) {
    my ($src_path, $dest_path) = @_;
    (!ends_in_a_slash($src_path))  or die "Since you are transferring a FILE to a new FILE location, the source must not end in a slash.  Your source was <$src_path>, and destination was <$dest_path>.";
    (!ends_in_a_slash($dest_path)) or die "Since you are transferring a FILE to a new FILE location, the destination must not end in a slash. This will be the new location of the file, NOT the name of the parent directory. Your source was <$src_path>, and destination was <$dest_path>. If you want to transfer a file INTO a directory, use the function transfer_file_into_directory instead.";
    return(_remote_transfer_internal($src_path, $dest_path, 'file'));
}

sub transfer_directory($$) {
    my ($src_path, $dest_path) = @_;
    (!ends_in_a_slash($src_path))  or die "Since you are transferring a DIRECTORY, the source must not end in a slash.  Your source was <$src_path>, and destination was <$dest_path>.";
    (!ends_in_a_slash($dest_path)) or die "Since you are transferring a DIRECTORY, the destination must not end in a slash. This will be the new location of the directory, NOT the name of the parent directory. Your source was <$src_path>, and destination was <$dest_path>.";
    return(_remote_transfer_internal($src_path, $dest_path, 'directory'));
}

sub transfer_file_into_directory($$) {
    # source: a file (that does NOT end in a slash!)
    # destination: a directory (that ends with a slash!)
    my ($src_path, $dest_path) = @_;
    (!ends_in_a_slash($src_path)) or die "Since you are transferring a FILE, the source must not end in a slash (the slash indicates that the source is a DIRECTORY, which is probably incorrect). Your source file was <$src_path> and destination file was <$dest_path>.";
    (ends_in_a_slash($dest_path)) or die "Since you are transferring a file INTO a directory, the destination path MUST END IN A SLASH (indicating that it is a destination directory. Otherwise, it is ambiguous as to whether you want to transfer the file INTO the directory, or if you want the file to be written to OVERWRITE that directory. Your source file was <$src_path> and destination file was <$dest_path>.";
    return(_remote_transfer_internal($src_path, $dest_path, 'file'));
}


sub execute_ssh_cmd($$;$) {
    my ($connection, $remote_cmd, $verbose) = @_;
    my $verboseFlag = (defined($verbose) && $verbose) ? '-v' : '';
    my $sshCmd = "ssh $GLOBAL_SSH_TIMEOUT_OPTIONS_STRING $verboseFlag $connection $remote_cmd";
    MRC::notifyAboutRemoteCmd($sshCmd);
    my $results = IPC::System::Simple::capture($sshCmd);
    (0 == $EXITVAL) or die( "Error running this ssh command: $sshCmd: $results" );
    return $results; ## <-- this gets used! Don't remove it.
}

sub clean_project{
    my ($self, $project_id) = @_;
    my $samples = $self->MRC::DB::get_samples_by_project_id( $project_id ); # apparently $samples is a scalar datatype that we can iterate over
    while(my $sample = $samples->next()){ # go through all the samples, I guess!
	my $sample_id = $sample->sample_id();
	$self->MRC::DB::delete_search_result_by_sample_id( $sample_id );
	$self->MRC::DB::delete_family_member_by_sample_id( $sample_id );
	$self->MRC::DB::delete_orfs_by_sample_id( $sample_id );
	$self->MRC::DB::delete_reads_by_sample_id( $sample_id );
	$self->MRC::DB::delete_sample( $sample_id );
    }
    $self->MRC::DB::delete_project( $project_id );
    $self->MRC::DB::delete_ffdb_project( $project_id );
}


sub exec_remote_cmd($$) {
    my ($self, $remote_cmd) = @_;
    my $connection = $self->get_remote_connection();
    if ($remote_cmd =~ /\'/) {
	die "Remote commands aren't allowed to include the single quote character currently. Sorry!";
    }
    my $sshCmd = "ssh $GLOBAL_SSH_TIMEOUT_OPTIONS_STRING -v $connection '$remote_cmd' "; # remote-cmd gets single quotes around it!
    MRC::notifyAboutRemoteCmd($sshCmd);
    my $results = IPC::System::Simple::capture($sshCmd);
    (0 == $EXITVAL) or die( "Error running this remote command: $sshCmd: $results" );
    return $results; ## <-- this gets used! Don't remove it.
}


#currently uses @suffix with basename to successfully parse off .fa. may need to change
sub get_partitioned_samples{
    my ($self, $path) = @_;
    my %samples = ();    

    opendir( PROJ, $path ) || die "Can't open the directory $path for read: $!\n";     #open the directory and get the sample names and paths, 
    my @files = readdir(PROJ);
    closedir(PROJ);

    foreach my $file (@files) {
	next if ( $file =~ m/^\./ || $file =~ m/hmmscan/ || $file =~ m/output/); # skip hmmscan and output, for whatever reason
	next if ( -d "$path/$file" ); # skip directories, apparently
	if($file =~ m/DESCRIPT\.txt/){ # <-- see if there's a description file
	    my $text = ''; # blank
	    open(DESC, "$path/$file") || die "Can't open project description file $file for read: $!. Project is $path.\n";
	    while(<DESC>){
		chomp($_);
		$text .= " " . $_; # append the line
	    }
	    close(DESC);
	    $self->set_project_desc($text);
	} else {
	    #get sample name here, simple parse on the period in file name
    	    my $thisSample = basename($file, (".fa", ".fna"));
	    $samples{$thisSample}->{"path"} = "$path/$file";
	}
    }
    warn("Adding samples to analysis object at path <$path>.");
    $self->set_samples( \%samples );
    #return $self;
}

sub load_project{
    my $self    = shift;
    my $path    = shift;
    my $nseqs_per_samp_split = shift; #how many seqs should each sample split file contain?
    #get project name and load
    my ( $name, $dir, $suffix ) = fileparse( $path );        
    my $proj = $self->MRC::DB::create_project( $name, $self->get_project_desc() );    
    my $pid  = $proj->project_id();
    warn("Loading project with PID $pid, files found at <$path>.\n");
    #store vars in object
    $self->set_project_path($path);
    $self->set_project_id($pid);
    #process the samples associated with project
    $self->MRC::Run::load_samples();
    $self->MRC::DB::build_project_ffdb();
    $self->MRC::DB::build_sample_ffdb( $nseqs_per_samp_split ); #this also splits the sample file
    warn("Project with PID $pid was successfully loaded!\n");
    #return $self;
}

sub load_samples{
    my $self   = shift;
    my %samples = %{ $self->get_samples() };
    my $numSamples = scalar( keys(%samples) );
    my $plural = ($numSamples == 1) ? '' : 's'; # pluralize 'samples'
    MRC::notify("Run.pm: load_samples: Processing $numSamples sample${plural} associated with project PID #" . $self->get_project_id() . " ");
    foreach my $samp( keys( %samples ) ){
	my $pid = $self->get_project_id();
	my $insert;
	eval { # <-- this is like a "try" (in the "try/catch" sense)
	    $insert = $self->MRC::DB::create_sample($samp, $pid );
	};
	if ($@) { # <-- this is like a "catch" block in the try/catch sense. "$@" is the exception message (a human-readable string).
	    # Caught an exception! Probably create_sample complained about a duplicate entry in the database!
	    my $errMsg = $@;
	    chomp($errMsg);
	    if ($errMsg =~ m/duplicate entry/i) {
		print STDERR ("*" x 80 . "\n");
		print STDERR ("DATABASE INSERTION ERROR\nCaught an exception when attempting to add sample \"$samp\" for project PID #${pid} to the database.\nThe exception message was:\n$errMsg\n");
		print STDERR ("Note that the error above was a DUPLICATE ENTRY error.\nThis is a VERY COMMON error, and is due to the database already having a sample/project ID with the same number as the one we are attempting to insert. This most often happens if a run is interrupted---so there is an entry in the database for your project run, but there are no files on the filesystem for it, since it did not complete the run. The solution to this problem is to manually remove the entries for project id #$pid from the Mysql database.\n");
		print STDERR ("You can do this as follows:\n");
		print STDERR ("   1. Go to your database server (probably " . $self->get_db_hostname() . ")\n");
		print STDERR ("   2. Log into mysql with this command: mysql -u YOURNAME -p   <--- YOURNAME is probably \"" . $self->get_username() . "\"\n");
		print STDERR ("   3. Type these commands in mysql: use ***THE DATABASE***;   <--- THE DATABASE is probably " . $self->get_db_name() . "\n");
		print STDERR ("   4.                        mysql: select * from project;    <--- just to look at the projects.\n");
		print STDERR ("   5.                        mysql: delete from project where project_id=${pid};    <-- actually deletes this project.\n");
		print STDERR ("   6. Then you can log out of mysql and hopefully re-run this script successfully!\n");
		print STDERR ("   7. You MAY also need to delete the entry from the 'samples' table in MySQL that has the same name as this sample/proejct.\n");
		print STDERR ("   8. Try connecting to mysql, then typing 'select * from samples;' . You should see an OLD project ID (but with the same textual name as this one) that may be preventing you from running another analysis. Delete that id ('delete from samples where sample_id=the_bad_id;'");
		my $mrcCleanCommand = (qq{perl \$MRC_LOCAL/scripts/mrc_clean_project.pl} 
				       . qq{ --pid=} . $pid
				       . qq{ --dbuser=} . $self->get_username()
				       . qq{ --dbpass=} . "PUT_YOUR_PASSWORD_HERE"
				       . qq{ --dbhost=} . $self->get_db_hostname()
				       . qq{ --ffdb=} . $self->get_ffdb()
				       . qq{ --dbname=} . $self->get_db_name()
				       . qq{ --schema=} . $self->{"schema_name"});
		print STDERR ("Or maybe run this: $mrcCleanCommand\n");
		print STDERR ("*" x 80 . "\n");
		die "Terminating: Duplicate database entry error! See above for a possible solution.";
	    }
	    die "Terminating: Database insertion error! See the message above for more details..."; # no "newline" with die!
	}
	
	my $seqs                = Bio::SeqIO->new( -file => $samples{$samp}->{"path"}, -format => 'fasta' );
	$samples{$samp}->{"id"} = $insert->sample_id();
	my $sid                 = $insert->sample_id(); # just a short name for the sample ID above
	my $numReads            = 0;
	
	if ($self->is_multiload()) {
	    my @read_names = (); # empty list to start...
	    while (my $read = $seqs->next_seq()) {
		my $read_name = $read->display_id();
		push( @read_names, $read_name );
		$numReads++;
	    }
	    $self->MRC::DB::create_multi_metareads( $sid, \@read_names );
	} else{
	    while (my $read = $seqs->next_seq()) { ## If we AREN'T multi-loading, then do this...
		my $read_name = $read->display_id();
		$self->MRC::DB::create_metaread($read_name, $sid);
		$numReads++;
	    }
	}

	MRC::notify("Loaded $numReads reads for sample $sid into the database.");
    }
    $self->set_samples( \%samples ); #uncertain if this is necessary
    MRC::notify("Successfully loaded $numSamples sample$plural associated with the project PID #" . $self->get_project_id() . " ");
}

sub back_load_project(){
    my $self = shift;
    my $project_id = shift;
    my $ffdb = $self->get_ffdb();
    $self->set_project_id( $project_id );
    $self->set_project_path("$ffdb/projects/$project_id");
    if( $self->is_remote ){
	$self->set_remote_hmmscan_script(   $self->get_remote_project_path() . "/run_hmmscan.sh" );
	$self->set_remote_hmmsearch_script( $self->get_remote_project_path() . "/run_hmmsearch.sh" );
        $self->set_remote_blast_script(     $self->get_remote_project_path() . "/run_blast.sh" );
        $self->set_remote_last_script(      $self->get_remote_project_path() . "/run_last.sh" );
        $self->set_remote_formatdb_script(  $self->get_remote_project_path() . "/run_formatdb.sh" );
        $self->set_remote_lastdb_script(    $self->get_remote_project_path() . "/run_lastdb.sh" );
	$self->set_remote_project_log_dir(  $self->get_remote_project_path() . "/logs" );
    }
}

#this might need extra work to get the "path" element correct foreach sample
sub back_load_samples{
    my $self = shift;
    my $project_id = $self->get_project_id();
    my $project_path = $self->get_project_path();
    opendir( PROJ, $project_path ) || die "can't open $project_path for read: $!\n";
    my @files = readdir( PROJ );
    closedir PROJ;
    my %samples = ();
    foreach my $file( @files ){
	next if ( $file =~ m/^\./ || $file =~ m/logs/ || $file =~ m/hmmscan/ || $file =~ m/output/ || $file =~ m/\.sh/ );
	my $sample_id = $file; # hmm.
	my $samp    = $self->MRC::DB::get_sample_by_sample_id( $sample_id );
#	my $sample_name = $samp->name();
#	$samples{$sample_name}->{"id"} = $sample_id;
	my $sample_alt_id = $samp->sample_alt_id();
	$samples{$sample_alt_id}->{"id"} = $sample_id;
    }
    $self->set_samples( \%samples );
    #back load remote data
    if( $self->is_remote() ){
	$self->set_remote_hmmscan_script(   $self->get_remote_project_path() . "/run_hmmscan.sh" );
        $self->set_remote_hmmsearch_script( $self->get_remote_project_path() . "/run_hmmsearch.sh" );
        $self->set_remote_blast_script(     $self->get_remote_project_path() . "/run_blast.sh" );
        $self->set_remote_project_log_dir(  $self->get_remote_project_path() . "/logs" );
    }
    warn("Back-loading of samples is now complete.");
    #return $self;
}

# Note this message: "this is a compute side function. don't use db vars"
sub translate_reads{
    my ($self, $input, $output) = @_;
    my @args     = ("$input", "$output", "-frame=6");
    # so... $input and $output should be what, directories or something?
    warn "Should add a sanity check here to make sure $input and $output both exist I guess.";

    my $results  = IPC::System::Simple::capture("transeq @args" );
    (0 == $EXITVAL) or die("Error translating sequences in $input: $results");
    return $results;
}

# Run hmmscan
sub run_hmmscan{
    my ($self, $inseqs, $hmmdb, $output, $tblout) = @_; # tblout means: "save $output as a tblast style table 1=yes, 0=no"
    my @args = ($tblout) # ternary operator
	? ( "--domE 0.001", "--domtblout $output", "$hmmdb", "$inseqs" ) # YES, $tblout
	: ("$hmmdb", "$inseqs", "> $output"); # NO, no $tblout
    my $results  = IPC::System::Simple::capture( "hmmscan @args" );
    (0 == $EXITVAL) or die("Error translating sequences in $inseqs: $results");
}

#this method may be faster, but suffers from having a few hardcoded parameters.
#because orfs are necessairly assigned to a sample_id via the ffdb structure, we can
#simply lookup the read_id to sample_id relationship via the ffdb, rather than the DB.
#see load_orf_dblookup for the older method.
sub load_orf{
    my ($self, $orf_alt_id, $read_alt_id, $sample_id) = @_;
    #A sample cannot have identical reads in it (same DNA string ok, but must have unique alt_ids)
    #Regardless, we need to check to ensure we have a single value
    my $reads = $self->get_schema->resultset("Metaread")->search(
	{
	    read_alt_id => $read_alt_id,
	    sample_id   => $sample_id,
	}
    );
    if ($reads->count() > 1){
	die "Found multiple reads that match read_alt_id: $read_alt_id and sample_id: $sample_id in load_orf. Cannot continue!";
    }
    my $read = $reads->next();
    my $read_id = $read->read_id();
    $self->MRC::DB::insert_orf($orf_alt_id, $read_id, $sample_id);
}

sub load_multi_orfs{
    my ($self, $orfsBioSeqObject, $sample_id, $algo) = @_;   # $orfsBioSeqObject is a Bio::Seq object
    my %orf_map    = (); #orf_alt_id to read_id
    my %read_map   = (); #read_alt_id to read_id
    my $count      = 0;
    while (my $orf = $orfsBioSeqObject->next_seq() ){
	$count++;
	my $orf_alt_id  = $orf->display_id();
	my $read_alt_id = MRC::Run::parse_orf_id( $orf_alt_id, $algo );
	#get the read id, but only if we haven't see this read before
	my $read_id = undef;
	if(defined( $read_map{ $read_alt_id } ) ){
	    $read_id = $read_map{ $read_alt_id };
	} else{
	    my $reads = $self->get_schema->resultset("Metaread")->search(
		{
		    read_alt_id => $read_alt_id,
		    sample_id   => $sample_id,
		}
		);
	    if ($reads->count() > 1) { die("Found multiple reads that match read_alt_id: $read_alt_id and sample_id: $sample_id in load_orf. Cannot continue!"); }
	    my $read = $reads->next();
	    $read_id = $read->read_id();
	    $read_map{ $read_alt_id } = $read_id;
	}
	$orf_map{ $orf_alt_id } = $read_id;
    }
    $self->MRC::DB::insert_multi_orfs( $sample_id, \%orf_map );
    MRC::notify("Bulk loaded $count orfs to the database.");
}


# #the efficiency of this method could be improved!
# sub load_orf_old{
#     my $self        = shift;
#     my $orf_alt_id  = shift;
#     my $read_alt_id = shift;
#     my $sampref     = shift;
#     my %samples     = %{ $sampref };
#     my $reads = $self->get_schema->resultset("Metaread")->search(
# 	{
# 	    read_alt_id => $read_alt_id,
# 	}
#     );
#     while( my $read = $reads->next() ){
# 	my $sample_id = $read->sample_id();
# 	if( exists( $samples{$sample_id} ) ){
# 	    my $read_id = $read->read_id();
# 	    $self->insert_orf( $orf_alt_id, $read_id, $sample_id );
# 	    #A project cannot have identical reads in it (same DNA string ok, but must have unique alt_ids)
# 	    last;
# 	}
#     }
# }

sub parse_orf_id{
    my $orfid  = shift;
    my $method = shift;
    my $read_id = ();
    if( $method eq "transeq" ){
	if( $orfid =~ m/^(.*?)\_\d$/ ){
	    $read_id = $1;
	}
	else{
	    die "Can't parse read_id from $orfid\n";
	}
    }
    if( $method eq "transeq_split" ){
	if( $orfid =~ m/^(.*?)\_\d_\d+$/ ){
	    $read_id = $1;
	}
	else{
	    die "Can't parse read_id from $orfid\n";
	}
    }

    return $read_id;
}

#classifies reads into predefined families given hmmscan results. eventually will take various input parameters to guide classification
#processes each orf split independently and iteratively (this works because we hmmscan, not hmmsearch). for each split, eval all search
#result files for that split and build a hash that stores the classification results for each sequence within the split.
sub classify_reads{
    my $self = shift;
    my $sample_id  = shift;
    my $orf_split  = shift; #just the file name of the split, not the full path
    my $class_id   = shift; #the classification_id
    my $algo       = shift;
    my $top_hit_type = shift;
    #remember, each orf_split has its own search_results sub directory
    my $search_results = $self->get_sample_path( $sample_id ) . "/search_results/$algo/$orf_split";
    print "processing $search_results using best $top_hit_type\n";
#    my $hmmdb_name     = $self->get_hmmdb_name();
#    my $blastdb_name   = $self->get_blastdb_name();
    my $query_seqs     = $self->get_sample_path($sample_id) . "/orfs/$orf_split";
    #this is a hash
    my $hit_map        = initialize_hit_map( $query_seqs );
    #open search results, get all results for this split
    opendir( RES, $search_results ) || die "Can't open $search_results for read in classify_reads: $!\n";
    my @result_files = readdir( RES );
    closedir( RES );
    foreach my $result_file( @result_files ){
	next unless( $result_file =~ m/$orf_split/ );
	#troubleshooting
#	next unless( $result_file =~ m/\_110\.tab/ );

	if( $algo eq "hmmscan" ){
	    #use the database name to enable multiple searches against different databases
	    my $database_name = $self->get_hmmdb_name();
	    next unless( $result_file =~ m/$database_name/ );	
	    $hit_map = $self->MRC::Run::parse_search_results("$search_results/${result_file}", "hmmscan", $hit_map );
	}
	elsif( $algo eq "hmmsearch" ){
	    #use the database name to enable multiple searches against different databases
	    my $database_name = $self->get_hmmdb_name();
	    next unless( $result_file =~ m/$database_name/ );
	    print "processing $result_file\n";
	    $hit_map = $self->MRC::Run::parse_search_results("$search_results/$result_file", "hmmsearch", $hit_map );
	}
	elsif( $algo eq "blast" ){
	    #use the database name to enable multiple searches against different databases
	    my $database_name = $self->get_blastdb_name();
	    next unless( $result_file =~ m/$database_name/ );
	    #because blast doesn't give sequence lengths in report, need the input file to get seq lengths. add $query_seqs to function
	    $hit_map = $self->MRC::Run::parse_search_results("$search_results/$result_file", "blast", $hit_map, $query_seqs );
	}
	elsif( $algo eq "last" ){
	    #use the database name to enable multiple searches against different databases
	    my $database_name = $self->get_blastdb_name();
	    next unless( $result_file =~ m/$database_name/ );
	    #because blast doesn't give sequence lengths in report, need the input file to get seq lengths. add $query_seqs to function
	    $hit_map = $self->MRC::Run::parse_search_results("$search_results/$result_file", "last", $hit_map, $query_seqs );	    
	}
    }
    #now insert the data into the database
    my $is_strict = $self->is_strict_clustering();
    my $n_hits    = 0;
    my %orf_hits   = (); #a hash for bulk loading hits: orf_id -> famid, only works for strict clustering!
    #if we want best hit per metaread, use this block
    if( $top_hit_type eq "read" ){
	print "Filtering hits to identify top hit per read, on " . `date`;
	#dbi is needed for speed on big data sets
#	timethese( 5000, 
#		   { 
#		       'Method DBIx'  =>  sub{ $hit_map = $self->MRC::Run::filter_hit_map_for_top_reads( $sample_id, $is_strict, $algo, $hit_map ) },
#		       'Method DBI'   =>  sub{ $hit_map = $self->MRC::Run::filter_hit_map_for_top_reads_dbi( $sample_id, $is_strict, $algo, $hit_map ) },
#		       'Method DBI_s' =>  sub{ $hit_map = $self->MRC::Run::filter_hit_map_for_top_reads_dbi_single( $sample_id, $is_strict, $algo, $hit_map ) },
#		   }
#	    );

	$hit_map = $self->MRC::Run::filter_hit_map_for_top_reads_dbi_single( $orf_split, $sample_id, $is_strict, $algo, $hit_map );
	print "finished filtering, on " . `date`;
    }
    #dbi for speed
    my $dbh  = $self->MRC::DB::build_dbh();
    while( my ( $orf_alt_id, $value) = each %$hit_map ){
	#note: since we know which reads don't have hits, we could, here produce a summary stat regarding unclassified reads...
	#for now, we won't add these to the datbase
	next unless( $hit_map->{$orf_alt_id}->{"has_hit"} );
	#how we insert into the db may change depending on whether we do strict of fuzzy clustering
	if( $is_strict ){
	    $n_hits++;
	    #turn these on if you decide to add search result into the database
#	    my $evalue   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
#	    my $coverage = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
#	    my $score    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
	    my $hit    = $hit_map->{$orf_alt_id}->{$is_strict}->{"target"};
	    my $famid;
	    #blast hits are gene_oids, which map to famids via the database (might change refdb seq headers to include famid in header
	    #which would enable faster flatfile lookup).
	    if( $algo eq "blast" || $algo eq "last" ){
		my $family = $self->MRC::DB::get_family_from_geneoid( $hit );
		$family->result_class('DBIx::Class::ResultClass::HashRefInflator');
                #if multiple fams, taking the first that's found. 
		my $first = $family->first;
		$famid    = $first->{"famid"};			  
	    }
	    else{
		$famid = $hit;
	    }	
	    #because we have an index on sample_id and orf_alt_id, we can speed this up by passing sample id
	    #my $orf_id = $self->MRC::DB::get_orf_from_alt_id( $orf_alt_id, $sample_id )->orf_id(); 
	    #use DBI for speed
	    my $orfs       = $self->MRC::DB::get_orf_from_alt_id_dbi( $dbh, $orf_alt_id, $sample_id );
	    my $orf        = $orfs->fetchall_arrayref();
	    my $orf_id     = $orf->[0][0];
	    $orfs->finish; # I guess this is a function?

	    #need to ensure that this stores the raw values, need some upper limit thresholds, so maybe we need classification_id here. simpler to store anything with evalue < 1. Still not sure I want to store this in the DB.
	    #$self->MRC::DB::insert_search_result( $orf_id, $famid, $evalue, $score, $coverage );
	    
	    if( $self->is_multiload() ){ 	    #let's try bulk loading to speed things up....
		$orf_hits{$orf_id} = $famid; #currently only works for strict clustering!
	    } else {
		#otherwise, the slow way...
		$self->MRC::DB::insert_familymember_orf( $orf_id, $famid, $class_id );
	    }
	}
    }
    $self->MRC::DB::disconnect_dbh( $dbh );
    #bulk load here:
    if( $self->is_multiload() ){
	print "Bulk loading classified reads into database\n";
	$self->MRC::DB::create_multi_familymemberss( $class_id, \%orf_hits);
    }
    print "Found and inserted $n_hits threshold passing search results into the database\n";
}

sub filter_hit_map_for_top_reads{
    my ( $self, $sample_id, $is_strict, $algo, $hit_map ) = @_;
#    print "Getting top read hit from $algo\n";
    my $read_map = {}; #stores best hit data for each read
#    print "initialized read map\n";    
    #to speed up the db interaction, we're going to grab orf_ids from disc
    my $path_to_split_orfs = $self->get_sample_path( $sample_id ) . "/orfs";
    foreach my $orf_split_file_name( @{ $self->MRC::DB::get_split_sequence_paths( $path_to_split_orfs , 1 ) } ) {
	open( SEQS, $orf_split_file_name ) || die "Can't open $orf_split_file_name for read: $!\n";
	my $count = 0;
	while( <SEQS> ){
	    chomp $_;
	    if( $_ =~ m/\>(.*?)$/ ){	     
		my $orf_alt_id = $1;
		next unless( $hit_map->{$orf_alt_id}->{"has_hit"} );
		my $orf        = $self->MRC::DB::get_orf_from_alt_id( $orf_alt_id, $sample_id );
		my $read_id    = $orf->{"read_id"};
#PAGER TEST HERE
#    my $page = 1;
#    while( my $orfs = $self->MRC::DB::get_orfs_by_sample( $sample_id, $page ) ){
#	print "getting page $page\n";
#	if( $orfs->all == 0 ){
#	    last;
#	}
#	$page++;
#	for( $orfs->all ){
#	    my $orf = $_;
#	    my $orf_alt_id = $orf->orf_alt_id();
#	    print $orf_alt_id . "\n";
#    }
		if( !defined( $read_map->{$read_id} ) ){
#		    print "adding orf $orf_alt_id\n";
		    $read_map->{$read_id}->{"target"}   = $orf_alt_id;
		    $read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
		    $read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
		    $read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
		}
		else{
#		    print "$orf_alt_id is in our hit map...\n";
		    #for now, we'll simply sort on evalue, since they both pass coverage threshold
		    if( ( $algo ne "last" && $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"} < $read_map->{$read_id}->{"evalue"} ) ||
			( $algo eq "last" && $hit_map->{$orf_alt_id}->{$is_strict}->{"score"} > $read_map->{$read_id}->{"score"}   )
			){
			my $prior_orf_alt_id = $read_map->{$read_id}->{"target"};
#			print "Canceling prior hit: " . $prior_orf_alt_id . "\n";
			$hit_map->{$prior_orf_alt_id}->{"has_hit"} = 0;
	#		print "$read_id\n";
			$read_map->{$read_id}->{"target"}   = $orf_alt_id;
			$read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
			$read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
			$read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
		    }
		    else{
#			print "Canceling $orf_alt_id:\n";
	#		print "..." . $orf_alt_id . " v " . $read_map->{$read_id}->{"target"} . "\n";
	#		print "..." . $hit_map->{$orf_alt_id}->{$is_strict}->{"score"} . " v " . $read_map->{$read_id}->{"score"} . "\n";
	#		print "..." . $hit_map->{$orf_alt_id}->{$is_strict}->{"target"} . " v " . $hit_map->{ $read_map->{$read_id}->{"target"} }->{$is_strict}->{"target"} . "\n";
			#get rid of the hit if it's not better than the current top for the read
			$hit_map->{$orf_alt_id}->{"has_hit"} = 0;
		    }
		}
	    }
	}
	close SEQS;
    }
#    $orfs->finish;
#    $self->MRC::DB::disconnect_dbh( $dbh );
    $read_map = {};
    return $hit_map;
}

sub filter_hit_map_for_top_reads_dbi{
    my ( $self, $sample_id, $is_strict, $algo, $hit_map ) = @_;
#    print "Getting top read hit from $algo\n";
    my $read_map = {}; #stores best hit data for each read
#    print "initialized read map\n";    
    #to speed up the db interaction, we're going to grab orf_ids from disc
    my $path_to_split_orfs = $self->get_sample_path( $sample_id ) . "/orfs/";
#    foreach my $orf_split_file_name( @{ $self->MRC::DB::get_split_sequence_paths( $path_to_split_orfs , 1 ) } ) {
#	open( SEQS, $orf_split_file_name ) || die "Can't open $orf_split_file_name for read: $!\n";
#	while( <SEQS> ){
#	    chomp $_;
#	    if( $_ =~ m/\>(.*?)$/ ){
#		my $orf_alt_id = $1;
#		my $orf        = $self->MRC::DB::get_orf_from_alt_id( $orf_alt_id, $sample_id );
#		my $read_id    = $orf->{"read_id"};
#PAGER TEST HERE
#    my $page = 1;
#    while( my $orfs = $self->MRC::DB::get_orfs_by_sample( $sample_id, $page ) ){
#	print "getting page $page\n";
#	if( $orfs->all == 0 ){
#	    last;
#	}
#	$page++;
#	for( $orfs->all ){
#	    my $orf = $_;
#	    my $orf_alt_id = $orf->orf_alt_id();
#	    print $orf_alt_id . "\n";
#    }

#DBI TEST HERE
    my $dbh  = $self->MRC::DB::build_dbh();
    my $orfs = $self->MRC::DB::get_orfs_by_sample_dbi( $dbh, $sample_id );
    my $max_rows = 10000;
    while( my $vals = $orfs->fetchall_arrayref( {}, $max_rows ) ){
#	print "grabbing rows\n";
#	system( "date" );
	foreach my $orf( @$vals ){
#	    print Dumper $orf;
	    my $orf_alt_id = $orf->{"orf_alt_id"};
	    next unless( $hit_map->{$orf_alt_id}->{"has_hit"} );
	    my $read_id = $orf->{"read_id"};
	    if( !defined( $read_map->{$read_id} ) ){
#		print "adding orf $orf_alt_id\n";
		$read_map->{$read_id}->{"target"}   = $orf_alt_id;
		$read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
		$read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
		$read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
	    }
	    else{
#		print "$orf_alt_id is in our hit map...\n";
		#for now, we'll simply sort on evalue, since they both pass coverage threshold
		if( ( $algo ne "last" && $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"} < $read_map->{$read_id}->{"evalue"} ) ||
		    ( $algo eq "last" && $hit_map->{$orf_alt_id}->{$is_strict}->{"score"} > $read_map->{$read_id}->{"score"}   )
		    ){
		    my $prior_orf_alt_id = $read_map->{$read_id}->{"target"};
#		    print "Canceling prior hit: " . $prior_orf_alt_id . "\n";
		    $hit_map->{$prior_orf_alt_id}->{"has_hit"} = 0;
#		    print "$read_id\n";
		    $read_map->{$read_id}->{"target"}   = $orf_alt_id;
		    $read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
		    $read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
		    $read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
		}
		else{
#		    print "Canceling $orf_alt_id:\n";
		    #		print "..." . $orf_alt_id . " v " . $read_map->{$read_id}->{"target"} . "\n";
		    #		print "..." . $hit_map->{$orf_alt_id}->{$is_strict}->{"score"} . " v " . $read_map->{$read_id}->{"score"} . "\n";
		    #		print "..." . $hit_map->{$orf_alt_id}->{$is_strict}->{"target"} . " v " . $hit_map->{ $read_map->{$read_id}->{"target"} }->{$is_strict}->{"target"} . "\n";
		    #get rid of the hit if it's not better than the current top for the read
		    $hit_map->{$orf_alt_id}->{"has_hit"} = 0;
		}
	    }
	}
    } 
    $orfs->finish;
    $self->MRC::DB::disconnect_dbh( $dbh );
    $read_map = {};
    return $hit_map;
}

sub filter_hit_map_for_top_reads_dbi_single{
    my ( $self, $orf_split, $sample_id, $is_strict, $algo, $hit_map ) = @_;
#    print "Getting top read hit from $algo\n";
    my $read_map = {}; #stores best hit data for each read
#    print "initialized read map\n";    
    #to speed up the db interaction, we're going to grab orf_ids from disc
    my $path_to_split_orfs = $self->get_sample_path( $sample_id ) . "/orfs/";
    my $orf_split_file_name = "$path_to_split_orfs/$orf_split";
    my $dbh  = $self->MRC::DB::build_dbh();
    open( SEQS, $orf_split_file_name ) || die "Can't open $orf_split_file_name for read: $!\n";
    while( <SEQS> ){
	chomp $_;
	if( $_ =~ m/\>(.*?)$/ ){
	    my $orf_alt_id = $1;
	    next unless( $hit_map->{$orf_alt_id}->{"has_hit"} );		
	    my $orfs       = $self->MRC::DB::get_orf_from_alt_id_dbi( $dbh, $orf_alt_id, $sample_id );
	    my $orf        = $orfs->fetchall_arrayref();
	    my $read_id = $orf->[0][2];
	    if( !defined( $read_map->{$read_id} ) ){
#		print "adding orf $orf_alt_id\n";
		$read_map->{$read_id}->{"target"}   = $orf_alt_id;
		$read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
		$read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
		$read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
	    }
	    else{
#		print "$orf_alt_id is in our hit map...\n";
		#for now, we'll simply sort on evalue, since they both pass coverage threshold
		if( ( $algo ne "last" && $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"} < $read_map->{$read_id}->{"evalue"} ) ||
		    ( $algo eq "last" && $hit_map->{$orf_alt_id}->{$is_strict}->{"score"} > $read_map->{$read_id}->{"score"}   )
		    ){
		    my $prior_orf_alt_id = $read_map->{$read_id}->{"target"};
#		    print "Canceling prior hit: " . $prior_orf_alt_id . "\n";
		    $hit_map->{$prior_orf_alt_id}->{"has_hit"} = 0;
#		    print "$read_id\n";
		    $read_map->{$read_id}->{"target"}   = $orf_alt_id;
		    $read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
		    $read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
		    $read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
		}
		else{
#		    print "Canceling $orf_alt_id:\n";
		    #		print "..." . $orf_alt_id . " v " . $read_map->{$read_id}->{"target"} . "\n";
		    #		print "..." . $hit_map->{$orf_alt_id}->{$is_strict}->{"score"} . " v " . $read_map->{$read_id}->{"score"} . "\n";
		    #		print "..." . $hit_map->{$orf_alt_id}->{$is_strict}->{"target"} . " v " . $hit_map->{ $read_map->{$read_id}->{"target"} }->{$is_strict}->{"target"} . "\n";
		    #get rid of the hit if it's not better than the current top for the read
		    $hit_map->{$orf_alt_id}->{"has_hit"} = 0;
		}
	    }
	    $orfs->finish;	
	}
    }
    close SEQS;
    $self->MRC::DB::disconnect_dbh( $dbh );
    $read_map = {};
    return $hit_map;
}



sub parse_search_results{
    my $self         = shift;
    my $file         = shift;
    my $type         = shift;
    my $hit_map      = shift;
    my $orfs_file    = shift; #only required for blast; used to get sequence lengths for coverage calculation
#    my %hit_map      = %{ $r_hit_map };
    #define clustering thresholds
    my $t_evalue   = $self->get_evalue_threshold();   #dom-ieval threshold
    my $t_coverage = $self->get_coverage_threshold(); #coverage threshold (applied to query)
    my $t_score    = $self->get_score_threshold();
    my $is_strict  = $self->is_strict_clustering();   #strict (top-hit) v. fuzzy (all hits above thresholds) clustering. Fuzzy not yet implemented   
    #because blast table doesn't print the sequence lengths (ugh) we have to look up the query length
    my %seqlens    = ();
    if( $type eq "blast" ){
	%seqlens   = %{ _get_sequence_lengths_from_file( $orfs_file ) };
    }
    #open the file and process each line
#    print "classifying reads from $file\n";
    open( RES, "$file" ) || die "can't open $file for read: $!\n";    
    while(<RES>){
	chomp $_;
	if($_ =~ m/^\#/ || $_ =~ m/^$/) {
	    next; # skip comments (lines starting with a '#') and completely-blank lines
	}
	
	my($qid, $qlen, $tid, $tlen, $evalue, $score, $start, $stop);
	if( $type eq "hmmscan" ){
	    my @data = split( ' ', $_ );
	    $qid  = $data[3];
	    $qlen = $data[5];
	    $tid  = $data[0];
	    $tlen = $data[2];
	    $evalue = $data[12]; #this is dom_ievalue
	    $score  = $data[7];  #this is dom score
	    $start  = $data[19]; #this is env_start
	    $stop   = $data[20]; #this is env_stop
	}

	if ( $type eq "hmmsearch" ){
	    #the fast parse way
	    # what in the heck is this?? apparently this is a fast way of splitting the data? Horrifying!
	    if( $_ =~ m/(.*?)\s+(.*?)\s+(\d+?)\s+(\d+?)\s+(.*?)\s+(\d+?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s(.*)/ ){
		$qid    = $1;
		$qlen   = $3;
		$tid    = $4;
		$tlen   = $6;
		$evalue = $13; #this is dom_ievalue
		$score  = $8;  #this is dom score
		$start  = $20; #this is env_start
		$stop   = $21; #this is env_stop
	    } else{
		warn( "couldn't parse results from $type file:\n$_ ");
		next;
	    }

	    #the old and slow way
	    if( 0 ){
		my @data = split(' ', $_);
		$qid  = $data[0];
		$qlen = $data[2];
		$tid  = $data[3];
		$tlen = $data[5];
		$evalue = $data[12]; #this is dom_ievalue
		$score  = $data[7];  #this is dom score
		$start  = $data[19]; #this is env_start
		$stop   = $data[20]; #this is env_stop
	    }
	}
	
	if( $type eq "blast" ){
	    if( $_ =~ m/^(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)$/ ){
		$qid    = $1;
		$tid    = $2;
		$start  = $9; 
		$stop   = $10; 
		$evalue = $11; 
		$score  = $12;
		$qlen   = $seqlens{$qid};	    
#		print "$qid\n";
#		print "$evalue\n";
#		print "A" . $score . "B\n";
	    } else{
		warn( "couldn't parse results from $type file:\n$_ ");
		next;
	    }
	    #old and slow way
	    if( 0 ){
		my @data = split( "\t", $_ );
		$qid    = $data[0];
		$tid    = $data[3];
		$evalue = $data[10]; #this is evalue
		$score  = $data[11];  #this is bit score
		$start  = $data[6];  #this is qstart
		$stop   = $data[7];  #this is qstop
		$qlen   = $seqlens{$qid};	    
		#won't calculate $tlen because it is messy - requires a DB lookup - and prolly unnecessary
	    }
	}

	if ($type eq "last") {
	    if($_ =~ m/^(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)$/ ){
		$score  = $1;
		$tid    = $2;
		$qid    = $7;
		$start  = $8;
		$stop   = $start + $9;
		$qlen   = $11;
		$evalue = 0; #hacky - no evalue reported for last, but want to use the same code below
	    } else {
		warn( "couldn't parse results from $type file:\n$_ ");
		next;
	    }
	}

	#calculate coverage from query perspective
	my $coverage;
	if ($stop > $start) {
	    $coverage = ($stop - $start + 1) / $qlen; # <-- coverage calc must include ****first base!*****, so add one apparently
	} elsif ($stop < $start) {
	    $coverage = ($start - $stop) / $qlen;
	} elsif ($stop == $start) {
	    $coverage = 0;
	}

	#does hit pass threshold?
	if( ( $evalue <= $t_evalue && $coverage >= $t_coverage ) ||
	    ( $type eq "last" && $score >= $t_score && $coverage >= $t_coverage ) ){
	    #is this the first hit for the query?
	    if ($hit_map->{$qid}->{"has_hit"} == 0) {
		#note that we use is_strict to differentiate top hit clustering from fuzzy clustering w/in hash
		$hit_map->{$qid}->{$is_strict}->{"target"}   = $tid;
		$hit_map->{$qid}->{$is_strict}->{"evalue"}   = $evalue;
		$hit_map->{$qid}->{$is_strict}->{"coverage"} = $coverage;
		$hit_map->{$qid}->{$is_strict}->{"score"}    = $score;
		$hit_map->{$qid}->{"has_hit"} = 1;
	    } elsif ($is_strict) {
		#only add if the current hit is better than the prior best hit. start with best evalue
#		print "evalue: $evalue\n";
#		print "coverage: $coverage\n";
#		print "score: $score\n";
#		print "stored: " . $hit_map->{$qid}->{$is_strict}->{"evalue"} . "\n";
		if( ( $evalue < $hit_map->{$qid}->{$is_strict}->{"evalue"} ||
		    ( $type eq "last" && $score > $hit_map->{$qid}->{$is_strict}->{"score"} ) ) ||
		    #if tie, use coverage to break
		    ( $evalue == $hit_map->{$qid}->{$is_strict}->{"evalue"} &&
		      $coverage > $hit_map->{$qid}->{$is_strict}->{"coverage"} ) 
		    ){
		    #add the hits here
		    $hit_map->{$qid}->{$is_strict}->{"target"}   = $tid;
		    $hit_map->{$qid}->{$is_strict}->{"evalue"}   = $evalue;
		    $hit_map->{$qid}->{$is_strict}->{"coverage"} = $coverage;
		    $hit_map->{$qid}->{$is_strict}->{"score"}    = $score;
		}
	    } else {
		#if stict clustering, we might have a pefect tie. Winner is the first one we find, so pass
		if($is_strict) {
		    warn "Alex: we should never be able to get here in the code";
		    next;
		}
		#else, add every threshold passing hit to the hash
		#since we aren't yet storing search results in db, we don't need to do this. turning off for speed and RAM
#		$hit_map{$qid}->{$is_strict}->{$tid}->{"evalue"}   = $evalue;
#		$hit_map{$qid}->{$is_strict}->{$tid}->{"coverage"} = $coverage;
#		$hit_map{$qid}->{$is_strict}->{$tid}->{"score"}    = $score;
	    }
	}
    }
    close RES;
    return $hit_map;
}

#produce a hashtab that maps sequence ids to sequence lengths
sub _get_sequence_lengths_from_file{
    my( $file ) = shift;    
    my %seqlens = ();
    open( FILE, "$file" ) || die "Can't open $file for read: $!\n";
    my($header, $sequence);
    while(<FILE>){
	chomp $_;
	if (eof) { # this is the last line I guess
	    $sequence .= $_; # append to the sequence
	    $seqlens{$header} = length($sequence);
	}

	if( $_ =~ m/\>(.*)/ ){
	    # Starts with a '>' so this is a header line!
	    if (defined($header)) { # <-- process the PREVIOUSLY READ sequence, which we have now completed
		$seqlens{$header} = length($sequence);
	    }
	    $header   = $1; # save the header apparently...
	    $sequence = ""; # sequence is just plain nothing at this point
	} else {
	    $sequence .= $_;
	}
    }
    return \%seqlens;
}


#called by classify_reads
#initialize a lookup hash by pulling seq_ids from a fasta file and dumping them into hash keys
sub initialize_hit_map{
    my $seq_file = shift;
#    my $seqs     = Bio::SeqIO->new( -file => $seq_file, -format => 'fasta' );
    my $hit_map  = {}; #a hashref
#    while( my $seq = $seqs->next_seq() ){
#	my $id = $seq->display_id();
#	$hit_map{$id}->{"has_hit"} = 0;
#    }
    open( SEQS, $seq_file ) || die "can't open $seq_file in initialize_hit_map\n";
    while( <SEQS> ){
	next unless ( $_ =~ m/^\>/ );
	chomp $_;
	$_ =~ s/^\>//;
	$hit_map->{$_}->{"has_hit"} = 0;
	
    }
    close SEQS;
    return $hit_map;
}

#this is a depricated function given upstream changes in the workflow. use classify_reads instead
sub classify_reads_depricated{
  my $self       = shift;
  my $sample_id  = shift;
  my $hscresults = shift;
  my $evalue     = shift;
  my $coverage   = shift;
  my $ffdb       = $self->get_ffdb();
  my $project_id = $self->get_project_id();
  my $results    = Bio::SearchIO->new( -file => $hscresults, -format => 'hmmer3' );
  my $count      = 0;
  while( my $result = $results->next_result ){
      $count++;
      my $qorf = $result->query_name();
      my $qacc = $result->query_accession();
      my $qdes = $result->query_description();
      my $qlen = $result->query_length();
      my $nhit = $result->num_hits();
      if( $nhit > 0 ){
	  while( my $hit = $result->next_hit ){
	      my $hmm    = $hit->name();
	      my $score  = $hit->raw_score();
	      my $signif = $hit->significance();
	      while( my $hsp = $hit->next_hsp ){
		  my $hsplen = $hsp->length('total');
		  my $hqlen  = $hsp->length('query');
		  my $hhlen  = $hsp->length('hit');
		  #print join ("\t", $qorf, $qacc, $qdes, $qlen, $nhit, $hmm, $score, $signif, $hqlen, "\n");
		  #if hit passes thresholds, push orf into the family
		  if( $signif <= $evalue && 
		      ( $hqlen / $qlen)  >= $coverage ){
		      my $orf = $self->MRC::DB::get_orf_from_alt_id( $qorf, $sample_id );
		      my $orf_id = $orf->orf_id();
		      $self->MRC::DB::insert_family_member_orf( $orf_id, $hmm );
		  }
	      }
	  }
      }
  }
  warn "Processed $count search results from $hscresults\n";
  #return $self;
}

sub build_search_db{
    my $self        = shift;
    my $db_name     = shift; #name of db to use, if build, new db will be named this. check for dups
    my $split_size  = shift; #integer - how many hmms per split?
    my $force       = shift; #0/1 - force overwrite of old DB during compression.
    my $type        = shift; #blast/hmm
    my $reps_only   = shift; #0/1 - should we only use representative sequences in our sequence DB
    my $nr_db       = shift; #0/1 - should we use a non-redundant version of the DB (sequence DB only)

    my $ffdb        = $self->get_ffdb();
    my $ref_ffdb    = $self->get_ref_ffdb();

    #where is the hmmdb going to go? each hmmdb has its own dir
    my $raw_db_path = undef;
    my $length      = 0;
    if ($type eq "hmm")   { $raw_db_path = $self->MRC::DB::get_hmmdb_path(); }
    if ($type eq "blast") { $raw_db_path = $self->MRC::DB::get_blastdb_path(); }

    warn "Building $type DB $db_name, placing $split_size per split\n";

    #Have you built this DB already?

    if( -d $raw_db_path && !($force) ){
	warn "You've already built a <$type> database with the name <$db_name> at <$raw_db_path>. Please delete or overwrite by using the --force option.\n";
	exit(0);
    }

    #create the HMMdb dir that will hold our split hmmdbs
    $self->MRC::DB::build_db_ffdb( $raw_db_path );
    #update the path to make it easier to build the split hmmdbs (e.g., points to an incomplete file name)
    #save the raw path for the database_length file when using blast

    my $db_path_with_name     = "$raw_db_path/$db_name";
    #constrain analysis to a set of families of interest
    my @families   = sort( @{ $self->get_family_subset() });
    my $n_fams     = @families;
    my $count      = 0;
    my @split      = (); #array of family HMMs/sequences (compressed)
    my $n_proc     = 0;
    my @fcis       = @{ $self->get_fcis() };
    foreach my $family( @families ){
	#find the HMM/sequences associated with the family (compressed)
	my $family_db_file = undef;

	if ($type eq "hmm") {
	    foreach my $fci (@fcis) {
		my $path = "${ref_ffdb}/fci_${fci}/HMMs/${family}.hmm.gz";
		if( -e $path ) { $family_db_file = $path; } # assign the family_db_file to this path ONLY IF IT EXISTS!
	    }
	    if (!defined( $family_db_file)) {
		die("Can't find the HMM corresponding to family $family when using the following fci:\n" . join( "\t", @fcis, "\n" ) . " ");
	    }

	} elsif( $type eq "blast" ) {
	    foreach my $fci( @fcis ){
		if (0 == $fci) {
		    $fci = 1; # <-- short term hack for the merged fci blast directory for 0 and 1
		}
		my $path = "$ref_ffdb/fci_${fci}/seqs/${family}.fa.gz";
		if( -e $path ){
		    $family_db_file = $path; # <-- save the path, if it exists
		    
		    if ($reps_only) {
			#do we only want rep sequences from big families?
			#first see if there is a reps file for the family
			my $reps_list_path = "${ref_ffdb}/reps/fci_${fci}/list/${family}.mcl";
			#if so, see if we need to build the seq file
			if( -e $reps_list_path ){
			    #we add the .gz extension in the gzip command inside grab_seqs_from_lookup_list
			    my $reps_seq_path = "$ref_ffdb/reps/fci_${fci}/seqs/${family}.fa";
			    if(! -e "${reps_seq_path}.gz" ){
				print "Building reps sequence file for $family\n";
				_grab_seqs_from_lookup_list( $reps_list_path, $family_db_file, $reps_seq_path );
				if(! -e "${reps_seq_path}.gz" ) {
				    ## if it STILL doesn't exist
				    warn( "Error grabbing representative sequences from $reps_list_path. Trying to place in $reps_seq_path.\n" );
				    exit(0);
				}
			    }
			    $family_db_file = "${reps_seq_path}.gz"; #add the .gz path because of the compression we use in grab_seqs_from_loookup_list
			}
		    }
		    #because of the fci hack, if we made it here, we don't want to rerun the above
#		    last;
		}
	    }
	    if(!defined($family_db_file) ){
		die( "Can't find the BLAST database corresponding to family $family when using the following fci:\n" . join( "\t", @fcis, "\n" )  . " ");
	    }
#	    $family_db_file =  $ffdb . "/BLASTs/" . $family . ".fa.gz";
	    $length += $self->MRC::Run::get_sequence_length_from_file($family_db_file);
	}
	
	push( @split, $family_db_file );
	$count++;
	#if we've hit our split size, process the split
	if($count >= $split_size || $family == $families[-1]) {
	    $n_proc++; 	    #build the DB
	    my $split_db_path;
	    if( $type eq "hmm" ){
		$split_db_path = MRC::Run::cat_db_split($db_path_with_name, $n_proc, $ffdb, ".hmm", \@split, 0); # note: the $nr_db parameter for hmm is ALWAYS zero --- it makes no sense to build a NR HMM DB
	    } elsif( $type eq "blast" ){
		$split_db_path = MRC::Run::cat_db_split($db_path_with_name, $n_proc, $ffdb, ".fa", \@split, $nr_db);
	    } else { die "invalid type: <$type>"; }
	    gzip_file($split_db_path); # We want DBs to be gzipped.
	    unlink($split_db_path); # So we save the gzipped copy, and DELETE the uncompressed copy
	    @split = (); # clear this out
	    $count = 0; # clear this too
	}
    }

    if($type eq "blast"){
	open( LEN, "> ${raw_db_path}/database_length.txt" ) || die "Can't open ${raw_db_path}/database_length.txt for write: $!\n";
	print LEN $length;
	close LEN;
    }

    print STDERR "Build Search DB: $type DB was successfully built and compressed.\n";
}

sub cat_db_split{
    my ($db_path, $n_proc, $ffdb, $suffix, $ra_families_array_ptr, $nr_db) = @_;
    my @families     = @{$ra_families_array_ptr}; # ra_families is a POINTER TO AN ARRAY
    my $split_db_path = "${db_path}_${n_proc}${suffix}";
    my $fh;
    open( $fh, ">> $split_db_path" ) || die "Can't open $split_db_path for write: $!\n";
    foreach my $family( @families ){
	#do we want a nonredundant version of the DB? 
	if (defined($nr_db) && $nr_db) {
	    my $tmp = _build_nr_seq_db( $family ); #make a temp file for the nr 
	    File::Cat::cat( $tmp, $fh ); # From the docs: "Copies data from EXPR to FILEHANDLE, or returns false if an error occurred. EXPR can be either an open readable filehandle or a filename to use as input."
	    unlink($tmp); # delete the $tmp file
	} else{
	    gunzip $family => $fh;
	}
    }
    close $fh;
    return $split_db_path;
}

#Note heuristic here: builiding an NR version of each family_db rather than across the complete DB. 
#Assumes identical sequences are in same family, decreases RAM requirement. First copy of seq is retained
sub _build_nr_seq_db{
    my $family    = shift;
    my $family_nr = $family . "_nr";
    my $seqin  = Bio::SeqIO->new( -file => "zcat $family |", -format => 'fasta' );
    my $seqout = Bio::SeqIO->new( -file => ">$family_nr", -format => 'fasta' );
    my $dict   = {};
    while(my $seq = $seqin->next_seq ) {
	my $id       = $seq->display_id();
	my $sequence = $seq->seq();
	#if we haven't seen this seq before, print it out
	if( !defined( $dict->{$sequence} ) ){
	    $seqout->write_seq( $seq );
	    $dict->{$sequence}++;
	} else {
	    #print "Removing duplication sequence $id\n";
	}
    }
    return $family_nr;
}


sub _grab_seqs_from_lookup_list{
    my $seq_id_list = shift; #list of sequence ids to retain
    my $seq_file    = shift; #compressed sequence file
    my $out_seqs    = shift; #compressed retained sequences

    my $lookup      = {}; # apparently this is a hash pointer? or list or something?
    print "Selecting reps from $seq_file, using $seq_id_list. Results in $out_seqs\n";
    #build lookup hash
    open( LOOK, $seq_id_list ) || die "Can't open $seq_id_list for read: $!\n";
    while(<LOOK>){
	chomp $_;
	$lookup->{$_}++;
    }
    close LOOK;
    my $seqs_in  = Bio::SeqIO->new( -file => "zcat $seq_file |", -format => 'fasta' );
    my $seqs_out = Bio::SeqIO->new( -file => ">$out_seqs", -format => 'fasta' );
    while(my $seq = $seqs_in->next_seq()){
	my $id = $seq->display_id();
	if( defined( $lookup->{$id} ) ){
	    $seqs_out->write_seq( $seq );
	}
    }
    gzip_file( $out_seqs );    
    unlink( $out_seqs );
}

#calculates total amount of sequence in a file (looks like actually in a DIRECTORY rather than a file)
sub calculate_blast_db_length{
    my($self) = @_;
    my $length  = 0;
    my $db_name = $self->get_blastdb_name();
    my $db_path = $self->get_ffdb() . "/$BLASTDB_DIR/$db_name";
    opendir( DIR, $db_path ) || die "Can't opendir $db_path for read: $! ";
    my @files = readdir(DIR);
    closedir DIR;

    my $numFilesRead = 0;
    foreach my $file (@files) {
	next unless( $file =~ m/\.fa/ ); # ONLY include files ending in .fa
	my $lengthThisFileOnly = $self->MRC::Run::get_sequence_length_from_file("$db_path/$file");
	$length += $lengthThisFileOnly;
	$numFilesRead++;
	MRC::notify("[$numFilesRead/" . scalar(@files) . "]: Got a sequence length of $lengthThisFileOnly from <$file>. Total length: $length");
    }
    return $length;
}

sub get_sequence_length_from_file{
    my($self, $file) = @_;
    my $READSTRING = ($file =~ m/\.gz/ ) ? "zmore $file | " : "$file"; # allow transparent reading of gzipped files via 'zmore'
    open(FILE, "$READSTRING") || die "Can't open <$file> for reading: $! ";
    my $length = 0;
    while(<FILE>){
	next if ($_ =~ m/^\>/ ); # skip lines that start with a '>'
	chomp $_; # remove the newline
	$length += length($_);
    }
    close FILE;
    return $length; # return the sequence length
}

sub gzip_file {
    my $file = shift;
    IO::Compress::Gzip::gzip $file => "${file}.gz" or die "gzip failed: $GzipError ";
}

# Code below is both unused AND refers to non-existent code in DB (as of Feb 2013).
#state how many spilts you want, will determine the correct number of hm
# sub build_hmm_db_by_n_splits{
#     my $self     = shift;
#     my $hmmdb    = shift; #name of hmmdb to use, if build, new hmmdb will be named this. check for dups
#     my $n_splits = shift; #integer - how many hmmdb splits should we produce?
#     my $force    = shift; #0/1 - force overwrite of old HMMdbs during compression.
#     my $ffdb     = $self->get_ffdb();
#     #where is the hmmdb going to go? each hmmdb has its own dir
#     my $hmmdb_path = "$ffdb/$HMMDB_DIR/$hmmdb";

#     warn "Building HMMdb $hmmdb, splitting into $n_splits parts.";
#     #Have you built this HMMdb already?
#     if (-d $hmmdb_path && !$force) {
# 	die "You've already built an HMMdb with the name $hmmdb at $hmmdb_path. Please delete or overwrite by using the --force option.";
#     }
#     #create the HMMdb dir that will hold our split hmmdbs
#     $self->MRC::DB::build_hmmdb_ffdb( $hmmdb_path );
#     #update the path to make it easier to build the split hmmdbs (e.g., points to an incomplete file name)


#     my $hmmdb_UPDATED_path = "$hmmdb_path/$hmmdb"; # why did this get updated to have $hmmdb twice in it??? This was in the original code, but I don't know what
#     warn "Alex is suspicious of the update from $hmmdb_path to $hmmdb_UPDATED_path above. I wonder if that line is an error.";

#     #constrain analysis to a set of families of interest
#     my @families   = sort( @{ $self->get_subset_famids() });
#     my $n_fams     = @families;
#     my $split_size = $n_fams / $n_splits;
#     my $count      = 0;
#     my @split      = (); #array of family HMMs (compressed)
#     my $n_proc     = 0;
#     my $ref_ffdb   = $self->get_ref_ffdb();
#     my @fcis       = @{ $self->get_fcis() };
#     foreach my $family( @families ){
# 	#find the HMM associated with the family (compressed)
# 	my $family_hmm;
# 	foreach my $fci( @fcis ){
# 	    my $path = "${ref_ffdb}/fci_${fci}/HMMs/${family}.hmm.gz";
# 	    if( -e $path ){
# 		$family_hmm = $path;
# 	    }
# 	}
# 	if( !defined( $family_hmm ) ){
# 	    die( "Can't find the HMM corresponding to family $family when using the following fci:\n" . join( "\t", @fcis, "\n" ) . " ");
# 	}
# 	push( @split, $family_hmm );
# 	#if we've hit our split size, process the split
# 	if (scalar(@split) >= $split_size || $family == $families[-1] ){ #build the HMMdb
# 	    $n_proc++;
# 	    my $nrdb_local_always_false = 0; # apparently this is alaways false for this call
# 	    my $split_db_path = MRC::Run::cat_db_split( $hmmdb_UPDATED_path, $n_proc, $ffdb, ".hmm", \@split, $nrdb_local_always_false);
# 	    compress_hmmdb( $split_db_path, $force ); #compress the HMMdb, a wrapper for hmmpress
# 	    @split = (); # clear it out...
# 	}
#     }
#     warn "HMMdb successfully built and compressed.\n";
#     #return $self;
# }

sub compress_hmmdb{
    my ($file, $force) = @_;
    my @args = ($force) ? ("-f", "$file") : ("$file"); # if we have FORCE on, then add "-f" to the options for hmmpress
    my $results  = IPC::System::Simple::capture( "hmmpress " . "@args" );
    (0 == $EXITVAL) or die("Error translating sequences in $file: $results ");
    return $results;
}

#copy a project's ffdb over to the remote server
sub load_project_remote{
    my ($self) = @_;
    my $project_dir_local = $self->get_ffdb() . "/projects/" . $self->get_project_id();
    my $remote_dir  = $self->get_remote_connection() . ":" . $self->get_remote_ffdb() . "/projects/" . $self->get_project_id();
    warn("Pushing $project_dir_local to the remote (" . $self->get_remote_server() . ") server's ffdb location in <$remote_dir>\n");
    my $results = MRC::Run::transfer_directory($project_dir_local, $remote_dir);
    return $results;
}

#the qsub -sync y option keeps the connection open. lower chance of a connection failure due to a ping flood, but if connection between
#local and remote tends to drop, this may not be foolproof
sub translate_reads_remote{
    my ($self, $waitTimeInSeconds, $logsdir, $split_orfs) = @_;
    # "split_orfs" argument means "split orfs on stop?" Should be 1 or 0.

    #push translation scripts to remote server
    my $connection = $self->get_remote_connection();
    my $remote_script_dir = $self->get_remote_script_dir();

    my $remote_handler  = $self->get_scripts_dir() . "/remote/run_transeq_handler.pl";
    my $remote_script   = $self->get_scripts_dir() . "/remote/run_transeq_array.sh"; # what is going on here
    my $transeqPerlRemote = "$remote_script_dir/run_transeq_handler.pl";
    
    MRC::Run::transfer_file_into_directory($remote_handler, "$connection:$remote_script_dir/"); # transfer the script into the remote directory
    MRC::Run::transfer_file_into_directory($remote_script,  "$connection:$remote_script_dir/"); # transfer the script into the remote directory
    foreach my $sample_id( @{$self->get_sample_ids()} ) {
	my $remote_input_dir    = $self->get_remote_ffdb() . "/projects/" . $self->get_project_id() . "/$sample_id/raw";
	my $remote_output_dir   = $self->get_remote_ffdb() . "/projects/" . $self->get_project_id() . "/$sample_id/orfs";

	MRC::notify("Translating reads...");
	if ($split_orfs) {
	    # Split the ORFs!
	    my $local_unsplit_dir  =        $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/$sample_id/unsplit_orfs"; # This is where the files will be tranferred BACK to. Should NOT end in a slash!
	    my $remote_unsplit_dir = $self->get_remote_ffdb() . "/projects/" . $self->get_project_id() . "/$sample_id/unsplit_orfs"; # Should NOT end in a slash!
	    my $tempStdoutLocationOnRemoteMachine = "$remote_unsplit_dir/tmp.out"; # used to be "~/tmp.out"
	    my $remote_cmd = "\'perl ${transeqPerlRemote} " . " -i $remote_input_dir" . " -o $remote_output_dir" . " -w $waitTimeInSeconds" . " -l $logsdir" . " -s $remote_script_dir" . " -u $remote_unsplit_dir" . " > ${tempStdoutLocationOnRemoteMachine} \'";
	    execute_ssh_cmd( $connection, $remote_cmd );
	    MRC::notify("Translation complete, Transferring split and raw translated orfs\n");
	    MRC::Run::transfer_directory("${connection}:$remote_unsplit_dir", $local_unsplit_dir); #the unsplit orfs
	} else{ 
	    my $remote_cmd_no_unsplit = "\'perl ${transeqPerlRemote} " . " -i $remote_input_dir" . " -o $remote_output_dir" . " -w $waitTimeInSeconds" . " -l $logsdir" . " -s $remote_script_dir" . "\'";
	    execute_ssh_cmd($connection, $remote_cmd_no_unsplit);
	}
	MRC::notify("Translation complete, Transferring ORFs\n");
	my $localOrfDir  = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/${sample_id}/orfs";
	MRC::Run::transfer_directory("$connection:$remote_output_dir", $localOrfDir); # This happens in both cases, whether or not the orfs are split!
    }
    MRC::notify("All reads were translated on the remote server and locally acquired.");
}

#if you'd rather routinely ping the remote server to check for job completion. not default
sub translate_reads_remote_ping{
    my ($self, $waitTimeInSeconds) = @_; # waitTimeInSeconds is the amount of time between queue checks

    my $connection  = $self->get_remote_connection();
    my $pid         = $self->get_project_id();
    my $remote_ffdb = $self->get_remote_ffdb();
    my $local_ffdb  = $self->get_ffdb();

    my %jobs = ();
    foreach my $sample_id( @{$self->get_sample_ids()} ){
	my $remote_input  = "$remote_ffdb/projects/$pid/$sample_id/raw.fa";
	my $remote_output = "$remote_ffdb/projects/$pid/$sample_id/orfs.fa";
	my $transeqShRemoteLocation = $self->get_remote_script_dir() . "/run_transeq.sh";
	my $results = execute_ssh_cmd( $connection, "\'qsub $transeqShRemoteLocation $remote_input $remote_output\'");
	if ($results =~ m/^Your job (\d+) / ){
	    my $job_id = $1;
	    $jobs{$job_id} = $sample_id;
	} else{
	    die("Remote server did not return a properly formatted job id! The previous SSH command got the results <$results> instead!");
	}
    }
    #check the jobs until they are all complete
    my @job_ids = keys(%jobs);
    my $time = $self->MRC::Run::remote_job_listener( \@job_ids, $waitTimeInSeconds );
    MRC::notify( "Reads were translated in approximately $time seconds on remote server");
    MRC::notify("Pulling translated reads from remote server"); # <-- consider that a completed job doesn't mean a *successful* run!
    foreach my $job( keys( %jobs ) ){
	my $sample_id = $jobs{$job};
	my $results = MRC::Run::transfer_file("$connection:$remote_ffdb/projects/$pid/$sample_id/orfs.fa", "$local_ffdb/projects/$pid/$sample_id/orfs.fa"); # retrieve the file from remote->local
    }
}

sub remote_job_listener{
    # Note that this function is a nearly exact copy of "local_job_listener"
    my ($self, $jobsArrayRef, $waitTimeInSeconds) = @_;
    ($waitTimeInSeconds >= 1) or die "Programming error: You can't set waitTimeInSeconds to less than 1 (but it was set to $waitTimeInSeconds)---we don't want to flood the machine with constant system requests.";
    my %statusHash             = ();
    my $startTimeInSeconds = time();
    while (scalar(keys(%statusHash)) != scalar(@{$jobsArrayRef})) { # keep checking until EVERY SINGLE job has a finished status
	#call qstat and grab the output
	my $results = execute_ssh_cmd( $self->get_remote_connection(), "\'qstat\'");
	#see if any of the jobs are complete. pass on those we've already finished
	foreach my $jobid( @{ $jobsArrayRef } ){
	    next if( exists( $statusHash{$jobid} ) );
	    if( $results !~ m/$jobid/ ){
		$statusHash{$jobid}++;
	    }
	}
	sleep( $waitTimeInSeconds );
    }
    return (time() - $startTimeInSeconds); # return amount of wall-clock time this took
}

sub local_job_listener{
    # Note that this function is a nearly exact copy of "remote_job_listener"
    my ($self, $jobsArrayRef, $waitTimeInSeconds) = @_;
    ($waitTimeInSeconds >= 1) or die "Programming error: You can't set waitTimeInSeconds to less than 1 (but it was set to $waitTimeInSeconds)---we don't want to flood the machine with constant requests for 'ps'.";
    my $startTimeInSeconds = time();
    my %statusHash   = ();
    while (scalar(keys(%statusHash)) != scalar(@{$jobsArrayRef})) { # keep checking until EVERY SINGLE job has a finished status
	my $results = IPC::System::Simple::capture("ps"); #call ps and grab the output
	($EXITVAL == 0) or die("Error running ps! ");
	foreach my $jobid(@{ $jobsArrayRef} ) { #see if any of the jobs are complete. pass on those we've already finished
	    next if (exists( $statusHash{$jobid}) ); # Skip... for some reason
	    if ($results !~ m/^$jobid /) {
		$statusHash{$jobid}++;
	    }
	}
	sleep( $waitTimeInSeconds ); # 'sleep' here so as not to flood the machine with requests for "ps"
    }
    return (time() - $startTimeInSeconds); # return amount of wall-clock time this took
}

sub remote_transfer_search_db{
    my ($self, $db_name, $type) = @_;
    my $DATABASE_PARENT_DIR = undef;
    if ($type eq "hmm") { $DATABASE_PARENT_DIR = $HMMDB_DIR; }
    if ($type eq "blast") { $DATABASE_PARENT_DIR = $BLASTDB_DIR; }
    (defined($DATABASE_PARENT_DIR)) or die "Programming error: the 'type' in remote_transfer_search_db must be either \"hmm\" or \"blast\". Instead, it was: \"$type\". Fix this in the code!\n";
    my $db_dir     = $self->get_ffdb() . "/${DATABASE_PARENT_DIR}/${db_name}";
    my $remote_dir = $self->get_remote_connection() . ":" . $self->get_remote_ffdb() . "/$DATABASE_PARENT_DIR/$db_name";
    return(MRC::Run::transfer_directory($db_dir, $remote_dir));
}

sub remote_transfer_batch { # transfers HMMbatches, not actually a general purpose "batch transfer"
    my ($self, $hmmdb_name) = @_;
    my $hmmdb_dir   = $self->get_ffdb() . "/HMMbatches/$hmmdb_name";
    my $remote_dir  = $self->get_remote_connection() . ":" . $self->get_remote_ffdb() . "/HMMbatches/$hmmdb_name";
    return(MRC::Run::transfer_directory($hmmdb_dir, $remote_dir));
}

sub gunzip_file_remote {
    my ($self, $remote_file) = @_;
    my $remote_cmd = "gunzip -f $remote_file";
    return(execute_ssh_cmd( $self->get_remote_connection(), $remote_cmd ));
}

sub gunzip_remote_dbs{
    my( $self, $db_name, $type ) = @_;    
    my $ffdb   = $self->get_ffdb();
    my $db_dir = undef;
    if ($type eq "hmm")      { $db_dir = "$ffdb/$HMMDB_DIR/$db_name"; }
    elsif ($type eq "blast") { $db_dir = "$ffdb/$BLASTDB_DIR/$db_name"; }
    else                     { die "invalid or unrecognized type."; }

    opendir( DIR, $db_dir ) || die "Can't opendir $db_dir for read: $!";
    my @files = readdir( DIR );
    closedir DIR;
    foreach my $file( @files ){
	next unless( $file =~ m/\.gz/ ); # Skip any files that are NOT .gz files
	my $remote_db_file;
	if( $type eq "hmm" ){   $remote_db_file = $self->get_remote_ffdb() . "/$HMMDB_DIR/$db_name/$file"; }
	if( $type eq "blast" ){ $remote_db_file = $self->get_remote_ffdb() . "/$BLASTDB_DIR/$db_name/$file"; }
	$self->MRC::Run::gunzip_file_remote($remote_db_file);
    }
}

sub format_remote_blast_dbs{
    my( $self, $remote_script_path ) = @_;
    my $ffdb       = $self->get_ffdb();
    my $remote_database_dir   = $self->get_remote_ffdb() . "/$BLASTDB_DIR/" . $self->get_blastdb_name();
    my $results    = execute_ssh_cmd($self->get_remote_connection(), "qsub -sync y $remote_script_path $remote_database_dir");
}

sub run_search_remote{
    my ($self, $sample_id, $type, $waitTimeInSeconds, $verbose) = @_;
    my ( $remote_script_path, $search_handler_log, $db_name, $remote_db_dir, $remote_search_res_dir);

    my $remote_query_dir      = $self->get_remote_sample_path($sample_id) . "/orfs"; # This is the same for ALL entries!
    
    if( $type eq "blast" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/blast_handler";
	$remote_script_path    = $self->get_remote_blast_script();
	$db_name               = $self->get_blastdb_name();
	$remote_db_dir         = $self->get_remote_ffdb() . "/$BLASTDB_DIR/$db_name/";
	$remote_search_res_dir = $self->get_remote_sample_path($sample_id) .  "/search_results/blast/";
    }
    if( $type eq "last" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/last_handler";
	$remote_script_path    = $self->get_remote_last_script();
	$db_name               = $self->get_blastdb_name();
	$remote_db_dir         = $self->get_remote_ffdb() . "/$BLASTDB_DIR/$db_name";
	$remote_search_res_dir = $self->get_remote_sample_path($sample_id) .  "/search_results/last";
    }
    if( $type eq "hmmsearch" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/hmmsearch_handler";
	$remote_script_path    = $self->get_remote_hmmsearch_script();
	$db_name               = $self->get_hmmdb_name();
	$remote_db_dir         = $self->get_remote_ffdb() . "/$HMMDB_DIR/$db_name";
	$remote_search_res_dir = $self->get_remote_sample_path($sample_id) .  "/search_results/hmmsearch";
    }
    if( $type eq "hmmscan" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/hmmscan_handler";
	$remote_script_path    = $self->get_remote_hmmscan_script();
	$db_name               = $self->get_hmmdb_name();
	$remote_db_dir         = $self->get_remote_ffdb() . "/$HMMDB_DIR/$db_name";
	$remote_search_res_dir = $self->get_remote_sample_path($sample_id) .  "/search_results/hmmscan";
    }
    
    my $perlScriptRemoteLoc = $self->get_remote_script_dir() . "/run_remote_search_handler.pl";
    my $remote_cmd  = "\'perl $perlScriptRemoteLoc -h $remote_db_dir -o $remote_search_res_dir -i $remote_query_dir -n $db_name -s $remote_script_path -w $waitTimeInSeconds > ${search_handler_log}.out 2> $search_handler_log.err \'";
    my $results     = execute_ssh_cmd( $self->get_remote_connection(), $remote_cmd, $verbose );
    return $results;
}

sub get_remote_search_results {
    my($self, $sample_id, $type) = @_;
    ($type eq "blast" or $type eq "last" or $type eq "hmmsearch" or $type eq "hmmscan") or die "Invalid type passed into get_remote_search_results! The invalid type was: \"$type\".";
    my $remote_search_res_dir = $self->get_remote_sample_path($sample_id) .  "/search_results/$type";
    my $local_search_res_dir  = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/$sample_id/search_results/$type";
    # Note that every sequence split has its *own* output dir, in order to cut back on the number of files per directory.
    my $in_orf_dir = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/$sample_id/orfs"; # <-- Always the same input directory (orfs) no matter what the $type is.
    foreach my $in_orfs( @{ $self->MRC::DB::get_split_sequence_paths($in_orf_dir, 0) } ) {
	my $remoteStr = $self->get_remote_connection() . ':' . "$remote_search_res_dir/$in_orfs";
	MRC::Run::transfer_directory($remoteStr, $local_search_res_dir);
    }
}

# Below: Note that this may not yet be a perfect replacement for the ping version below. The problem with this approach is that it keeps an ssh connection alive
#for every job, which can flood the remote server. So this version is now defuct. Use run_hmmscan_remote instead
# sub run_hmmscan_remote_defunct{
#     my( $self, $in_seqs_dir, $inseq_file, $hmmdb, $output, $outstem, $type, $closed, $second_output ) = @_; #type is 0 for default and 1 for --max, 2 is to run both at the same time, requires $second_output to be set
#     if( !defined( $type ) ){
# 	$type = 0;
#     }
#     my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
#     my $remote_cmd;
#     if( defined( $second_output ) ){
# 	$remote_cmd = "\'qsub -sync y " . $self->get_remote_script_dir() . "run_hmmscan.sh "  . $in_seqs_dir . " " .$inseq_file . " " . $hmmdb . " " . $output . " " . $outstem . " " . $type . " " . $second_output . "\'";
#     }
#     else{
# 	#set closed = 1 if you don't want the connection to remote server to remain open. This is important if you are worried about flooding the connection pool.
# 	if( defined( $closed ) && $closed == 1 ){
# 	    $remote_cmd = "\'qsub " . $self->get_remote_script_dir() . "run_hmmscan.sh " .  $in_seqs_dir . " " . $inseq_file . " " . $hmmdb . " " . $output . " " . $outstem . " " . $type . "\'";
# 	}
# 	else{
# 	    $remote_cmd = "\'qsub -sync y " . $self->get_remote_script_dir() . "run_hmmscan.sh " .  $in_seqs_dir . " " . $inseq_file . " " . $hmmdb . " " . $output . " " . $outstem . " " . $type . "\'";
# 	}
#     }
#     my $results = execute_ssh_cmd( $connection, $remote_cmd );
#     return $results;
# }

#not used in mrc_handler.pl
sub run_blast_remote{
    my ( $self, $inseq, $db, $output, $closed ) = @_;
    my $remoteScriptDir = $self->get_remote_script_dir();

    my $SINGLE_QUOTE = "\'";
    my $sync_parameter = (!defined($closed) || !$closed) ? ' -sync y ' : ''; # if "closed" is false or unspecified, then add "-sync y" to the parameter list
    my $remote_cmd = $SINGLE_QUOTE . "qsub $sync_parameter $remoteScriptDir/run_blast.sh  $inseq  $db  $output " . $SINGLE_QUOTE;
    return(execute_ssh_cmd($self->get_remote_connection(), $remote_cmd));
}

sub transfer_hmmsearch_remote_results{
    my ($self, $hmmdb_name) = @_;
    my $ffdb = $self->get_ffdb();
    my $local_file = "$ffdb/hmmsearch/$hmmdb_name";
    my $remote_file  = $self->get_remote_connection() . ":" . $self->get_remote_ffdb() . "/hmmsearch/$hmmdb_name";
    return(MRC::Run::transfer_file($remote_file, $local_file));
}

sub remove_remote_file{
    my($self, $file) = @_;
    return(execute_ssh_cmd($self->get_remote_connection(), "/bin/rm $file"));
}

sub remove_hmmsearch_remote_results{
    my ($self, $search_outfile) = @_;
    my $remote_file = $self->get_remote_ffdb() . "/hmmsearch/$search_outfile";
    return(execute_ssh_cmd($self->get_remote_connection(), "/bin/rm $remote_file"));
}

sub run_hmmscan_remote_ping{
    my ($self, $hmmdb_name, $waitTimeInSeconds) = @_;  # waitTimeInSeconds is amount of time between queue checks
    my @sample_ids = @{$self->get_sample_ids()};
    my %jobs = ();
    my %hmmdbs =  %{ $self->MRC::DB::get_hmmdbs( $hmmdb_name, 1 ) };     #use get_hmmdbs with the 1 flag to indicate remote server file paths
    foreach my $sample_id( @sample_ids ){ #search each sample against each hmmdb split
	my $projID = $self->get_project_id();
	my $ff = $self->get_remote_ffdb();
	my $thisSampleDir = "$ff/projects/${projID}/${sample_id}";
	my $remote_input = "${thisSampleDir}/orfs.fa";
	foreach my $hmmdb( keys( %hmmdbs ) ){
	    my $remote_hmmdb_path = $hmmdbs{$hmmdb};
	    my $remote_output = "${thisSampleDir}/search_results/${sample_id}_v_${hmmdb}.hsc";

	    my $runHmmScanShRemoteLocation =  $self->get_remote_script_dir() . "/run_hmmscan.sh";
	    my $remote_cmd = "\'qsub $runHmmScanShRemoteLocation -o $remote_output $remote_hmmdb_path $remote_input \'";
	    my $results = execute_ssh_cmd( $self->get_remote_connection(), $remote_cmd );
	    if ($results =~ m/^Your job (\d+) /) {
		my $job_id = $1;
		$jobs{$job_id}{$sample_id}{$hmmdb} = $remote_output;
	    } else {
		die("Remote server did not return a properly formatted job id when running $remote_cmd. Got $results instead!. Exiting.");
	    }

	    MRC::notify("Sleeping for 10 seconds here to avoid flooding the remote server...");
	    sleep(10); # sleep for ten seconds -- add a sleep so that we don't flood the remote server
	}
    }
    #check the jobs until they are all complete
    my @job_ids = keys( %jobs );
    my $time = $self->MRC::Run::remote_job_listener(\@job_ids, $waitTimeInSeconds);
    MRC::notify("Hmmscan was conducted: translation finished (hopefully it was successful) on " . $self->get_remote_server() . " in approximately $time seconds.");
    #consider that a completed job doesn't mean a successful run!
    MRC::notify("Pulling hmmscan reads from remote server\n");
    foreach my $job( keys( %jobs ) ){
	foreach my $sample_id( @sample_ids ){
	    foreach my $hmmdb( keys( %hmmdbs ) ){
		next unless exists( $jobs{$job}{$sample_id}{$hmmdb} );
		warn( join("\t", $job, $sample_id, $hmmdb) );
		my $remote_src = $self->get_remote_connection() . ":" . $jobs{$job}{$sample_id}{$hmmdb};
		my $local_dest = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/${sample_id}/search_results/${sample_id}_v_${hmmdb}.hsc";
		my $results = MRC::Run::transfer_file( $remote_src, $local_dest);
	    }
	}
    }    
}

sub get_family_size_by_id{
    my $self  = shift;
    my $famid = shift;
    my $refonly = shift; #only count reference family members?
    my $fam_mems = $self->MRC::DB::get_family_members_by_famid( $famid );
    my $size = 0;
    if( $refonly ){
	while( my $member = $fam_mems->next() ){
	    if( $member->gene_oid() ){
		$size++;
	    }
	}
    }
    else{
	$size = $fam_mems->count();
    }
    return $size;
}

sub build_PCA_data_frame{
    my $self     = shift;
    my $class_id = shift;
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/PCA_data_frame_${class_id}.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in build_classification_map: $! ";
    print OUT join("\t", "OPF", @{ $self->get_sample_ids() }, "\n" );
    my %opfs        = ();
    my %opf_map     = (); #$sample->$opf->n_hits;  
    my %sample_cnts = (); #sample_cnts{$sample_id} = total_hits_in_sample
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my $family_rs  = $self->MRC::DB::get_families_with_orfs_by_sample( $sample_id );
	$family_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
	my $sample_total = 0;
	while( my $family = $family_rs->next() ){
	    my $famid = $family->{"famid"};
	    $opfs{$famid}++;
	    $opf_map{ $sample_id }->{ $famid }++;
	    $sample_total++; 
	}	
	$sample_cnts{$sample_id} = $sample_total;
    }
    foreach my $opf( keys( %opfs ) ){
	print OUT ($opf . "\t");
	foreach my $sample_id( @{ $self->get_sample_ids() } ){
	    if( defined( $opf_map{$sample_id}->{$opf} ) ){
		#total classified reads
		#my $rel_abund = $opf_map{$sample_id}->{$opf} / $sample_cnts{$sample_id};
		#total reads in sample
		my $rel_abund = $opf_map{$sample_id}->{$opf} / $self->MRC::DB::get_number_reads_in_sample( $sample_id );
		print OUT $rel_abund . "\t";
	    }
	    else{
		print OUT "0\t";
	    }
	}
	print OUT "\n";
    }
    close OUT;
    #return $self;
}

sub calculate_project_richness {
    my ($self, $class_id) = @_;
    #identify which families were uniquely found across the project
    my $hit_fams = {}; #hashref

    my $family_rs = $self->MRC::DB::get_families_with_orfs_by_project( $self->get_project_id(), $class_id );
    while( my $family = $family_rs->next() ){
	my $famid = $family->famid->famid();
	next if( defined( $hit_fams->{$famid} ) );
	$hit_fams->{$famid}++;
    }
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/project_richness_${class_id}.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_project_richness: $! ";   
    print OUT join( "\t", "opf", "\n" );
    #dump the famids that were found in the project to the output
    foreach my $famid( keys( %$hit_fams ) ){
	print OUT "$famid\n";
    }
    close OUT;
    #return $self;
}

sub calculate_sample_richness{
    my $self     = shift;
    my $class_id = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/sample_richness_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_sample_richness: $!";    
    print OUT join( "\t", "sample", "opf", "\n" );
    #identify which families were uniquely hit in each sample
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my %hit_fams = ();
	my $family_rs = $self->MRC::DB::get_families_with_orfs_by_sample( $sample_id );
	while( my $family = $family_rs->next() ){
	    my $famid = $family->famid->famid();
	    next if( defined( $hit_fams{$famid} ) );
	    $hit_fams{$famid}++;
	}
	foreach my $famid( keys( %hit_fams ) ){
	    print OUT join( "\t", $sample_id, $famid, "\n" );
	}	
    }
    close OUT;
    #return $self;
}

#divides total number of reads per OPF by all classified reads
sub calculate_project_relative_abundance{
    my ($self, $class_id) = @_;
    #identify number of times each family hit across the project. also, how many reads were classified. 
    my $hit_fams = {};
    my $total     = $self->MRC::DB::get_number_orfs_by_project( $self->get_project_id() );
    print "getting families that have orfs\n";
    my $family_rs = $self->MRC::DB::get_families_with_orfs_by_project( $self->get_project_id() );    
    $family_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    while( my $family = $family_rs->next() ){
	my $famid = $family->{"famid"};
	$hit_fams->{$famid}++;
    }
    print "creating outfile...\n";
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/project_relative_abundance_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_project_relative_abundance: $!";    
    print OUT join( "\t", "opf", "r_abundance", "hits", "total_orfs", "\n" );
    #dump the famids that were found in the project to the output
    foreach my $famid( keys( %$hit_fams ) ){
	my $relative_abundance = $hit_fams->{$famid} / $total;
	print OUT join("\t", $famid, $relative_abundance, $hit_fams->{$famid}, $total, "\n");
    }
    close OUT;
    print "outfile created!\n";
    #return $self;
}

#for each sample, divides total number of reads per OPF by all classified reads
sub calculate_sample_relative_abundance{
    my $self     = shift;
    my $class_id = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/sample_relative_abundance_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_sample_relative_abundance: $!";
    print OUT join( "\t", "sample", "opf", "r_abundance", "hits", "sample_orfs", "\n" );
    #identify number of times each family hit in each sample. also, how many reads were classified.
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my $hit_fams  = {};
	my $total     = $self->MRC::DB::get_number_orfs_by_samples( $sample_id );
	my $family_rs = $self->MRC::DB::get_families_with_orfs_by_sample( $sample_id );
	$family_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
	while( my $family = $family_rs->next() ){
	    my $famid = $family->{"famid"};
	    $hit_fams->{$famid}++;
	}
	foreach my $famid( keys( %$hit_fams ) ){
	    my $relative_abundance = $hit_fams->{$famid} / $total;
	    print OUT join("\t", $sample_id, $famid, $relative_abundance, $hit_fams->{$famid}, $total, "\n");
	}	
    }
    close OUT;
    #return $self;
}

#maps project_id -> sample_id -> read_id -> orf_id -> famid
sub build_classification_map{
    my ($self, $class_id) = @_;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/classification_map_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in build_classification_map: $!";    
    print OUT join("\t", "PROJECT_ID", "SAMPLE_ID", "READ_ID", "ORF_ID", "FAMID", "\n" );
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my $family_rs = $self->MRC::DB::get_families_with_orfs_by_sample( $sample_id );
	$family_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
	while( my $family = $family_rs->next() ){
	    my $famid   = $family->{"famid"};
	    my $orf_id  = $family->{"orf_id"};
	    my $read_id = $self->MRC::DB::get_orf_by_orf_id( $orf_id )->read_id();
	    print OUT join("\t", $self->get_project_id(), $sample_id, $read_id, $orf_id, $famid, "\n" );
	}	
    }
    close OUT;
    #return $self;
}

1;
