#!/usr/bin/perl -w

use strict;
use MRC;
use Getopt::Long;
use Data::Dumper;
use Bio::SeqIO;
use File::Basename;

#mrc_load_project.pl - load a metagenomic project into the IMG database.

#A project is divided into one or more samples, each of which contain sequences. There are at least two common formats
#that we will need to be capable of loading: concatenated and partitioned. Concatenated projects have all samples
#in a single sequence file and each sequence contains an identifier that links it to a particular sample. Partitioned
#projects are those in which all each sample has a distinct sequence file and the file name (and possibly the sequence 
#metadata) contains the sample specific information. We will add to this list as we encounter additional project types.
#Where possible, we will simply build converters that reformat the initial data into one of the above two project formats.

my $flat_data_path = ""; #point to the master directory path for the flat file database (aligns and HMMs)
my $scripts_path   = ""; #point to the location of the MRC scripts
my $project_file   = ""; #where is the project files to be processed?
my $family_subset_list = ""; #path to a file that lists (one per line) which family ids you want to include. Defaults to all. Will probably come back and make this a seperate familyconstruction
my $username       = "";
my $password       = "";
my $check          = 0;

GetOptions(
    "d=s" => \$flat_data_path,
    "s=s" => \$scripts_path,
    "i=s" => \$project_file,
    "u=s" => \$username,
    "p=s" => \$password,
    "sub:s" => \$family_subset_list,
    );

#Initialize the project
my $project = MRC->new();
#Get a DB connection 
$project->set_dbi_connection( "DBI:mysql:IMG" );
$project->set_username( $username );
$project->set_password( $password );
my $schema  = $project->build_schema();

#constrain analysis to a set of families of interest
$project->set_family_subset( $family_subset_list, $check );

#Grab the samples associated with the project
if( -f $project_file ){
    #Single file, concatenated project. Build later. Hint:
    #my %samples = %{ get_cat_samples( $project_name ) };
}
if( -d $project_file ){
    #Partitioned samples project
    #get the samples associated with project. a project description can be left in 
    #DESCRIPT.txt
    my %samples = %{ get_part_samples( $project_file ) };
    #come back and add a check that ensures sequences associated with samples
    #are of the proper format. We should check data before loading.
    
    #Load Data. Project id becomes a project var in load_project
    my $text = $samples{"text"};
    
    $project->load_project( $project_file, $text, \%samples );
}

my $projects = $schema->resultset('Project');
print "There are ",$projects->count() , " projects.\n";

