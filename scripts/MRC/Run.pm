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
use Bio::SearchIO;

sub clean_project{
    my $self       = shift;
    my $project_id = shift;
    my $samples    = $self->MRC::DB::get_samples_by_project_id( $project_id );
    while( my $sample = $samples->next() ){
	my $sample_id = $sample->sample_id();
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
sub get_part_samples{
    my $self = shift;
    my $path = shift;
    my @suffixes = (".fa");
    my %samples =();    
    #open the directory and get the sample names and paths, 
    opendir( PROJ, $path ) || die "Can't open the directory $path for read: $!\n";
    my @files = readdir( PROJ );
    closedir( PROJ );
    foreach my $file( @files ){
	next if $file =~ m/^\./;
	#see if there's a description file
	if( $file =~ m/DESCRIPT\.txt/ ){
	    open( TXT, $file ) || die "Can't open project description file $file for read: $!. Project is $path.\n";
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
    $self->set_samples( \%samples );
    return $self;
}

sub load_project{
    my $self    = shift;
    my $path    = shift;
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
    $self->MRC::DB::build_sample_ffdb();
    warn( "Project $pid successfully loaded!\n" );
    return $self;
}

sub load_samples{
    my $self   = shift;
    my %samples = %{ $self->get_samples() };
    my $samps = scalar( keys(%samples) );
    warn( "Processing $samps samples associated with project $self->get_project_id() \n" );
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
    warn( "All samples associated with project $self->get_project_id() are loaded\n" );
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
    #Run hmmscan
    my @args     = ("$hmmdb", "$inseqs", "> $output");
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

#we will convert a gene row into a three element hash: the unqiue gene_oid key, the protein id, and the nucleotide sequence. the same
#proteins may be in the DB more than once, so we will track genes by their gene_oid (this will be the bioperl seq->id() tag)
sub print_gene{
    my ( $self, $geneid, $seqout ) = @_;
    my $gene = $self->MRC::DB::get_gene_by_id( $geneid );
    my $sequence = $gene->get_column('dna');
    my $desc     = $gene->get_column('protein_id');
    my $seq = Bio::Seq->new( -seq        => $sequence,
			     -alphabet   => 'dna',
			     -display_id => $geneid,
			     -desc       => $desc
	);
    $seqout->write_seq( $seq );
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
sub classify_reads{
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
    my $n_splits = shift; #integer - how many hmmdb splits should we produce?
    my $force    = shift; #0/1 - force overwrite of old HMMdbs during compression.
    my $ffdb     = $self->get_ffdb();
    #where is the hmmdb going to go? each hmmdb has its own dir
    my $hmmdb_path = $ffdb . "HMMdbs/" . $hmmdb . "/";
    warn "Building HMMdb $hmmdb, splitting into $n_splits parts.\n";
    #Have you built this HMMdb already?
    if( -d $hmmdb_path && !($force) ){
	warn "You've already built an HMMdb with the name $hmmdb at $hmmdb_path. Please delete or overwrite by using the -f option when running mrc_build_hmmdb.pl\n";
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
	    my $split_db_path = build_hmmdb( $hmmdb_path, $n_proc, $ffdb, \@split );
	    #compress the HMMdb, a wrapper for hmmpress
	    compress_hmmdb( $split_db_path, $force );
	    @split = ();
	    $count = 0;
	}
    }
    warn "HMMdb successfully built and compressed.\n";
    return $self;
}

sub build_hmmdb{
    my $hmmdb_path = shift;
    my $n_proc     = shift;
    my $ffdb       = shift;
    my @families   = @{ $_[0] };
    my $split_db_path = $hmmdb_path . "_" . $n_proc;
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

1;
