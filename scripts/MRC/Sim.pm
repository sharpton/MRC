#!/usr/bin/perl -w

#MRC::Sim.pm - MRC simulation methods handler
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

package MRC::Sim;

use strict;
use IMG::Schema;
use Data::Dumper;
use File::Basename;
use IPC::System::Simple qw(capture $EXITVAL);
use List::Util qw(shuffle);
use File::Copy;

sub get_rand_geneid{
    my $self  = shift;
    my $famid = shift;
    my $schema = $self->{"schema"};
    my $fm_rs = $schema->resultset("Familymember");
    my $fammembers = $fm_rs->search({ famid => $famid });
    my $rand = int( rand( $fammembers->count() ) );
    my @geneids = $fammembers->get_column('gene_oid')->all();
    my $rand_id = $geneids[$rand-1];
    return $rand_id;
}

sub get_rand_geneids{
    my $self      = shift;
    my $genes     = shift; #a DBIx Resultset
    my $n_samples = shift;
    my $famid     = shift; #only need for the warning below.
    my @geneids  = $genes->get_column('gene_oid')->all();
    #what if family is small. need a way to automate through this (change number of samples?)
    if( scalar( @geneids ) < $n_samples ){
	warn( "Not enough genes in family $famid to randomly sample $n_samples genes. Taking all family members." );
	return \@geneids;
    }
    #randomly shuffle array, select the first $n_samples elements
    warn( "Shuffling and selecting genes\n");
    my @rand_ids = ( shuffle( @geneids ) )[0 .. $n_samples - 1];
    return \@rand_ids;
}

sub rand_sample_famids{
    my $self     = shift;
    my $nsamples = shift;
    my @ids = @{ $self->get_subset_famids() };
    my %rands = ();
    my $nitems = @ids;
    until( scalar( keys( %rands ) ) == $nsamples ){
	my $rand = int( rand( $nitems ) );
	$rands{$ids[$rand]}++;
    }
    my @result = keys( %rands );
    return \@result;
}

#Make sure MetaPASSAGE is part of your path
sub run_meta_passage{
    my $self    = shift;
    my $inseqs = shift;
    my $out_dir = shift;
    my $out_basename = shift;
    my $n_reads      = shift;
    my $padlength    = shift;
    my $mean_read_len = shift;
    my $stddev_read_len = shift;
    my $mean_clone_len = shift;
    my $stddev_clone_len = shift;
    my $seq_type = shift;
    my $metasim_src   = shift; #directory to location of MetaSim remove at a later date
    my $drop_length   = shift;
    my $blast_translate  = shift; #optional, point to blast database of the input sim sequences. will also build db under the hood
    #NOTE: we don't pass a -j or --sim option. we'll always need those options here
    #NOTE: We don't pass a -q option here, as we'll always generate more reads than
    #we need and then use an indpendent method to conduct our own filtering.
    my @args = ();
    if( $blast_translate ){
	@args     = ("-i $inseqs", "--out_dir $out_dir", "--out_basename $out_basename", "-j", "-m -1", "--pad $padlength", "--sim",  "--num_reads $n_reads", "--mean_clone_len $mean_clone_len", "--stddev_clone_len $stddev_clone_len", "--mean_read_len $mean_read_len", "--stddev_read_len $stddev_read_len", "--type $seq_type", "--metasim_path $metasim_src", "-x", "-y $blast_translate", "--drop_len $drop_length" );
    }
    else{
	@args     = ("-i $inseqs", "--out_dir $out_dir", "--out_basename $out_basename", "-j", "-m -1", "--pad $padlength", "--sim",  "--num_reads $n_reads", "--mean_clone_len $mean_clone_len", "--stddev_clone_len $stddev_clone_len", "--mean_read_len $mean_read_len", "--stddev_read_len $stddev_read_len", "--type $seq_type", "--metasim_path $metasim_src", "--drop_len $drop_length");
    }
    warn( "MetaPASSAGE.pl " . "@args" );
    my $results  = capture( "MetaPASSAGE.pl " . "@args" );
    if( $EXITVAL != 0 ){
	warn("Error running MetaPASSAGE in run_meta_passage: $results\n");
	exit(0);
    }
    return $self;
}

sub filter_sim_reads{
    my $self = shift;
    my $sim_reads_file = shift;
    my $read_len_cut = 80;
    my $filtered_reads_file = ();
    my @suffixes = ( ".fna", ".fa" );
    my ( $basename, $directory, $suffix ) = fileparse( $sim_reads_file, @suffixes );
    $filtered_reads_file = $directory . "/" . $basename . "-f.fa";
    my $seqout = Bio::SeqIO->new( -file => ">$filtered_reads_file", -format => 'fasta' );
    my $seqin  = Bio::SeqIO->new( -file => "$sim_reads_file", -format => 'fasta' );
    my %sources = ();
    warn( "Filtering simulated reads\n");
    #grab a single read per source that passes desired criteria 
    while( my $seq = $seqin->next_seq() ){	
	my $readid = $seq->display_id();
        #parse the source identifier from the read header
	my $source = ();
	my $desc = $seq->description();	
	if( $desc =~ m/SOURCE_1\=\"\d+\s(\w+)\"/ ){
	    $source = $1;
	}
	else{
	    warn( "Can't parse source from $desc!\n" );
	    next;
	}
	#only want one read per source (for now)
	next if( exists( $sources{$source} ) && $sources{$source} > 1 );
	#we haven't retained a read from this source yet
	$sources{$source} = 0;
	#check that the non-padded part of the read is longer than the threshold
	my $no_pad = strip_pads( $seq->seq );
	my $no_pad_len = length( $no_pad );
	next if( $no_pad_len < $read_len_cut );
	#update the id such that source name is appended to read id
	my $id = $seq->display_id();
	$id = $id . "_" . $source;
	$seq->display_id( $id );
	#print the read and set the source to be skipped next round
	warn( "Grabbing sequence $id for source $source:\n" );
	$seqout->write_seq( $seq );
	$sources{$source}++;
    }
    return $filtered_reads_file;
}

sub strip_pads{
    my $sequence = shift;
    $sequence =~ s/^N+//g;
    $sequence =~ s/N+$//g;
    return $sequence;
}

sub pads_to_rand_noncoding{
    my $self = shift;
    my $filtered_reads_file = shift;
    my $sim_outdir = shift;
    my @suffixes = ( ".fna", ".fa" );
    my ( $basename, $directory, $suffix ) = fileparse( $filtered_reads_file, @suffixes );
    my $prepped_reads_file = $directory . "/" . $basename . "-prep.fa";
    my $seqout = Bio::SeqIO->new( -file => ">$prepped_reads_file", -format => 'fasta' );
    my $seqin  = Bio::SeqIO->new( -file => $filtered_reads_file, -format => 'fasta' );
    warn( "Replacing pads with random nucleotide characters\n");
    while( my $seq = $seqin->next_seq() ){
	my $sequence = $seq->seq();
	#replace each N with a random A|T|G|C. See
	#http://tinyurl.com/4xq4wa6
	my ( $fiveprime, $threeprime, $tempseq );
	if( $sequence =~ m/^(N+)(.*)/ ){
	    $fiveprime = $1;
	    $tempseq   = $2;
	    my $fplen  = length( $fiveprime );
	    my $nc_pad = generate_random_noncoding_str( $fplen );
	    $sequence  = $nc_pad . $tempseq;
	}
	if( $sequence =~ m/^(.*?)(N+)$/ ){
	    $tempseq    = $1;
	    $threeprime = $2;
	    my $tplen      = length( $threeprime );
	    my $nc_pad  = generate_random_noncoding_str( $tplen );
	    $sequence   = $tempseq . $nc_pad;	    
	}		
	$seq->seq( $sequence );
	$seqout->write_seq( $seq );	
    }
    return $prepped_reads_file;
}

sub generate_random_noncoding_str{
    my $seqlen = shift;
    my @chars = ( "A", "T", "G", "C");
    my $rand_str;
    foreach ( 1..$seqlen){
	$rand_str .= $chars[rand @chars];
    }
    return $rand_str;
}

sub convert_to_project_sample{
    my $self       = shift;
    my $famid      = shift;
    my $reads_file = shift;
    my $outdir     = shift; #where the sample file will be placed
    my $out_basename = shift;
    my $cp_file = $outdir . "/" . $out_basename . "_" . $famid . ".fa";
    copy( $reads_file, $cp_file ) || die "Copy of $reads_file failed: $!\n";
    return $cp_file;
}

#we will convert a gene row into a three element hash: the unqiue gene_oid key, the protein id, and the nucleotide sequence. the same
#proteins may be in the DB more than once, so we will track genes by their gene_oid (this will be the bioperl seq->id() tag)

sub print_gene{
    my ( $self, $geneid, $seqout ) = @_;
    my $gene = $self->MRC::DB::get_gene_by_id( $geneid );
    my $sequence = $gene->get_column('dna');
    if( $sequence !~ m/(A|a|T|t|G|g|C|c)/ ){
	return 0;
    }
    my $desc     = $gene->get_column('protein_id');
    my $seq = Bio::Seq->new( -seq        => $sequence,
			     -alphabet   => 'dna',
			     -display_id => $geneid,
			     -desc       => $desc
	);
    my $length = $seq->length();
    $seqout->write_seq( $seq );    
    return $length;
}

sub print_protein{
    my ( $self, $geneid, $seqout ) = @_;
    my $gene = $self->MRC::DB::get_gene_by_id( $geneid );
    my $sequence = $gene->get_column('protein');
    my $desc     = $gene->get_column('protein_id');
    my $seq = Bio::Seq->new( -seq        => $sequence,
			     -alphabet   => 'protein',
			     -display_id => $geneid,
			     -desc       => $desc
	);
    $seqout->write_seq( $seq );
}


#used to determine how original simulated reads are associated with families. Reads were produced
#using the script mrc_simulate_reads.pl.
#returns hash that looks like the following:
#$standards{$read_id}->{$famid} = 1;

sub map_read_ids_to_famids{
    my $projectdir = shift;
    my $basename   = shift;
    my %map = ();
    opendir( PROJ, "$projectdir" ) || die "can't opendir $projectdir for read: $!\n";
    my @files = readdir(PROJ);
    closedir PROJ;
    foreach my $file( @files ){
	next if $file =~ m/^\./;
	next if ( -d $projectdir . "/" . $file );
	if( $file =~ m/$basename\_(\d+)/ ){
	    my $famid = $1;
	    my $seqin = Bio::SeqIO->new( -file => $projectdir . "/" . $file, -format => 'fasta' );
	    while( my $seq = $seqin->next_seq() ){
		my $id = $seq->display_id();
		$map{$id}->{$famid}++;
	    }
	}
	else{
	    warn( "Can't parse family identifier from " . $projectdir . "/" . $file . "\n" );
	    exit(0);
	}	
    }
    return \%map;
}



1;
