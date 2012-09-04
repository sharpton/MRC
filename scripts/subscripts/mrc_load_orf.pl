#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use Bio::SeqIO;
use MRC;

my( $in_orfs, $project_id, $username, $password );

GetOptions(
    "i=s" => \$in_orfs,
    "n=i" => \$project_id,
    "u=s" => \$username,
    "p=s" => \$password,
    );

#Initialize the project
my $project = MRC->new();
#Get a DB connection 
$project->set_dbi_connection( "DBI:mysql:IMG" );
$project->set_username( $username );
$project->set_password( $password );
my $schema  = $project->build_schema();
#set the project id
$project->set_project_id( $project_id );
#get the sample ids associated with project. maybe unnecessary
my $samples = $project->get_samples_by_project_id();
my %sample_lookup = ();
while( my $sample = $samples->next() ){
    my $sid = $sample->sample_id();
    my $alt_id = $sample->sample_alt_id();
    $sample_lookup{$sid} = $alt_id;
}
#now let's get our hands dirty with the orfs
#each sample has its own orf file sitting in the ffdb
my $orfs = Bio::SeqIO->new( -file => $in_orfs, -format => 'fasta' );
my $count = 0;
while( my $orf = $orfs->next_seq() ){
    my $orf_alt_id = $orf->display_id();
    my $read_alt_id    = parse_orf_id( $orf_alt_id, "transeq" );
    #this is currently an inefficient method, but will work for now. need to use sample_id in file name so that 
    #we can assume sample_id and not have to check per read!
    $project->load_orf( $orf_alt_id, $read_alt_id, \%sample_lookup );
    $count++;			
}
print "Added $count orfs to the DB\n";


