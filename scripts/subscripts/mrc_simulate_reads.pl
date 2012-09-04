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
my $outdir         = "";
my $format         = 'fasta';
my $check = 0; #Should we check that any user provided family_subset_ids are of the proper family_construction_ids?
my $force = 0;
my $n_genes_per_fam = 10;
my $out_basename = "";
my $n_reads = 100;
my $padlength = 100;
my $mean_read_len = 300;
my $stddev_read_len = 5;
my $mean_clone_len = 100;
my $stddev_clone_len = 5;
my $seq_type = 'RNA2DNA'; #For our purposes, same as running 'DNA', which is not yet implemented in MetaPASSAGE

my $metasim_src = "/home/sharpton/src/metasim/";

GetOptions(
    "u=s"   => \$username,
    "p=s"   => \$password,
    "sub:s" => \$family_subset_list,
    "n:i"   => \$nsamples,
    "o=s"   => \$outdir, #where will all output generated end up?
    "b=s"   => \$out_basename,  
    "f:s"   => \$format,
    "check" => \$check,
    "force" => \$force,
    );

#Initialize the project
my $analysis = MRC->new();
#Get a DB connection 
$analysis->set_dbi_connection( "DBI:mysql:IMG:lighthouse.ucsf.edu" );
$analysis->set_username( $username );
$analysis->set_password( $password );
$analysis->build_schema();

#constrain analysis to a set of families of interest
warn( "setting family subset list\n");
my @subset_famids = sort( @{ $analysis->set_family_subset( $family_subset_list, $check ) } );

#make sure there are more families in the subset list than we are trying to randomly sample
if( scalar( @subset_famids ) < $nsamples ){
    warn( "You are trying to uniquely sample more families than are in your subset list. Decrease your number of requested samples (-n)\n");
    die;
}

warn( "Making output directory\n");
#Initialize output directory
if( -d $outdir && !$force ){
    warn( "Directory exists at $outdir, will not overwrite without force!\n" );
    die;
}
elsif( -d $outdir && $force ){
    rmtree( $outdir ) || die "can't rmtree $outdir: $!\n";
    make_path( $outdir ) || die "can't make_path $outdir: $!\n";
}
else{
    make_path( $outdir ) || die "$!\n";
}
warn( "Output created\n");

#Obtain a random sampling of family ids from the DB
my $fams = $analysis->get_schema->resultset('Family');
my @rand_ids = @{ $analysis->MRC::Sim::rand_sample_famids( $nsamples ) };
my $nfams_grabbed = scalar(@rand_ids);
warn( "Randomly selected $nfams_grabbed families from the database\n");

#For each famid, get a random gene id associated with the family
my %sim = ();
foreach my $famid( @rand_ids ){
    warn( ".Processing family $famid for simulation\n");
    #create output subdir for the family directory structure
    my $famdir = $outdir . "/" . $famid . "/";
    if( -d $famdir && !$force ){
	warn( "Directory exists at $famdir, will not overwrite without force!\n" );
	die;
    }
    elsif( -d $famdir && $force ){
	rmtree( $famdir ) || die "can't rmtree:$!\n";
	make_path( $famdir ) || die "can't make_path: $!\n";
    }
    else{
	warn( "..creating an output subdirectory for family data in $famdir\n");
	make_path( $famdir );
    }
    my $full_len_seqout = $famdir . "source_seqs.fa";
    my $sim_outdir      = $famdir . "/sim_seqs/";
    warn( "..creating an output subdirectory for family simulation data in $sim_outdir\n");
    make_path( $sim_outdir );
    #randomly sample genes from the family using the DB
    my $familymembers   = $analysis->MRC::DB::get_fammembers_by_famid( $famid );
    my @geneids = @{ $analysis->MRC::Sim::get_rand_geneids( $familymembers, $n_genes_per_fam, $famid ) };
    my $ngeneids = scalar( @geneids );
    warn( "...Randomly selected $ngeneids genes from family\n");
    $sim{$famid} = \@geneids;    
    #Get gene sequences and print to file
    warn("...Printing source sequences to the file $full_len_seqout\n");
    my $source_seqout = Bio::SeqIO->new( -file => ">$full_len_seqout", -format => $format );
    foreach my $geneid( @geneids ){
	$analysis->MRC::Sim::print_gene( $geneid, $source_seqout );
    }
    warn("...Simulating reads\n");
    $analysis->MRC::Sim::run_meta_passage(
	$full_len_seqout,
	$sim_outdir,
	$out_basename,
	$n_reads,
	$padlength,
	$mean_read_len,
	$stddev_read_len,
	$mean_clone_len,
	$stddev_clone_len,
	$seq_type,
	$metasim_src
   );
   warn("..Simulation complete for family $famid\n");
   #will need to change this if you want the post MetaPASSAGE filtering output
   my $sim_reads_file = $sim_outdir . $out_basename .  "-pd-reads.fna"; 
   #impose our own filtering as per our needs
   my $filtered_reads_file = $analysis->MRC::Sim::filter_sim_reads( $sim_reads_file, $sim_outdir ); 
   my $prepped_reads_file = $analysis->MRC::Sim::pads_to_rand_noncoding( $filtered_reads_file, $sim_outdir );
   my $sample_file        = $analysis->MRC::Sim::convert_to_project_sample( $famid, $prepped_reads_file, $outdir, $out_basename ); 
}




