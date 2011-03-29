#!/usr/bin/perl -w

use strict;
use Getopt::Long;

#open Guillaume's family statistics file (data/famStats_allhits.txt) and produce a file that has one famid per line.
#this file will be used with the family_subset option when loading and processing projects in the MRC package.

my $famstats_file = "data/famStats_allhits.txt";
my $output        = ""; #no default because we don't want to accidentially overwrite

GetOptions(
    "i=s" => \$famstats_file,
    "o=s" => \$output,
    );

open( IN, $famstats_file ) || die "Can't open $famstats_file for read:$!\n";
open( OUT, ">$output") || die "Can't open $output for write: $!\n";

while( <IN> ){
    chomp $_;
    next if $_ =~ m/^\#/;
    my( $famid, $nseedhits, $nseedseqs, $recall, $nnonseedhits, $precision ) = split( "\t", $_ );
    if( $precision == 1 && $recall == 1 ){
	print OUT "$famid\n";
    }
}

close IN;
close OUT;
