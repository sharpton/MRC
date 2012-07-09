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
use IMG::Schema;
use File::Basename;
use IPC::System::Simple qw(capture $EXITVAL);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError);

use Bio::SearchIO;

sub clean_project{
    my $self       = shift;
    my $project_id = shift;
    my $samples    = $self->MRC::DB::get_samples_by_project_id( $project_id );
    while( my $sample = $samples->next() ){
	my $sample_id = $sample->sample_id();
	$self->MRC::DB::delete_search_result_by_sample_id( $sample_id );
	$self->MRC::DB::delete_family_member_by_sample_id( $sample_id );
	$self->MRC::DB::delete_orfs_by_sample_id( $sample_id );
	$self->MRC::DB::delete_reads_by_sample_id( $sample_id );
	$self->MRC::DB::delete_sample( $sample_id );
    }
    $self->MRC::DB::delete_project( $project_id );
    $self->MRC::DB::delete_ffdb_project( $project_id );
    return $self;
}

#currently uses @suffix with basename to successfully parse off .fa. may need to change
sub get_partitioned_samples{
    my $self = shift;
    my $path = shift;
    my @suffixes = (".fa", ".fna");
    my %samples =();    
    #open the directory and get the sample names and paths, 
    opendir( PROJ, $path ) || die "Can't open the directory $path for read: $!\n";
    my @files = readdir( PROJ );
    closedir( PROJ );
    foreach my $file( @files ){
	next if ( $file =~ m/^\./ || $file =~ m/hmmscan/ || $file =~ m/output/);
	next if ( -d $path . "/" . $file );
        #see if there's a description file
	if( $file =~ m/DESCRIPT\.txt/ ){
	    open( TXT, $path . "/" . $file ) || die "Can't open project description file $file for read: $!. Project is $path.\n";
	    my $text = "";
	    while(<TXT>){
		chomp $_;
		$text = $text . " " . $_;
	    }		
	    $self->set_project_desc( $text );
	}
	else{
	    #get sample name here, simple parse on the period in file name
	    my ( $sample ) = basename( $file, @suffixes );
	    #add to %samples, point name to the location
	    $samples{$sample}->{"path"} = $path . "/" . $file;
	}
    }
    warn( "Adding samples to analysis object\n" );
    $self->set_samples( \%samples );
    return $self;
}

sub load_project{
    my $self    = shift;
    my $path    = shift;
    my $nseqs_per_samp_split = shift; #how many seqs should each sample split file contain?
    #get project name and load
    my ( $name, $dir, $suffix ) = fileparse( $path );        
    my $proj = $self->MRC::DB::create_project( $name, $self->get_project_desc() );    
    my $pid  = $proj->project_id();
    warn( "Loading project $pid, files found at $path\n" );
    #store vars in object
    $self->set_project_path( $path );
    $self->set_project_id( $pid );
    #process the samples associated with project
    $self->MRC::Run::load_samples();
    $self->MRC::DB::build_project_ffdb();
    $self->MRC::DB::build_sample_ffdb( $nseqs_per_samp_split ); #this also splits the sample file
    warn( "Project $pid successfully loaded!\n" );
    return $self;
}

sub load_samples{
    my $self   = shift;
    my %samples = %{ $self->get_samples() };
    my $samps = scalar( keys(%samples) );
    warn( "Processing $samps samples associated with project " . $self->get_project_id() . "\n" );
    foreach my $sample( keys( %samples ) ){	
	my $insert  = $self->MRC::DB::create_sample( $sample, $self->get_project_id() );    
	my $sid     = $insert->sample_id();
	$samples{$sample}->{"id"} = $sid;
	my $seqs    = Bio::SeqIO->new( -file => $samples{$sample}->{"path"}, -format => 'fasta' );
	my $count   = 0;
	while( my $read = $seqs->next_seq() ){
	    my $read_name = $read->display_id();
	    $self->MRC::DB::create_metaread( $read_name, $sid );
	    $count++;
	}
	warn("Loaded $count reads into DB for sample $sid\n");
    }
    $self->set_samples( \%samples ); #uncertain if this is necessary
    warn( "All samples associated with project " . $self->get_project_id() . " are loaded\n" );
    return $self;
}

sub back_load_project{
    my $self = shift;
    my $project_id = shift;
    my $ffdb = $self->get_ffdb();
    $self->set_project_id( $project_id );
    $self->set_project_path( $ffdb . "/projects/" . $project_id );
    if( $self->is_remote ){
	$self->set_remote_hmmscan_script( $self->get_remote_project_path() . "run_hmmscan.sh" );
	$self->set_remote_project_log_dir( $self->get_remote_project_path() . "/logs/" );
    }
    return $self;
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
	next if ( $file =~ m/^\./ || $file =~ m/logs/ || $file =~ m/hmmscan/ || $file =~ m/output/ );
	my $sample_id = $file;
	my $sample    = $self->MRC::DB::get_sample_by_sample_id( $sample_id );
	my $sample_name = $sample->name();
	$samples{$sample_name}->{"id"} = $sample_id;
    }
    $self->set_samples( \%samples );
    warn( "Backloading of samples complete\n" );
    return $self;
}

#this is a compute side function. don't use db vars
sub translate_reads{
    my $self     = shift;
    my $input    = shift;
    my $output   = shift;
    my @args     = ("$input", "$output", "-frame=6");
    my $results  = capture( "transeq " . "@args" );
    if( $EXITVAL != 0 ){
	warn("Error translating sequences in $input: $results\n");
	exit(0);
    }
    return $results;
}

sub run_hmmscan{
    my $self   = shift;
    my $inseqs = shift;
    my $hmmdb  = shift;
    my $output = shift;
    my $tblout = shift; #save $output as a tblast style table 1=yes, 0=no
    #Run hmmscan
    my @args = ();
    if( $tblout ){
	@args = ( "--domE 0.001", "--domtblout $output", "$hmmdb", "$inseqs" );
    }
    else{
	@args     = ("$hmmdb", "$inseqs", "> $output");
    }   
    my $results  = capture( "hmmscan " . "@args" );
    if( $EXITVAL != 0 ){
	warn("Error translating sequences in $inseqs: $results\n");
	exit(0);
    }
    return $self;
}

#this method may be faster, but suffers from having a few hardcoded parameters.
#because orfs are necessairly assigned to a sample_id via the ffdb structure, we can
#simply lookup the read_id to sample_id relationship via the ffdb, rather than the DB.
#see load_orf_dblookup for the older method.
sub load_orf{
    my $self        = shift;
    my $orf_alt_id  = shift;
    my $read_alt_id = shift;
    my $sample_id   = shift;
    #A sample cannot have identical reads in it (same DNA string ok, but must have unique alt_ids)
    #Regardless, we need to check to ensure we have a single value
    my $reads = $self->get_schema->resultset("Metaread")->search(
	{
	    read_alt_id => $read_alt_id,
	    sample_id   => $sample_id,
	}
    );
    if( $reads->count() > 1 ){
	warn "Found multiple reads that match read_alt_id: $read_alt_id and sample_id: $sample_id in load_orf. Cannot continue!\n";
	die;
    }
    my $read = $reads->next();
    my $read_id = $read->read_id();
    $self->MRC::DB::insert_orf( $orf_alt_id, $read_id, $sample_id );
    return $self;
}

#the efficiency of this method could be improved!
sub load_orf_old{
    my $self        = shift;
    my $orf_alt_id  = shift;
    my $read_alt_id = shift;
    my $sampref     = shift;
    my %samples     = %{ $sampref };
    my $reads = $self->get_schema->resultset("Metaread")->search(
	{
	    read_alt_id => $read_alt_id,
	}
    );
    while( my $read = $reads->next() ){
	my $sample_id = $read->sample_id();
	if( exists( $samples{$sample_id} ) ){
	    my $read_id = $read->read_id();
	    $self->insert_orf( $orf_alt_id, $read_id, $sample_id );
	    #A project cannot have identical reads in it (same DNA string ok, but must have unique alt_ids)
	    last;
	}
    }
}

sub parse_orf_id{
    my $orfid  = shift;
    my $method = shift;
    my $read_id = ();
    if( $method eq "transeq" ){
	if( $orfid =~ m/^(.*)\_/ ){
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
    #remember, each orf_split has its own search_results sub directory
    my $search_results = $self->get_sample_path( $sample_id ) . "/search_results/" . $orf_split;
    my $hmmdb_name     = $self->get_hmmdb_name();
    my $query_seqs     = $self->get_sample_path( $sample_id ) . "/orfs/" . $orf_split;
    my %hit_map        = %{ initialize_hit_map( $query_seqs ) };
    #open search results, get all results for this split
    opendir( RES, $search_results ) || die "Can't open $search_results for read in classify_reads: $!\n";
    my @result_files = readdir( RES );
    closedir( RES );
    foreach my $result_file( @result_files ){
	next unless( $result_file =~ m/$orf_split/ );
	%hit_map = %{ $self->MRC::Run::parse_hmmscan_table( $search_results . "/" . $result_file, \%hit_map ) };
    }
    #now insert the data into the database
    my $is_strict = $self->is_strict_clustering();
    my $n_hits    = 0;
    foreach my $orf_alt_id( keys( %hit_map ) ){
	#note: since we know which reads don't have hits, we could, here produce a summary stat regarding unclassified reads...
	#for now, we won't add these to the datbase
	next unless( $hit_map{$orf_alt_id}->{"has_hit"} );
	#how we insert into the db may change depending on whether we do strict of fuzzy clustering
	if( $is_strict ){
	    $n_hits++;
	    my $evalue   = $hit_map{$orf_alt_id}->{$is_strict}->{"evalue"};
	    my $coverage = $hit_map{$orf_alt_id}->{$is_strict}->{"coverage"};
	    my $score    = $hit_map{$orf_alt_id}->{$is_strict}->{"score"};
	    my $famid    = $hit_map{$orf_alt_id}->{$is_strict}->{"target"};
	    my $orf_id = $self->MRC::DB::get_orf_from_alt_id( $orf_alt_id, $sample_id )->orf_id();
	    print "$orf_alt_id \t $orf_id \t $famid \n";
#	    $self->MRC::DB::insert_search_result( $orf_id, $famid, $evalue, $score, $coverage );
#	    $self->MRC::DB::insert_family_member_orf( $orf_id, $famid );
	}
    }
    print "Found and inserted $n_hits threshold passing search results into the database\n";
}

#called by classify_reads
#parses a hmmscan hit table and updates the hit map based on the information in the table
sub parse_hmmscan_table{
    my $self      = shift;
    my $file      = shift;
    my $r_hit_map = shift;
    my %hit_map   = %{ $r_hit_map };
    #define clustering thresholds
    my $t_evalue   = $self->get_evalue_threshold();   #dom-ieval threshold
    my $t_coverage = $self->get_coverage_threshold(); #coverage threshold (applied to query)
    my $is_strict  = $self->is_strict_clustering();   #strict (top-hit) v. fuzzy (all hits above thresholds) clustering. Fuzzy not yet implemented   
    #open the file and process each line
    open( HMM, "$file" ) || die "can't open $file for read: $!\n";    
    while(<HMM>){
	chomp $_;
	if( $_ =~ m/^\#/ || $_ =~ m/^$/ ){
	    next;
	}
	my( $tid, $tacc, $tlen,  $qid, $qacc, $qlen, $full_eval, 
	    $full_score, $full_bias, $dom_num, $dom_total, 
	    $dom_ceval, $dom_ieval, $dom_score, $dom_bias, 
	    $tstart, $tstop, $qstart, $qstop, 
	    $estart, $estop, $acc, $description ) = split( ' ', $_ );
	#calculate coverage from query perspective
	my $coverage  = 0;
	if( $estop > $estart ){
	    my $len = $estop - $estart + 1; #coverage calc must include first base!
	    $coverage = $len / $qlen;
	}
	if( $estart > $estop ){
	    my $len = $estart - $estop;
	    $coverage = $len / $qlen;
	}
	#does hit pass threshold?
	if( $dom_ieval <= $t_evalue && $coverage >= $t_coverage ){
	    #is this the first hit for the query?
	    if( $hit_map{$qid}->{"has_hit"} == 0 ){
		#note that we use is_strict to differentiate top hit clustering from fuzzy clustering w/in hash
		$hit_map{$qid}->{$is_strict}->{"target"}   = $tid;
		$hit_map{$qid}->{$is_strict}->{"evalue"}   = $dom_ieval;
		$hit_map{$qid}->{$is_strict}->{"coverage"} = $coverage;
		$hit_map{$qid}->{$is_strict}->{"score"}    = $dom_score;
		$hit_map{$qid}->{"has_hit"} = 1;
	    }
	    elsif( $is_strict ){
		#only add if the current hit is better than the prior best hit. start with best evalue
		if( $dom_ieval < $hit_map{$qid}->{$is_strict}->{"evalue"} ||
		    #if evalues tie, use coverage to break
		    ( $dom_ieval == $hit_map{$qid}->{$is_strict}->{"evalue"} &&
		      $coverage >   $hit_map{$qid}->{$is_strict}->{"coverage"} ) ||
		    #finally, if evalue and coverage tie, use score to break
		    ( $dom_ieval == $hit_map{$qid}->{$is_strict}->{"evalue"} &&
		      $coverage  == $hit_map{$qid}->{$is_strict}->{"coverage"} &&
		      $dom_score >  $hit_map{$qid}->{$is_strict}->{"score"} ) 
		    ){
		    #add the hits here
		    $hit_map{$qid}->{$is_strict}->{"target"}   = $tid;
		    $hit_map{$qid}->{$is_strict}->{"evalue"}   = $dom_ieval;
		    $hit_map{$qid}->{$is_strict}->{"coverage"} = $coverage;
		    $hit_map{$qid}->{$is_strict}->{"score"}    = $dom_score;
		}
	    }
	    else{
		#if stict clustering, we might have a pefect tie. Winner is the first one we find, so pass
		if( $is_strict ){
		    next;
		}
		#else, add every threshold passing hit to the hash
		$hit_map{$qid}->{$is_strict}->{$tid}->{"evalue"}   = $dom_ieval;
		$hit_map{$qid}->{$is_strict}->{$tid}->{"coverage"} = $coverage;
		$hit_map{$qid}->{$is_strict}->{$tid}->{"score"}    = $dom_score;
	    }
	}
    }
    close HMM;
    return \%hit_map;
}

#called by classify_reads
#initialize a lookup hash by pulling seq_ids from a fasta file and dumping them into hash keys
sub initialize_hit_map{
    my $seq_file = shift;
    my $seqs     = Bio::SeqIO->new( -file => $seq_file, -format => 'fasta' );
    my %hit_map  = ();
    while( my $seq = $seqs->next_seq() ){
	my $id = $seq->display_id();
	$hit_map{$id}->{"has_hit"} = 0;
    }
    return \%hit_map;
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
		  print join ("\t", $qorf, $qacc, $qdes, $qlen, $nhit, $hmm, $score, $signif, $hqlen, "\n");
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
  return $self;
}

sub build_hmm_db{
    my $self     = shift;
    my $hmmdb    = shift; #name of hmmdb to use, if build, new hmmdb will be named this. check for dups
    my $split_size  = shift; #integer - how many hmms per split?
    my $force    = shift; #0/1 - force overwrite of old HMMdbs during compression.
    my $ffdb     = $self->get_ffdb();
    #where is the hmmdb going to go? each hmmdb has its own dir
    my $hmmdb_path = $self->MRC::DB::get_hmmdb_path();
    warn "Building HMMdb $hmmdb, placing $split_size per split\n";
    #Have you built this HMMdb already?
    if( -d $hmmdb_path && !($force) ){
	warn "You've already built an HMMdb with the name $hmmdb at $hmmdb_path. Please delete or overwrite by using the -f option.\n";
	die;
    }
    #create the HMMdb dir that will hold our split hmmdbs
    $self->MRC::DB::build_hmmdb_ffdb( $hmmdb_path );
    #update the path to make it easier to build the split hmmdbs (e.g., points to an incomplete file name)
    $hmmdb_path = $hmmdb_path . $hmmdb;
    #constrain analysis to a set of families of interest
    my @families   = sort( @{ $self->get_subset_famids() });
    my $n_fams     = @families;
    my $count      = 0;
    my @split      = (); #array of family HMMs (compressed)
    my $n_proc     = 0;
    foreach my $family( @families ){
	#find the HMM associated with the family (compressed)
	my $family_hmm = $ffdb . "/HMMs/" . $family . ".hmm.gz";
	push( @split, $family_hmm );
	$count++;
	#if we've hit our split size, process the split
	if( $count >= $split_size || $family == $families[-1] ){
	    $n_proc++;
	    #build the HMMdb
	    my $split_db_path = cat_hmmdb_split( $hmmdb_path, $n_proc, $ffdb, \@split );
	    #compress the HMMdb, a wrapper for hmmpress
	    #we might need to come back here and build a switch so that this runs on local thread, but for remote, we don't want to do this here, so it's turned off. Better yet, put this in a standalone routine.
	    #compress_hmmdb( $split_db_path, $force );
	    #we do want hmmdbs to be gzipped 
	    gzip_hmmdb( $split_db_path );
	    #save the gzipped copy, remove the uncompressed copy
	    unlink( $split_db_path );
	    @split = ();
	    $count = 0;
	}
    }
    warn "HMMdb successfully built and compressed.\n";
    return $self;
}

sub gzip_hmmdb{
    my $splitout = shift;
    gzip $splitout => $splitout . ".gz"
	or die "gzip failed: $GzipError\n";
}

#state how many spilts you want, will determine the correct number of hm
sub build_hmm_db_by_n_splits{
    my $self     = shift;
    my $hmmdb    = shift; #name of hmmdb to use, if build, new hmmdb will be named this. check for dups
    my $n_splits = shift; #integer - how many hmmdb splits should we produce?
    my $force    = shift; #0/1 - force overwrite of old HMMdbs during compression.
    my $ffdb     = $self->get_ffdb();
    #where is the hmmdb going to go? each hmmdb has its own dir
    my $hmmdb_path = $ffdb . "HMMdbs/" . $hmmdb . "/";
    warn "Building HMMdb $hmmdb, splitting into $n_splits parts.\n";
    #Have you built this HMMdb already?
    if( -d $hmmdb_path && !($force) ){
	warn "You've already built an HMMdb with the name $hmmdb at $hmmdb_path. Please delete or overwrite by using the -f option.\n";
	die;
    }
    #create the HMMdb dir that will hold our split hmmdbs
    $self->MRC::DB::build_hmmdb_ffdb( $hmmdb_path );
    #update the path to make it easier to build the split hmmdbs (e.g., points to an incomplete file name)
    $hmmdb_path = $hmmdb_path . $hmmdb;
    #constrain analysis to a set of families of interest
    my @families   = sort( @{ $self->get_subset_famids() });
    my $n_fams     = @families;
    my $split_size = $n_fams / $n_splits;
    my $count      = 0;
    my @split      = (); #array of family HMMs (compressed)
    my $n_proc     = 0;
    foreach my $family( @families ){
	#find the HMM associated with the family (compressed)
	my $family_hmm = $ffdb . "/HMMs/" . $family . ".hmm.gz";
	push( @split, $family_hmm );
	$count++;
	#if we've hit our split size, process the split
	if( $count >= $split_size || $family == $families[-1] ){
	    $n_proc++;
	    #build the HMMdb
	    my $split_db_path = cat_hmmdb_split( $hmmdb_path, $n_proc, $ffdb, \@split );
	    #compress the HMMdb, a wrapper for hmmpress
	    compress_hmmdb( $split_db_path, $force );
	    @split = ();
	    $count = 0;
	}
    }
    warn "HMMdb successfully built and compressed.\n";
    return $self;
}

sub cat_hmmdb_split{
    my $hmmdb_path = shift;
    my $n_proc     = shift;
    my $ffdb       = shift;
    my @families   = @{ $_[0] };
    my $split_db_path = $hmmdb_path . "_" . $n_proc . ".hmm";
    my $fh;
    open( $fh, ">>$split_db_path" ) || die "Can't open $split_db_path for write: $!\n";
    foreach my $family( @families ){
	gunzip $family => $fh;
    }
    close $fh;
    return $split_db_path;
}

sub compress_hmmdb{
    my $file  = shift;
    my $force = shift;
    my @args  = ();
    if( $force ){
	@args     = ("-f", "$file");
    }
    else{
	@args = ("$file");
    }
    my $results  = capture( "hmmpress " . "@args" );
    if( $EXITVAL != 0 ){
	warn("Error translating sequences in $file: $results\n");
	exit(0);
    }
    return $results;
}

#copy a project's ffdb over to the remote server
sub load_project_remote{
    my $self = shift;
    my $pid  = $self->get_project_id();
    my $ffdb = $self->get_ffdb();
    my $project_dir = $ffdb . "/projects/" . $pid;
    my $remote_dir  = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb . "/projects/" . $pid;
    warn( "Adding $project_dir to remote ffdb: $remote_dir\n" );
    my $results = $self->MRC::Run::remote_transfer( $project_dir, $remote_dir, "directory" );
    return $results;
}

#the qsub -sync y option keeps the connection open. lower chance of a connection failure due to a ping flood, but if connection between
#local and remote tends to drop, this may not be foolproof
sub translate_reads_remote{
    my $self = shift;
    my $waittime = shift;
    my @sample_ids = @{ $self->get_sample_ids() };
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my @job_ids = ();
    foreach my $sample_id( @sample_ids ){
	my $remote_input_dir  = $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/raw/";
	my $remote_output_dir =  $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
#	my @sample_files = @{ $self->MRC::DB::get_split_sequence_paths( $self->get_samples->{$sample}, 0 ) };
#this block will run each split in series. to do parallel, i need to execute qsub on the remote side. this will also cut back on active ssh connections to remote
#	foreach my $sample_file( @sample_files ){    
#	    my $remote_input  = $remote_input_dir . $sample_file;
#	    my $remote_output = $remote_output_dir . $sample_file;
#	    my $remote_cmd = "\'qsub -sync y " . $self->get_remote_scripts() . "run_transeq.sh " . $remote_input . " " . $remote_output . "\'";	
#	}
# If we want to submit directly from local, use the line below
#	my $remote_cmd = "\'qsub -sync y perl " . $self->get_remote_scripts() . "run_transeq_handler.pl -i " . $remote_input_dir . " -o " . $remote_output_dir . " -w " . $waittime . "\'";	
# It is more efficient, however, to submit jobs to cluster on remote: Note that we have to pass r_scripts_path to command so that we can execute queue submission script off on remote server
	my $remote_cmd = "\'perl " . $self->get_remote_scripts() . "run_transeq_handler.pl -i " . $remote_input_dir . " -o " . $remote_output_dir . " -w " . $waittime . " -s " . $self->get_remote_scripts() . "\'";	
	my $remote_orfs = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
	my $local_orfs  = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
	print( "translating reads\n" );
	$self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
	print( "translation complete. Transferring orfs\n" );
	$self->MRC::Run::remote_transfer( $remote_orfs, $local_orfs, 'c' );
	print( "transfer of orfs successful\n");	
    }
    warn( "All reads were translated on the remote server and locally acquired\n" );
    return $self;
}

#if you'd rather routinely ping the remote server to check for job completion. not default
sub translate_reads_remote_ping{
    my $self = shift;
    my $waittime = shift; #in seconds, amount of time between queue checks
    my @sample_ids =  @{ $self->get_sample_ids() };
    my %jobs = ();
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    foreach my $sample_id( @sample_ids ){
	my $remote_input  = $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/raw.fa";
	my $remote_output =  $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs.fa";
	my $remote_cmd = "\'qsub " . $self->get_remote_scripts() . "run_transeq.sh " . $remote_input . " " . $remote_output . "\'";
	my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
	if( $results =~ m/^Your job (\d+) / ){
	    my $job_id = $1;
	    $jobs{$job_id} = $sample_id;
	}
	else{
	    warn( "Remote server did not return a properly formatted job id when running $remote_cmd using connection $connection. Got $results instead!. Exiting.\n" );
	    exit(0);
	}
    }
    #check the jobs until they are all complete
    my @job_ids = keys( %jobs );
    my $time = $self->MRC::Run::remote_job_listener( \@job_ids, $waittime );
    warn( "Reads were translated in approximately $time seconds on remote server\n");
    #consider that a completed job doesn't mean a successful run!
    warn( "Pulling translated reads from remote server\n" );
    foreach my $job( keys( %jobs ) ){
	my $sample_id = $jobs{$job};
	my $remote_orfs = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs.fa";
	my $local_orfs  = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs.fa";
	my $results = $self->MRC::Run::remote_transfer( $remote_orfs, $local_orfs, 'file' );
    }
}

sub remote_job_listener{
    my $self     = shift;
    my $jobs     = shift; #a refarray
    my $waittime = shift;
    my $numwaits = 0;
    my %status   = ();
    my $remote_cmd = "\'qstat\'";
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    while(1){
	#stop checking if every job has a finished status
	last if( scalar( keys( %status ) ) == scalar( @{ $jobs } ) );
	#call qstat and grab the output
	my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
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

sub local_job_listener{
    my $self     = shift;
    my $jobs     = shift; #a refarray
    my $waittime = shift;
    my $numwaits = 0;
    my %status   = ();
    while(1){
	#stop checking if every job has a finished status
	last if( scalar( keys( %status ) ) == scalar( @{ $jobs } ) );
	#call ps and grab the output
	my $results = capture( "ps" );
	if( $EXITVAL != 0 ){
	    warn( "Error running ps!\n" );
	    exit(0);
	}
	#see if any of the jobs are complete. pass on those we've already finished
	foreach my $jobid( @{ $jobs } ){
	    next if( exists( $status{$jobid} ) );
	    if( $results !~ m/^$jobid / ){
		$status{$jobid}++;
	    }
	}
	sleep( $waittime );
	$numwaits++
    }
    my $time = $numwaits * $waittime;
    return $time;
}


sub remote_transfer{
    my $self = shift;
    my $source_path = shift; #a file or dir path (not connection string)
    my $sink_path   = shift; #a file or dir path
    my $path_type   = shift; #'file' or 'directory' or 'contents'
    my @args = ();
    if( $path_type eq 'file' || $path_type eq "f" ){ 
	@args = ( $source_path, $sink_path );
    }
    elsif( $path_type eq 'directory' || $path_type eq "d" ){
	@args = ( "-r", $source_path, $sink_path );
    }
    #on some machines, if the directories are the same on remote and local, a recursive scp will create a subdir with identical dir name. Use the contents setting to 
    #copy all of the contents of a file over, without transferring the actual sourcedir as well
    elsif( $path_type eq 'contents' || $path_type eq "c" ){
	@args = ( $source_path . "/*", $sink_path );
    }
    else{
	warn( "You did not correctly specify your parameters in remote_transfer when moving $source_path to $sink_path! Path type is $path_type. Exiting.\n" );
	exit(0);
    }
    warn( "scp " . "@args" );
    my $results = capture( "scp " . "@args" );
    if( $EXITVAL != 0 ){
	warn( "Error transferring $source_path to $sink_path using $path_type: $results\n" );
	exit(0);
    }
    return $results;  
}

#File::Base name has a dirname function, but it includes the full path. This only returns the current directory name from a path
sub get_dirname{
    my $self = shift;
    my $path = shift;
    #remove any trailing slashes
    $path =~ s/\/$//;
    #split on slashes, grab the last bin in the array
    my @data = split("\/", $path );
    my $dirname = $data[-1];
    return $dirname;
}

sub execute_ssh_cmd{
    my $self       = shift;
    my $connection = shift; #e.g., tom@www
    my $remote_cmd = shift;
    my $verbose    = shift;
    my $results;
    my @args = ( $connection, $remote_cmd );
    if( defined( $verbose ) && $verbose ){
 	warn( "ssh -v " . "@args" );
	$results = capture( "ssh -v " . "@args" );
    }
    else{
 	warn( "ssh " . "@args" );
	$results = capture( "ssh " . "@args" );
    }
    if( $EXITVAL != 0 ){
	warn( "Error running ssh command $connection $remote_cmd: $results\n" );
	exit(0);
    }
    return $results;
}

sub remote_transfer_hmm_db{
    my $self = shift;
    my $hmmdb_name = shift;
    my $ffdb = $self->get_ffdb();
    my $hmmdb_dir = $ffdb . "/HMMdbs/" . $hmmdb_name;
    my $remote_dir  = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb . "/HMMdbs/" . $hmmdb_name;
    my $results = $self->MRC::Run::remote_transfer( $hmmdb_dir, $remote_dir, "directory" );
    return $results;
}

sub remote_transfer_batch{
    my $self = shift;
    my $hmmdb_name = shift;
    my $ffdb = $self->get_ffdb();
    my $hmmdb_dir = $ffdb . "/HMMbatches/" . $hmmdb_name;
    my $remote_dir  = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb . "/HMMbatches/" . $hmmdb_name;
    my $results = $self->MRC::Run::remote_transfer( $hmmdb_dir, $remote_dir, "file" );
    return $results;
}

sub gunzip_file_remote{
    my ( $self, $remote_file ) = @_;
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my $remote_cmd = "gunzip -f " . $remote_file;
    my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
    return $results;
}

#notice that we edit file suffixes given the remote script procedure!
sub run_hmmsearch_remote{
    my ( $self, $batchfile, $query_db ) = @_;
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    $batchfile =~ s/\.hmm//;
    $query_db  =~ s/\.fa//;
    my $remote_cmd = "\'qsub -sync y " . $self->get_remote_scripts() . "run_hmmsearch.sh " . $batchfile . " " . $query_db . "\'";
    my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
    return $results;
}

sub run_hmmscan_remote{
    my( $self, $sample_id, $verbose ) = @_;
 
    my $hmmscan_r_script_path = $self->get_remote_hmmscan_script();
    my $hmmscan_handler_log   = $self->get_remote_project_log_dir() . "/hmmscan_handler";
    my $hmmdb_name            = $self->get_hmmdb_name();
    my $remote_hmmdb_dir      = $self->get_remote_ffdb . "/HMMdbs/" . $hmmdb_name . "/";
    my $remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/";
    my $remote_query_dir      = $self->get_remote_sample_path( $sample_id ) . "/orfs/";

    my $remote_cmd   = "\'perl " . $self->get_remote_scripts() . "/run_remote_hmmscan_handler.pl -h $remote_hmmdb_dir -o $remote_search_res_dir -i $remote_query_dir -n $hmmdb_name -s $hmmscan_r_script_path > " . $hmmscan_handler_log . ".out 2> " . $hmmscan_handler_log . ".err\'";
    print "$remote_cmd\n";
    my $connection            = $self->get_remote_username . "@" . $self->get_remote_server;
    my $results               = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd, $verbose );
    return $results;
}

sub get_remote_hmmscan_results{
    my( $self, $sample_id ) = @_;
    my $remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/";
    my $local_search_res_dir  = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/" . $sample_id . "/search_results/";
    #recall, every sequence split has its own output dir to cut back on the number of files per directory
    my $in_orf_dir = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
    foreach my $in_orfs( @{ $self->MRC::DB::get_split_sequence_paths( $in_orf_dir, 0 ) } ){	
	my $split_orf_search_results = $remote_search_res_dir . $in_orfs;
	$self->MRC::Run::remote_transfer(  $self->get_remote_username . "@" . $self->get_remote_server . ":" . $split_orf_search_results, $local_search_res_dir, 'd' );
#	$self->MRC::Run::remote_transfer(  $self->get_remote_username . "@" . $self->get_remote_server . ":" . $remote_search_res_dir, $local_search_res_dir, 'c' );
    }
    return $self;
}

#Note that this may not yet be a perfect replacement for the ping version below. The problem with this approach is that it keeps an ssh connection alive
#for every job, which can flood the remote server. So this version is now defuct. Use run_hmmscan_remote instead
sub run_hmmscan_remote_defunct{
    my( $self, $in_seqs_dir, $inseq_file, $hmmdb, $output, $outstem, $type, $closed, $second_output ) = @_; #type is 0 for default and 1 for --max, 2 is to run both at the same time, requires $second_output to be set
    if( !defined( $type ) ){
	$type = 0;
    }
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my $remote_cmd;
    if( defined( $second_output ) ){
	$remote_cmd = "\'qsub -sync y " . $self->get_remote_scripts() . "run_hmmscan.sh "  . $in_seqs_dir . " " .$inseq_file . " " . $hmmdb . " " . $output . " " . $outstem . " " . $type . " " . $second_output . "\'";
    }
    else{
	#set closed = 1 if you don't want the connection to remote server to remain open. This is important if you are worried about flooding the connection pool.
	if( defined( $closed ) && $closed == 1 ){
	    $remote_cmd = "\'qsub " . $self->get_remote_scripts() . "run_hmmscan.sh " .  $in_seqs_dir . " " . $inseq_file . " " . $hmmdb . " " . $output . " " . $outstem . " " . $type . "\'";
	}
	else{
	    $remote_cmd = "\'qsub -sync y " . $self->get_remote_scripts() . "run_hmmscan.sh " .  $in_seqs_dir . " " . $inseq_file . " " . $hmmdb . " " . $output . " " . $outstem . " " . $type . "\'";
	}
    }
    my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
    return $results;
}

sub run_blast_remote{
    my ( $self, $inseq, $db, $output, $closed ) = @_;
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my $remote_cmd;
    if( !defined( $closed ) ){
	$remote_cmd = "\'qsub -sync y " . $self->get_remote_scripts() . "run_blast.sh " . $inseq . " " . $db . " " . $output . "\'";
    }
    elsif( $closed == 1 ){
	$remote_cmd = "\'qsub " . $self->get_remote_scripts() . "run_blast.sh " . $inseq . " " . $db . " " . $output . "\'";
    }
    else{
	#if( $closed == 0, or same as if not defined $closed)
	$remote_cmd = "\'qsub -sync y " . $self->get_remote_scripts() . "run_blast.sh " . $inseq . " " . $db . " " . $output . "\'";
    }
    my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
    return $results;
}

sub transfer_hmmsearch_remote_results{
    my $self = shift;
    my $hmmdb_name = shift;
    my $ffdb = $self->get_ffdb();
    my $local_file = $ffdb . "/hmmsearch/" . $hmmdb_name;
    my $remote_file  = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb . "/hmmsearch/" . $hmmdb_name;
    my $results = $self->MRC::Run::remote_transfer( $remote_file, $local_file, "file" );
    return $results;
}

sub remove_remote_file{
    my( $self, $file ) = @_;
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my $remote_cmd = "rm " . $file;
    my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
    return $results;
}

sub remove_hmmsearch_remote_results{
    my ( $self, $search_outfile ) = @_;
    my $remote_file = $self->get_remote_ffdb . "/hmmsearch/" . $search_outfile;
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my $remote_cmd = "rm " . $remote_file;
    my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
    return $results;
}

sub run_hmmscan_remote_ping{
    my $self = shift;
    my $hmmdb_name = shift;
    my $waittime   = shift; #in seconds, amount of time between queue checks
    my @sample_ids =  @{ $self->get_sample_ids() };
    my %jobs = ();
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    #use get_hmmdbs with the 1 flag to indicate remote server file paths
    my %hmmdbs =  %{ $self->MRC::DB::get_hmmdbs( $hmmdb_name, 1 ) };
    #search each sample against each hmmdb split
    foreach my $sample_id( @sample_ids ){
	my $remote_input  = $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs.fa";
	foreach my $hmmdb( keys( %hmmdbs ) ){
	    my $remote_hmmdb_path = $hmmdbs{$hmmdb};
	    my $remote_output =  $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/search_results/" . $sample_id . "_v_" . $hmmdb . ".hsc";
	    my $remote_cmd = "\'qsub " . $self->get_remote_scripts() . "run_hmmscan.sh -o " . $remote_output . " " . $remote_hmmdb_path . " " . $remote_input . "\'";
	    my $results = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
	    if( $results =~ m/^Your job (\d+) / ){
		my $job_id = $1;
		$jobs{$job_id}{$sample_id}{$hmmdb} = $remote_output;
	    }
	    else{
		warn( "Remote server did not return a properly formatted job id when running $remote_cmd using connection $connection. Got $results instead!. Exiting.\n" );
		exit(0);
	    }
	    #add a sleep so that we don't flood the remote server
	    sleep(10);
	}
    }
    #check the jobs until they are all complete
    my @job_ids = keys( %jobs );
    my $time = $self->MRC::Run::remote_job_listener( \@job_ids, $waittime );
    warn( "Hmmscan was conducted translated in approximately $time seconds on remote server\n");
    #consider that a completed job doesn't mean a successful run!
    warn( "Pulling hmmscan reads from remote server\n" );
    print Dumper %jobs;
    foreach my $job( keys( %jobs ) ){
	foreach my $sample_id( @sample_ids ){
	    foreach my $hmmdb( keys( %hmmdbs ) ){
		next unless exists( $jobs{$job}{$sample_id}{$hmmdb} );
		warn( join("\t", $job, $sample_id, $hmmdb, "\n" ) );
		my $remote_results = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $jobs{$job}{$sample_id}{$hmmdb};
		my $local_results  = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/search_results/" . $sample_id . "_v_" . $hmmdb . ".hsc";
		my $results = $self->MRC::Run::remote_transfer( $remote_results, $local_results, 'file' );
	    }
	}
    }    
}

sub get_family_size_by_id{
    my $self  = shift;
    my $famid = shift;
    my $refonly = shift; #only count reference family members?
    my $fam_mems = $self->MRC::DB::get_fammembers_by_famid( $famid );
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
    my $self = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/PCA_data_frame.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in build_classification_map: $!\n";    
    print OUT join("\t", "OPF", @{ $self->get_sample_ids() }, "\n" );
    my %opfs        = ();
    my %opf_map     = (); #$sample->$opf->n_hits;  
    my %sample_cnts = (); #sample_cnts{$sample_id} = total_hits_in_sample
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my $family_rs  = $self->MRC::DB::get_families_with_orfs_by_sample( $sample_id );
	my $sample_total = 0;
	while( my $family = $family_rs->next() ){
	    my $famid  = $family->famid->famid();
	    $opfs{$famid}++;
	    $opf_map{ $sample_id }->{ $famid }++;
	    $sample_total++; 
	}	
	$sample_cnts{$sample_id} = $sample_total;
    }
    foreach my $opf( keys( %opfs ) ){
	print OUT $opf . "\t";
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
    return $self;
}

sub calculate_project_richness{
    my $self = shift;
    #identify which families were uniquely found across the project
    my %hit_fams = ();
    my $family_rs = $self->MRC::DB::get_families_with_orfs_by_project( $self->get_project_id() );
    while( my $family = $family_rs->next() ){
	my $famid = $family->famid->famid();
	next if( defined( $hit_fams{$famid} ) );
	$hit_fams{$famid}++;
    }
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/project_richness.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_project_richness: $!\n";    
    print OUT join( "\t", "opf", "\n" );
    #dump the famids that were found in the project to the output
    foreach my $famid( keys( %hit_fams ) ){
	print OUT "$famid\n";
    }
    close OUT;
    return $self;
}

sub calculate_sample_richness{
    my $self = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/sample_richness.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_sample_richness: $!\n";    
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
    return $self;
}

#divides total number of reads per OPF by all classified reads
sub calculate_project_relative_abundance{
    my $self = shift;
    #identify number of times each family hit across the project. also, how many reads were classified. 
    my %hit_fams = ();
    my $total    = 0;
    my $family_rs = $self->MRC::DB::get_families_with_orfs_by_project( $self->get_project_id() );    
    while( my $family = $family_rs->next() ){
	my $famid = $family->famid->famid();
	$hit_fams{$famid}++;
	$total++;	   
    }
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/project_relative_abundance.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_project_relative_abundance: $!\n" ;    
    print OUT join( "\t", "opf", "r_abundance", "hits", "total_reads", "\n" );
    #dump the famids that were found in the project to the output
    foreach my $famid( keys( %hit_fams ) ){
	my $relative_abundance = $hit_fams{$famid} / $total;
	print OUT join("\t", $famid, $relative_abundance, $hit_fams{$famid}, $total, "\n");
    }
    close OUT;
    return $self;
}

#for each sample, divides total number of reads per OPF by all classified reads
sub calculate_sample_relative_abundance{
    my $self = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/sample_relative_abundance.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_sample_relative_abundance: $!\n";    
    print OUT join( "\t", "sample", "opf", "r_abundance", "hits", "sample_reads", "\n" );
    #identify number of times each family hit in each sample. also, how many reads were classified.
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my %hit_fams  = ();
	my $total     = 0;
	my $family_rs = $self->MRC::DB::get_families_with_orfs_by_sample( $sample_id );
	while( my $family = $family_rs->next() ){
	    my $famid = $family->famid->famid();
	    $hit_fams{$famid}++;
	    $total++;
	}
	foreach my $famid( keys( %hit_fams ) ){
	    my $relative_abundance = $hit_fams{$famid} / $total;
	    print OUT join("\t", $sample_id, $famid, $relative_abundance, $hit_fams{$famid}, $total, "\n");
	}	
    }
    close OUT;
    return $self;
}

#maps project_id -> sample_id -> read_id -> orf_id -> famid
sub build_classification_map{
    my $self = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/classification_map.tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in build_classification_map: $!\n";    
    print OUT join("\t", "PROJECT_ID", "SAMPLE_ID", "READ_ID", "ORF_ID", "FAMID", "\n" );
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my $family_rs = $self->MRC::DB::get_families_with_orfs_by_sample( $sample_id );
	while( my $family = $family_rs->next() ){
	    my $famid  = $family->famid->famid();
	    my $orf_id = $family->orf_id();
	    my $read_id = $self->MRC::DB::get_orf_by_orf_id( $orf_id )->read_id();
	    print OUT join("\t", $self->get_project_id(), $sample_id, $read_id, $orf_id, $famid, "\n" );
	}	
    }
    close OUT;
    return $self;
}

1;
