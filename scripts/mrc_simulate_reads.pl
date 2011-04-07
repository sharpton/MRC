#!/usr/bin/perl -w

use strict;
use MRC;
use MRC::Run;
use MRC::DB;
use MRC::Sim;
use Getopt::Long;
use Bio::SeqIO;
use File::Path qw(make_path rmtree);
use Data::Dumper;

my $family_subset_list; #path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction
my $username       = "";
my $password       = "";
my $nsamples       = 10;
my $output         = "";
my $format         = 'fasta';
my $check = 0; #Should we check that any user provided family_subset_ids are of the proper family_construction_ids?
my $force = 0;
my $n_genes_per_family = 10;

GetOptions(
    "u=s" => \$username,
    "p=s" => \$password,
    "sub:s" => \$family_subset_list,
    "n=i"   => \$nsamples,
    "o=s"   => \$outdir, #where will all output generated end up?
    "f:s"   => \$format,
    "check" => \$check,
    "force" => \$force,
    );

#Initialize the project
my $analysis = MRC->new();
#Get a DB connection 
$analysis->set_dbi_connection( "DBI:mysql:IMG" );
$analysis->set_username( $username );
$analysis->set_password( $password );
$analysis->build_schema();

#constrain analysis to a set of families of interest
my @subset_famids = sort( @{ $analysis->set_family_subset( $family_subset_list, $check ) } );

#Initialize output directory
if( -d $outdir && !$force ){
    warn( "Directory exists at $outdir, will not overwrite without force!\n" );
}
else{
    make_path( $output );
}

#Obtain a random sampling of family ids from the DB
my $fams = $schema->resultset('Family');
my @rand_ids = @{ $analysis->MRC::Sim::rand_sample_famids( $nsamples ) };

#For each famid, get a random gene id associated with the family
%sim = ();
foreach my $famid( @rand_ids ){
    #create output subdir for the family directory structure
    my $famdir = $outdir . "/" . $famid . "/";
    if( -d $famdir && !$force ){
	warn( "Directory exists at $famdir, will not overwrite without force!\n" );
    }
    else{
	make_path( $famdir );
    }
    my $full_len_seqout = $famdir . "source_seqs.fa";
    my $sim_outdir      = $famdir . "/sim_seqs/";
    make_path( $sim_outdir );
    #randomly sample genes from the family using the DB
    my $genes   = $analysis->MRC::DB::get_genes_by_famid( $famid );
    my @geneids = @{ $analysis->MRC::Sim::get_rand_geneids( $genes, $n_genes_per_fam, $famid ) };
    $sim{$famid} = \@geneids;    
    #Get gene sequences and print to file
    my $source_seqout = Bio::SeqIO->new( -file => ">$output", -format => $format );
    foreach my $geneid( @geneids ){
	$analysis->MRC::Sim::print_gene( $geneid, $source_seqout );
    }
    $analysis->MRC::Sim::run_meta_passage(
	$self,
	$source_seqout,
	$out_dir,
	$out_basename,
	$n_reads,
	$padlength,
	$mean_read_len,
	$metasim_src,
   );
}



