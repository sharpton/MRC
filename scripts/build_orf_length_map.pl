#!/usr/bin/perl -w

#use this to build a map of orf identifiers that are shorter than a specified length
#use the output to filter orfs that have been already searched by read length

my $project_dir = $ARGV[0];
my $min_length  = $ARGV[1]; #inclusive!
my $output      = $ARGV[2];

open( OUT, ">$output" ) || die;

opendir( PROJ, $project_dir ) || die( "Can't open $project_dir for read:$!\n" );
my @samples = readdir(PROJ);
closedir PROJ;


foreach my $sample( @samples ){
    next if( $sample =~ m/\./ || $sample =~ m/output/ || $sample =~ m/logs/ );
    my $split_orf_dir = $project_dir . "/" . $sample . "/orfs/";
    print "Processing $split_orf_dir\n";
    opendir( SPLIT, $split_orf_dir ) || die( "Can't open $split_orf_dir for read: $!\n" );
    my @orfs = readdir(SPLIT);
    closedir( SPLIT );
    foreach my $orf( @orfs ){
	next if( $orf =~ m/^\./ );
	my $file = $split_orf_dir . $orf;
	print "\tLooking in $file\n";
	open( ORF, $file ) || die "Can't open $file for read: $!\n";
	my $seqid = ();
	my $seq   = ();
	while(<ORF>){
	    chomp $_;
	    if( eof ){
		$seq .= $_;
		if( length( $seq ) < $min_length ){
		    print OUT $seqid . "\n";
		}       
	    }
	    if( $_ =~ m/\>(.*)/ ){
		if( defined( $seqid ) ){
		    if( length( $seq ) < $min_length ){
			print OUT $seqid . "\n";
		    }
		}
		$seqid = $1;
		$seq   = ();
	    }
	    else{
		$seq .= $_;
	    }
	}
    }
}

close OUT;
