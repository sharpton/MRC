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
	if( $self->multi_load() ){
	    my @read_names = ();
	    while( my $read = $seqs->next_seq() ){
		my $read_name = $read->display_id();
		
		push( @read_names, $read_name );
		$count++;
	    }
	    $self->MRC::DB::create_multi_metareads( $sid, \@read_names );
	}
	else{
	    while( my $read = $seqs->next_seq() ){
		my $read_name = $read->display_id();
		$self->MRC::DB::create_metaread( $read_name, $sid );
		$count++;
	    }
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
	$self->set_remote_hmmsearch_script( $self->get_remote_project_path() . "run_hmmsearch.sh" );
        $self->set_remote_blast_script( $self->get_remote_project_path() . "run_blast.sh" );
        $self->set_remote_last_script( $self->get_remote_project_path() . "run_last.sh" );
        $self->set_remote_formatdb_script( $self->get_remote_project_path() . "run_formatdb.sh" );
        $self->set_remote_lastdb_script( $self->get_remote_project_path() . "run_lastdb.sh" );
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
	next if ( $file =~ m/^\./ || $file =~ m/logs/ || $file =~ m/hmmscan/ || $file =~ m/output/ || $file =~ m/\.sh/ );
	my $sample_id = $file;
	my $sample    = $self->MRC::DB::get_sample_by_sample_id( $sample_id );
#	my $sample_name = $sample->name();
#	$samples{$sample_name}->{"id"} = $sample_id;
	my $sample_alt_id = $sample->sample_alt_id();
	$samples{$sample_alt_id}->{"id"} = $sample_id;
    }
    $self->set_samples( \%samples );
    #back load remote data
    if( $self->is_remote() ){
	$self->set_remote_hmmscan_script( $self->get_remote_project_path() . "run_hmmscan.sh" );
        $self->set_remote_hmmsearch_script( $self->get_remote_project_path() . "run_hmmsearch.sh" );
        $self->set_remote_blast_script( $self->get_remote_project_path() . "run_blast.sh" );
        $self->set_remote_project_log_dir( $self->get_remote_project_path() . "/logs/" );
    }
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

sub load_multi_orfs{
    my $self       = shift;
    my $orfs       = shift; #a Bio::Seq object
    my $sample_id  = shift;
    my $algo       = shift;
    my %orf_map    = (); #orf_alt_id to read_id
    my %read_map   = (); #read_alt_id to read_id
    my $count      = 0;
    while( my $orf = $orfs->next_seq() ){
	$count++;
	my $orf_alt_id  = $orf->display_id();
	my $read_alt_id = MRC::Run::parse_orf_id( $orf_alt_id, $algo );
	#get the read id, but only if we haven't see this read before
	my $read_id;
	if( defined( $read_map{ $read_alt_id } ) ){
	    $read_id = $read_map{ $read_alt_id };
	}
	else{
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
		$read_id = $read->read_id();
		$read_map{ $read_alt_id } = $read_id;
	}
	$orf_map{ $orf_alt_id } = $read_id;
    }
    $self->MRC::DB::insert_multi_orfs( $sample_id, \%orf_map );
    print "Bulk loaded $count orfs to the database.\n";
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
    my $search_results = $self->get_sample_path( $sample_id ) . "/search_results/" . $algo . "/" . $orf_split;
    print "processing $search_results using best $top_hit_type\n";
#    my $hmmdb_name     = $self->get_hmmdb_name();
#    my $blastdb_name   = $self->get_blastdb_name();
    my $query_seqs     = $self->get_sample_path( $sample_id ) . "/orfs/" . $orf_split;
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
	    $hit_map = $self->MRC::Run::parse_search_results( $search_results . "/" . $result_file, "hmmscan", $hit_map );
	}
	elsif( $algo eq "hmmsearch" ){
	    #use the database name to enable multiple searches against different databases
	    my $database_name = $self->get_hmmdb_name();
	    next unless( $result_file =~ m/$database_name/ );
	    print "processing $result_file\n";
	    $hit_map = $self->MRC::Run::parse_search_results( $search_results . "/" . $result_file, "hmmsearch", $hit_map );
	}
	elsif( $algo eq "blast" ){
	    #use the database name to enable multiple searches against different databases
	    my $database_name = $self->get_blastdb_name();
	    next unless( $result_file =~ m/$database_name/ );
	    #because blast doesn't give sequence lengths in report, need the input file to get seq lengths. add $query_seqs to function
	    $hit_map = $self->MRC::Run::parse_search_results( $search_results . "/" . $result_file, "blast", $hit_map, $query_seqs );
	}
	elsif( $algo eq "last" ){
	    #use the database name to enable multiple searches against different databases
	    my $database_name = $self->get_blastdb_name();
	    next unless( $result_file =~ m/$database_name/ );
	    #because blast doesn't give sequence lengths in report, need the input file to get seq lengths. add $query_seqs to function
	    $hit_map = $self->MRC::Run::parse_search_results( $search_results . "/" . $result_file, "last", $hit_map, $query_seqs );
	}
    }
    #now insert the data into the database
    my $is_strict = $self->is_strict_clustering();
    my $n_hits    = 0;
    my %orf_hits   = (); #a hash for bulk loading hits: orf_id -> famid, only works for strict clustering!
    #if we want best hit per metaread, use this block
    if( $top_hit_type eq "read" ){
	$hit_map = $self->MRC::Run::filter_hit_map_for_top_reads( $sample_id, $is_strict, $hit_map );	
    }
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
		$famid = $self->MRC::DB::get_famid_from_geneoid( $hit );
	    }
	    else{
		$famid = $hit;
	    }	
	    #because we have an index on sample_id and orf_alt_id, we can speed this up by passing sample id
	    my $orf_id = $self->MRC::DB::get_orf_from_alt_id( $orf_alt_id, $sample_id )->orf_id();
	    #need to ensure that this stores the raw values, need some upper limit thresholds, so maybe we need classification_id here. simpler to store anything with evalue < 1. Still not sure I want to store this in the DB.
	    #$self->MRC::DB::insert_search_result( $orf_id, $famid, $evalue, $score, $coverage );
	    
	    #let's try bulk loading to speed things up....
	    if( $self->multi_load() ){
		$orf_hits{$orf_id} = $famid; #currently only works for strict clustering!
	    }
	    #otherwise, the slow way...
	    else{
		$self->MRC::DB::insert_familymember_orf( $orf_id, $famid, $class_id );
	    }
	}
    }
    #bulk load here:
    if( $self->multi_load() ){
	print "Bulk loading classified reads into database\n";
	$self->MRC::DB::create_multi_familymemberss( $class_id, \%orf_hits);
    }
    print "Found and inserted $n_hits threshold passing search results into the database\n";
}

sub filter_hit_map_for_top_reads{
    my ( $self, $sample_id, $is_strict, $hit_map ) = @_;
    my $orfs = $self->MRC::DB::get_orfs_by_sample( $sample_id );
    my $read_map = {}; #stores best hit data for each read
    while( my $orf = $orfs->next() ){
	my $orf_alt_id = $orf->orf_alt_id();
	next unless( $hit_map->{$orf_alt_id}->{"has_hit"} );
	my $read_id = $orf->read_id();
	if( !defined( $read_map->{$read_id} ) ){
#	    print "adding orf $orf_alt_id\n";
	    $read_map->{$read_id}->{"target"}   = $orf_alt_id;
	    $read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
	    $read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
	    $read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
	}
	else{
	    print "$orf_alt_id is in hash...\n";
	    #for now, we'll simply sort on evalue, since they both pass coverage threshold
	    if( $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"} < $read_map->{$read_id}->{"evalue"} ){
		print "Updating $orf_alt_id\n";
		$read_map->{$read_id}->{"target"}   = $orf_alt_id;
		$read_map->{$read_id}->{"evalue"}   = $hit_map->{$orf_alt_id}->{$is_strict}->{"evalue"};
		$read_map->{$read_id}->{"coverage"} = $hit_map->{$orf_alt_id}->{$is_strict}->{"coverage"};
		$read_map->{$read_id}->{"score"}    = $hit_map->{$orf_alt_id}->{$is_strict}->{"score"};
	    }
	    else{
		print "Canceling $orf_alt_id\n";
		#get rid of the hit if it's not better than the current top for the read
		$hit_map->{$orf_alt_id}->{"has_hit"} = 0;
	    }
	}
    }
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
    print "classifying reads from $file\n";
    open( RES, "$file" ) || die "can't open $file for read: $!\n";    
    while(<RES>){
	chomp $_;
	if( $_ =~ m/^\#/ || $_ =~ m/^$/ ){
	    next;
	}
	my( $qid, $qlen, $tid, $tlen, $evalue, $score, $start, $stop );
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
	elsif( $type eq "hmmsearch" ){
	    #the fast parse way
	    if( $_ =~ m/(.*?)\s+(.*?)\s+(\d+?)\s+(\d+?)\s+(.*?)\s+(\d+?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s(.*)/ ){
		$qid    = $1;
		$qlen   = $3;
		$tid    = $4;
		$tlen   = $6;
		$evalue = $13; #this is dom_ievalue
		$score  = $8;  #this is dom score
		$start  = $20; #this is env_start
		$stop   = $21; #this is env_stop
	    }
	    else{
		warn( "couldn't parse results from $type file:\n$_\n");
		next;
	    }
	    #the old and slow way
	    if( 0 ){
		my @data = split( ' ', $_ );
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
	    }
	    else{
		warn( "couldn't parse results from $type file:\n$_\n");
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
	if( $type eq "last" ){
	    if( $_ =~ m/^(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)$/ ){
		$score  = $1;
		$tid    = $2;
		$qid    = $7;
		$start  = $8;
		$stop   = $start + $9;
		$qlen   = $11;
		$evalue = 0; #hacky - no evalue reported for last, but want to use the same code below
	    }
	    else{
		warn( "couldn't parse results from $type file:\n$_\n");
		next;
	    }
	}
	#calculate coverage from query perspective
	my $coverage  = 0;
	if( $stop > $start ){
	    my $len   = $stop - $start + 1; #coverage calc must include first base!
	    $coverage = $len / $qlen;
	}
	if( $start > $stop ){
	    my $len   = $start - $stop;
	    $coverage = $len / $qlen;
	}
	#does hit pass threshold?
	if( ( $evalue <= $t_evalue && $coverage >= $t_coverage ) ||
	    ( $type eq "last" && $score >= $t_score && $coverage >= $t_coverage ) ){
	    #is this the first hit for the query?
	    if( $hit_map->{$qid}->{"has_hit"} == 0 ){
		#note that we use is_strict to differentiate top hit clustering from fuzzy clustering w/in hash
		$hit_map->{$qid}->{$is_strict}->{"target"}   = $tid;
		$hit_map->{$qid}->{$is_strict}->{"evalue"}   = $evalue;
		$hit_map->{$qid}->{$is_strict}->{"coverage"} = $coverage;
		$hit_map->{$qid}->{$is_strict}->{"score"}    = $score;
		$hit_map->{$qid}->{"has_hit"} = 1;
	    }
	    elsif( $is_strict ){
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
	    }
	    else{
		#if stict clustering, we might have a pefect tie. Winner is the first one we find, so pass
		if( $is_strict ){
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
    my(  $header, $sequence );
    while( <FILE> ){
	chomp $_;
	if( eof ){
	    $sequence .= $_;
	    $seqlens{ $header } = length( $sequence );
	}
	if( $_ =~ m/\>(.*)/ ){
	    #process old sequence
	    if( defined( $header ) ){
		$seqlens{ $header } = length( $sequence );
	    }
	    $header   = $1;
	    $sequence = "";
	}
	else{
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
  return $self;
}

sub build_search_db{
    my $self        = shift;
    my $db_name     = shift; #name of db to use, if build, new db will be named this. check for dups
    my $split_size  = shift; #integer - how many hmms per split?
    my $force       = shift; #0/1 - force overwrite of old DB during compression.
    my $type        = shift; #blast/hmm
    my $reps_only   = shift; #0/1 - should we only use representative sequences in our sequence DB
    my $nr_db       = shift; #0/1 - should we use a non-redundant version of the DB (sequence DB only)
    if( !defined( $nr_db ) ){
	$nr_db = 0;
    }
    my $ffdb        = $self->get_ffdb();
    my $ref_ffdb    = $self->get_ref_ffdb();

    #where is the hmmdb going to go? each hmmdb has its own dir
    my $db_path;
    my $length      = 0;
    if( $type eq "hmm" ){
	$db_path = $self->MRC::DB::get_hmmdb_path();
    }
    elsif( $type eq "blast" ){
	$db_path = $self->MRC::DB::get_blastdb_path();
    }
    warn "Building $type DB $db_name, placing $split_size per split\n";
    #Have you built this DB already?
    if( -d $db_path && !($force) ){
	warn "You've already built an $type database with the name $db_name at $db_path. Please delete or overwrite by using the -f option.\n";
	exit(0);
    }
    #create the HMMdb dir that will hold our split hmmdbs
    $self->MRC::DB::build_db_ffdb( $db_path );
    #update the path to make it easier to build the split hmmdbs (e.g., points to an incomplete file name)
    #save the raw path for the database_length file when using blast
    my $raw_path = $db_path;
    $db_path = $db_path . $db_name;
    #constrain analysis to a set of families of interest
    my @families   = sort( @{ $self->get_family_subset() });
    my $n_fams     = @families;
    my $count      = 0;
    my @split      = (); #array of family HMMs/sequences (compressed)
    my $n_proc     = 0;
    my @fcis       = @{ $self->get_fcis() };
    FAM: foreach my $family( @families ){
	#find the HMM/sequences associated with the family (compressed)
	my $family_db;	
	if( $type eq "hmm" ){
	    foreach my $fci( @fcis ){
		my $path = $ref_ffdb . "fci_" . $fci . "/HMMs/" . $family . ".hmm.gz";
		if( -e $path ){
		    $family_db = $path;
		}
	    }
	    if( !defined( $family_db ) ){
		warn( "Can't find the HMM corresponding to family $family when using the following fci:\n" . join( "\t", @fcis, "\n" ) );
		exit(0);
	    }
	}
	elsif( $type eq "blast" ){
	    foreach my $fci( @fcis ){
		#short term hack for the merged fci blast directory for 0 and 1
		if( $fci == 0 ){
		    $fci = 1;
		}
		my $path = $ref_ffdb . "fci_" . $fci . "/seqs/" . $family . ".fa.gz";
		if( -e $path ){
		    $family_db = $path;
		    #do we only want rep sequences from big families?
		    if( $reps_only ){
			#first see if there is a reps file for the family
			my $reps_list_path = $ref_ffdb . "reps/fci_" . $fci . "/list/" . $family . ".mcl";
			#if so, see if we need to build the seq file
			if( -e $reps_list_path ){
			    #we add the .gz extension in the gzip command inside grab_seqs_from_lookup_list
			    my $reps_seq_path = $ref_ffdb . "reps/fci_" . $fci . "/seqs/" . $family . ".fa";
			    if( ! -e $reps_seq_path . ".gz" ){
				print "Building reps sequence file for $family\n";
				_grab_seqs_from_lookup_list( $reps_list_path, $family_db, $reps_seq_path );
				if( ! -e $reps_seq_path . ".gz" ){
				    warn( "Error grabbing representative sequences from $reps_list_path. Trying to place in $reps_seq_path.\n" );
				    exit(0);
				}
			    }
			    #add the .gz path because of the compression we use in grab_seqs_from_loookup_list
			    $family_db = $reps_seq_path . ".gz";
			}
		    }
		    #because of the fci hack, if we made it here, we don't want to rerun the above
#		    last;
		}
	    }
	    if( !defined( $family_db ) ){
		warn( "Can't find the BLAST database corresponding to family $family when using the following fci:\n" . join( "\t", @fcis, "\n" ) );
		exit(0);
	    }
#	    $family_db =  $ffdb . "/BLASTs/" . $family . ".fa.gz";
	    $length   += $self->MRC::Run::get_sequence_length_from_file( $family_db );
	}       
	push( @split, $family_db );
	$count++;
	#if we've hit our split size, process the split
	if( $count >= $split_size || $family == $families[-1] ){
	    $n_proc++;
	    #build the DB
	    my $split_db_path;
	    if( $type eq "hmm" ){
		$nr_db = 0; #Makes no sense to build a NR HMM DB
		$split_db_path = cat_db_split( $db_path, $n_proc, $ffdb, ".hmm", \@split, $nr_db );
	    }
	    elsif( $type eq "blast" ){
		$split_db_path = cat_db_split( $db_path, $n_proc, $ffdb, ".fa", \@split, $nr_db );
	    }
	    #we do want DBs to be gzipped 
	    gzip_file( $split_db_path );
	    #save the gzipped copy, remove the uncompressed copy
	    unlink( $split_db_path );
	    @split = ();
	    $count = 0;
	}
    }
    if( $type eq "blast" ){
	open( LEN, ">" . $raw_path . "/database_length.txt" ) || die "Can't open " . $raw_path . "/database_length.txt for write: $!\n";
	print LEN $length;
	close LEN;
    }
    warn "$type DB successfully built and compressed.\n";
    return $self;
}

sub cat_db_split{
    my $db_path      = shift;
    my $n_proc       = shift;
    my $ffdb         = shift;
    my $suffix       = shift;
    my $ra_families  = shift;
    my $nr_db        = shift;
    my @families     = @{ $ra_families };

    my $split_db_path = $db_path . "_" . $n_proc . $suffix;
    my $fh;
    open( $fh, ">>$split_db_path" ) || die "Can't open $split_db_path for write: $!\n";
    foreach my $family( @families ){
	#do we want a nonredundant version of the DB? 
	if( $nr_db ){
	    #make a temp file for the nr 
	    my $tmp = _build_nr_seq_db( $family );
	    cat( $tmp, $fh );
	    unlink( $tmp );
	}
	else{
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
    while( my $seq = $seqin->next_seq ){
	my $id       = $seq->display_id();
	my $sequence = $seq->seq();
	#if we haven't seen this seq before, print it out
	if( !defined( $dict->{$sequence} ) ){
	    $seqout->write_seq( $seq );
	    $dict->{$sequence}++;
	}
	else{
	    #print "Removing duplication sequence $id\n";
	}
    }
    return $family_nr;
}


sub _grab_seqs_from_lookup_list{
    my $seq_id_list = shift; #list of sequence ids to retain
    my $seq_file    = shift; #compressed sequence file
    my $out_seqs    = shift; #compressed retained sequences
    my $lookup      = {};
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
    while( my $seq = $seqs_in->next_seq() ){
	my $id = $seq->display_id();
	if( defined( $lookup->{$id} ) ){
	    $seqs_out->write_seq( $seq );
	}
    }
    gzip_file( $out_seqs );    
    unlink( $out_seqs );
}

#calculates total amount of sequence in a file
sub calculate_blast_db_length{
    my( $self ) = @_;
    my $length  = 0;
    my $db_name = $self->get_blastdb_name();
    my $db_path = $self->get_ffdb() . "/BLASTdbs/" . $db_name . "/";
    opendir( DIR, $db_path ) || die "Can't opendir $db_path for read: $!\n";
    my @files = readdir( DIR );
    closedir DIR;
    foreach my $file( @files ){
	next unless( $file =~ m/\.fa/ );
	my $filepath = $db_path . $file;
	$length += get_sequence_length_from_file( $filepath );
    }
    return $length
}

sub get_sequence_length_from_file{
    my( $self, $file ) = @_;
    my $length = 0;
    if( $file =~ m/\.gz/ ){
	open( FILE, "zmore $file |" ) || die "Can't open $file for read: $!\n"
    }
    else{
	open( FILE, "$file" ) || die "Can't open $file for read: $!\n";
    }
    while(<FILE>){
	chomp $_;
	next if( $_ =~ m/\>/ );
	$length += length( $_ );
    }
    close FILE;
    return $length;
}

sub gzip_file{
    my $file = shift;
    gzip $file => $file . ".gz"
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
    my $ref_ffdb   = $self->get_ref_ffdb();
    my @fcis       = @{ $self->get_fcis() };
    foreach my $family( @families ){
	#find the HMM associated with the family (compressed)
	my $family_hmm;
	foreach my $fci( @fcis ){
	    my $path = $ref_ffdb . "fci_" . $fci . "/HMMs/" . $family . ".hmm.gz";
	    if( -e $path ){
		$family_hmm = $path;
	    }
	}
	if( !defined( $family_hmm ) ){
	    warn( "Can't find the HMM corresponding to family $family when using the following fci:\n" . join( "\t", @fcis, "\n" ) );
	    exit(0);
	}
	push( @split, $family_hmm );
	$count++;
	#if we've hit our split size, process the split
	if( $count >= $split_size || $family == $families[-1] ){
	    $n_proc++;
	    #build the HMMdb
	    my $split_db_path = cat_db_split( $hmmdb_path, $n_proc, $ffdb, ".hmm", \@split );
	    #compress the HMMdb, a wrapper for hmmpress
	    compress_hmmdb( $split_db_path, $force );
	    @split = ();
	    $count = 0;
	}
    }
    warn "HMMdb successfully built and compressed.\n";
    return $self;
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
    my $self       = shift;
    my $waittime   = shift;
    my $logsdir    = shift;
    my $split_orfs = shift; #split orfs on stop? 1/0    
    my @sample_ids = @{ $self->get_sample_ids() };
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my @job_ids = ();
    #push translation scripts to remote server
    my $rscripts        = $self->get_remote_scripts();
    my $remote_handler  = $self->get_scripts_dir . "/remote/run_transeq_handler.pl";
    my $remote_script   = $self->get_scripts_dir . "/remote/run_transeq_array.sh";
    $self->MRC::Run::remote_transfer( $remote_handler, $self->get_remote_username . "@" . $self->get_remote_server . ":" . $rscripts, 'f' );
    $self->MRC::Run::remote_transfer( $remote_script,  $self->get_remote_username . "@" . $self->get_remote_server . ":" . $rscripts, 'f' );
    foreach my $sample_id( @sample_ids ){
	my $remote_input_dir  = $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/raw/";
	my $remote_output_dir =  $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
	my $remote_orfs = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
	my $local_orfs  = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
	if( $split_orfs ){
	    my $local_unsplit_orfs = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/unsplit_orfs/";
	    my $remote_unsplit_orfs = $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/unsplit_orfs/";
	    my $remote_cmd   = "\'perl " . $self->get_remote_scripts() . "run_transeq_handler.pl -i " . $remote_input_dir . " -o " . $remote_output_dir . " -w " . $waittime . 
		" -l " . $logsdir . " -s " . $self->get_remote_scripts() . " -u " . $remote_unsplit_orfs . " > ~/tmp.out\'";	
	    print( "translating reads, splitting orfs on stop codon\n" );       
	    $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
	    print( "translation complete, Transferring split and raw translated orfs\n" );
	    $self->MRC::Run::remote_transfer( $self->get_remote_username . "@" . $self->get_remote_server . ":" . $remote_unsplit_orfs, $local_unsplit_orfs, 'c' ); #the unsplit orfs
	    $self->MRC::Run::remote_transfer( $remote_orfs, $local_orfs, 'c' ); #the split orfs
	}
	else{ #no splitting of the orfs
	    my $remote_cmd = "\'perl " . $self->get_remote_scripts() . "run_transeq_handler.pl -i " . $remote_input_dir . " -o " . $remote_output_dir . " -w " . $waittime . 
		" -l " . $logsdir . " -s " . $self->get_remote_scripts() . "\'";	
	    print( "translating reads\n" );       
	    $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
	    print( "translation complete. Transferring orfs\n" );
	    $self->MRC::Run::remote_transfer( $remote_orfs, $local_orfs, 'c' );
	}
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

sub remote_transfer_search_db{
    my $self = shift;
    my $db_name = shift;
    my $type    = shift; #blast/hmm
    my $ffdb = $self->get_ffdb();
    my $db_dir;
    if( $type eq "hmm" ){
	$db_dir = $ffdb . "/HMMdbs/" . $db_name;
    }
    elsif( $type eq "blast" ){
	$db_dir = $ffdb . "/BLASTdbs/" . $db_name;
    }
    my $remote_dir;
    if( $type eq "hmm" ){
       $remote_dir = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb . "/HMMdbs/" . $db_name;
    }
    elsif( $type eq "blast" ){
       $remote_dir = $self->get_remote_username . "@" . $self->get_remote_server . ":" . $self->get_remote_ffdb . "/BLASTdbs/" . $db_name;
    }
    my $results = $self->MRC::Run::remote_transfer( $db_dir, $remote_dir, "directory" );
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

sub gunzip_remote_dbs{
    my( $self, $db_name, $type ) = @_;    
    my $ffdb        = $self->get_ffdb();
    my $db_dir;
    if( $type eq "hmm"){
	$db_dir = $ffdb . "/HMMdbs/" . $db_name;
    }
    elsif( $type eq "blast" ){
	$db_dir = $ffdb . "/BLASTdbs/" . $db_name;
    }
    opendir( DIR, $db_dir ) || die "Can't opendir $db_dir for read: $!\n";
    my @files = readdir( DIR );
    closedir DIR;
    foreach my $file( @files ){
	next unless( $file =~ m/\.gz/ );
	my $remote_db_file;
	if( $type eq "hmm" ){
	    $remote_db_file = $self->get_remote_ffdb . "/HMMdbs/" . $db_name . "/" . $file;
	}
	elsif( $type eq "blast" ){
	    $remote_db_file = $self->get_remote_ffdb . "/BLASTdbs/" . $db_name . "/" . $file;
	}
	$self->MRC::Run::gunzip_file_remote( $remote_db_file );
    }
    return $self;
}

sub format_remote_blast_dbs{
    my( $self, $r_script_path ) = @_;
    my $ffdb       = $self->get_ffdb();
    my $r_db_dir   = $self->get_remote_ffdb . "/BLASTdbs/" . $self->get_blastdb_name() . "/";
    my $connection = $self->get_remote_username . "@" . $self->get_remote_server;
    my $remote_cmd = "qsub -sync y $r_script_path $r_db_dir";
    my $results    = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd );
    return $self;
}

sub run_search_remote{
    my ( $self, $sample_id, $type, $waittime, $verbose ) = @_;
    my ( $r_script_path, $search_handler_log, $db_name, $remote_db_dir,
	 $remote_search_res_dir, $remote_query_dir, $remote_cmd );
    if( $type eq "blast" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/blast_handler";
	$r_script_path         = $self->get_remote_blast_script();
	$db_name               = $self->get_blastdb_name();
	$remote_db_dir         = $self->get_remote_ffdb . "/BLASTdbs/" . $db_name . "/";
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/blast/";
	$remote_query_dir      = $self->get_remote_sample_path( $sample_id ) . "/orfs/";	
    }
    if( $type eq "last" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/last_handler";
	$r_script_path         = $self->get_remote_last_script();
	$db_name               = $self->get_blastdb_name();
	$remote_db_dir         = $self->get_remote_ffdb . "/BLASTdbs/" . $db_name . "/";
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/last/";
	$remote_query_dir      = $self->get_remote_sample_path( $sample_id ) . "/orfs/";	
    }
    if( $type eq "hmmsearch" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/hmmsearch_handler";
	$r_script_path         = $self->get_remote_hmmsearch_script();
	$db_name               = $self->get_hmmdb_name();
	$remote_db_dir         = $self->get_remote_ffdb . "/HMMdbs/" . $db_name . "/";
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/hmmsearch/";
	$remote_query_dir      = $self->get_remote_sample_path( $sample_id ) . "/orfs/";	
    }
    if( $type eq "hmmscan" ){
	$search_handler_log    = $self->get_remote_project_log_dir() . "/hmmscan_handler";
	$r_script_path         = $self->get_remote_hmmscan_script();
	$db_name               = $self->get_hmmdb_name();
	$remote_db_dir         = $self->get_remote_ffdb . "/HMMdbs/" . $db_name . "/";
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/hmmscan/";
	$remote_query_dir      = $self->get_remote_sample_path( $sample_id ) . "/orfs/";
    }
    $remote_cmd   = "\'perl " . $self->get_remote_scripts() . "/run_remote_search_handler.pl -h $remote_db_dir " . 
	"-o $remote_search_res_dir -i $remote_query_dir -n $db_name -s $r_script_path -w $waittime > " . 
	$search_handler_log . ".out 2> " . $search_handler_log . ".err\'";
    print "$remote_cmd\n";
    my $connection            = $self->get_remote_username . "@" . $self->get_remote_server;
    my $results               = $self->MRC::Run::execute_ssh_cmd( $connection, $remote_cmd, $verbose );
    return $results;
}

sub get_remote_search_results{
    my( $self, $sample_id, $type ) = @_;
    my( $remote_search_res_dir, $local_search_res_dir );
    if( $type eq "blast" ){
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/blast/";
	$local_search_res_dir  = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/" . $sample_id . "/search_results/blast/";
    }
    elsif( $type eq "last" ){
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/last/";
	$local_search_res_dir  = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/" . $sample_id . "/search_results/last/";
    }
    elsif( $type eq "hmmsearch" ){
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/hmmsearch/";
	$local_search_res_dir  = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/" . $sample_id . "/search_results/hmmsearch/";
    }
    elsif( $type eq "hmmscan" ){
	$remote_search_res_dir = $self->get_remote_sample_path( $sample_id ) .  "/search_results/hmmscan/";
	$local_search_res_dir  = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/" . $sample_id . "/search_results/hmmscan/";
    }
    #recall, every sequence split has its own output dir to cut back on the number of files per directory
    my $in_orf_dir = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
    foreach my $in_orfs( @{ $self->MRC::DB::get_split_sequence_paths( $in_orf_dir, 0 ) } ){	
	my $split_orf_search_results = $remote_search_res_dir . $in_orfs;
	$self->MRC::Run::remote_transfer(  $self->get_remote_username . "@" . $self->get_remote_server . ":" . $split_orf_search_results, $local_search_res_dir, 'd' );
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

#not used in mrc_handler.pl
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
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/PCA_data_frame_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in build_classification_map: $!\n";    
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
    my $self     = shift;
    my $class_id = shift;
    #identify which families were uniquely found across the project
    my $hit_fams = {}; #hashref

    my $family_rs = $self->MRC::DB::get_families_with_orfs_by_project( $self->get_project_id(), $class_id );
    while( my $family = $family_rs->next() ){
	my $famid = $family->famid->famid();
	next if( defined( $hit_fams->{$famid} ) );
	$hit_fams->{$famid}++;
    }
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/project_richness_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_project_richness: $!\n";    
    print OUT join( "\t", "opf", "\n" );
    #dump the famids that were found in the project to the output
    foreach my $famid( keys( %$hit_fams ) ){
	print OUT "$famid\n";
    }
    close OUT;
    return $self;
}

sub calculate_sample_richness{
    my $self     = shift;
    my $class_id = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/sample_richness_" . $class_id . ".tab";
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
    my $self     = shift;
    my $class_id = shift;
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
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_project_relative_abundance: $!\n" ;    
    print OUT join( "\t", "opf", "r_abundance", "hits", "total_orfs", "\n" );
    #dump the famids that were found in the project to the output
    foreach my $famid( keys( %$hit_fams ) ){
	my $relative_abundance = $hit_fams->{$famid} / $total;
	print OUT join("\t", $famid, $relative_abundance, $hit_fams->{$famid}, $total, "\n");
    }
    close OUT;
    print "outfile created!\n";
    return $self;
}

#for each sample, divides total number of reads per OPF by all classified reads
sub calculate_sample_relative_abundance{
    my $self     = shift;
    my $class_id = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/sample_relative_abundance_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in calculate_sample_relative_abundance: $!\n";    
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
    return $self;
}

#maps project_id -> sample_id -> read_id -> orf_id -> famid
sub build_classification_map{
    my $self     = shift;
    my $class_id = shift;
    #create the outfile
    my $output = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/output/classification_map_" . $class_id . ".tab";
    open( OUT, ">$output" ) || die "Can't open $output for write in build_classification_map: $!\n";    
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
    return $self;
}

1;
