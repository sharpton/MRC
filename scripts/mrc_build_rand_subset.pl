#!/usr/bin/perl -w

use strict;
use MRC;
use MRC::Run;
use MRC::DB;
use MRC::Sim;
use Getopt::Long;
use Bio::SeqIO;
use Data::Dumper;

my $family_subset_list; #path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction
my $username       = "";
my $password       = "";
my $nsamples       = 10;
my $output         = "";
my $format         = 'fasta';
my $check = 0; #Should we check that any user provided family_subset_ids are of the proper family_construction_ids?

GetOptions(
    "u=s" => \$username,
    "p=s" => \$password,
    "sub:s" => \$family_subset_list,
    "n=i"   => \$nsamples,
    "o=s"   => \$output,
    "f:s"   => \$format,
    "check" => \$check,
    );

#Initialize the project
my $project = MRC->new();
#Get a DB connection 
$project->set_dbi_connection( "DBI:mysql:IMG" );
$project->set_username( $username );
$project->set_password( $password );
my $schema  = $project->build_schema();

#constrain analysis to a set of families of interest
my @subset_famids = sort( @{ $project->set_family_subset( $family_subset_list, $check ) } );

#Obtain a random sampling of family ids from the DB
my $fams = $schema->resultset('Family');
my @rand_ids = ();
@rand_ids = @{ rand_sample_famids( $nsamples, \@subset_famids, $schema ) };

#For each famid, get a random gene id associated with the family
my @geneids = ();
foreach my $famid( @rand_ids ){
    my $geneid = $project->MRC::Sim::get_rand_geneid( $famid );
    push( @geneids, $geneid );
}

#Get gene sequences and print to file
my $seqout = Bio::SeqIO->new( -file => ">$output", -format => $format );
foreach my $geneid( @geneids ){
    $project->MRC::Run::print_gene( $geneid, $seqout );
}

####################
# SUBROUTINES
####################

sub rand_sample_famids{
    my ( $nsamples, $ids, $schema ) = @_;
    my %rands = ();
    my $nitems = @{ $ids };
    until( scalar( keys( %rands ) ) == $nsamples ){
	my $rand = int( rand( $nitems ) );
	$rands{$rand}++;
    }
    my @result = keys( %rands );
    return \@result;
}
