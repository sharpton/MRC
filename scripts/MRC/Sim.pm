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
	warn( "Not enough genes in family $famid to randomly sample $n_samples genes. Stopping\n" );
	die;
    }
    #randomly shuffle array, select the first $n_samples elements
    my @rand_ids = ( shuffle( @geneids ) )[0 .. $n_samples - 1];
    return \@rand_ids;
}

sub rand_sample_famids{
    my $self     = shift;
    my $nsamples = shift;
    my $ids = $self->get_subset_families();
    my %rands = ();
    my $nitems = @{ $ids };
    until( scalar( keys( %rands ) ) == $nsamples ){
	my $rand = int( rand( $nitems ) );
	$rands{$rand}++;
    }
    my @result = keys( %rands );
    return \@result;
}

#Make sure MetaPASSAGE is part of your path
sub run_meta_passage{
    my $self    = shift;
    my $inseqls = shift;
    my $out_dir = shift;
    my $out_basename = shift;
    my $n_reads      = shift;
    my $padlength    = shift;
    my $mean_read_len = shift
    my $metasim_src   = shift; #directory to location of MetaSim remove at a later date
    my @args     = ("-i $inseqs", "--out_dir $out_dir", "--out_basename $out_basename", "-j", "-m -1", "--pad $padlength", "--sim", "--filter", "--num_reads $n_reads", "--mean_clone_len $mean_read_len", "--metasim_path $metasim_src" );
    my $results  = capture( "perl MetaPASSAGE.pl" . "@args" );
    if( $EXITVAL != 0 ){
	warn("Error running MetaPASSAGE in run_meta_passage: $results\n");
	exit(0);
    }
    return $self;
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

1;
