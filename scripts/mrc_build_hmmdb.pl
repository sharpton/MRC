#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use MRC;
use IPC::System::Simple qw(capture $EXITVAL);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

my( $input, $output, $ffdb, $hmmdb );
my $family_subset_list = "";
my $n_splits = 1; #how many hmmdb splits should we produce?
my $check    = 0;
my $force    = 0; #force overwrite of old HMMdbs during compression.

GetOptions(
    "d=s" => \$ffdb,
    "sub:s" => \$family_subset_list,
    "h=s"   => \$hmmdb, #name of hmmdb to use, if build, new hmmdb will be named this. We check for duplicate HMMdbs!
    "n=i"   => \$n_splits,
    "f"     => \$force,
    );

#where is the hmmdb going to go?
my $hmmdb_path = $ffdb . "HMMdbs/" . $hmmdb;
#Have you built this HMMdb already?
if( -e $hmmdb_path . "_1" && !($force) ){
    warn "You've already built an HMMdb with the name $hmmdb at $hmmdb_path. Please delete or overwrite by using the -f option when running mrc_build_hmmdb.pl\n";
    die;
}

#Initialize the project
my $project = MRC->new();
#Get a DB connection 
#$project->set_dbi_connection( "DBI:mysql:IMG" );
#$project->set_username( $username );
#$project->set_password( $password );
#my $schema = $project->build_schema();

#constrain analysis to a set of families of interest
my @families   = sort( @{ $project->subset_families( $family_subset_list, $check ) } );
my $n_fams     = @families;
my $split_size = $n_fams / $n_splits;
print $split_size . "\n";
my $count      = 0;
my @split      = ();
my $n_proc     = 0;
foreach my $family( @families ){
    my $family_hmm = $ffdb . "/HMMs/" . $family . ".hmm.gz";
    push( @split, $family_hmm );
    $count++;
    print $count . "\n";
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



#######
# SUBROUTINES
#######

sub build_hmmdb{
    my $hmmdb_path = shift;
    my $n_proc     = shift;
    my $ffdb       = shift;
    my @families   = @{ $_[0] };

    my $split_db_path = $hmmdb_path . "_" . $n_proc;
    print "$split_db_path\n";
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
	warn("Error translating sequences in $input: $results\n");
	exit(0);
    }
    return $results;
}
