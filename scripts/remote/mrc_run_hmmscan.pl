#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use IPC::System::Simple qw(capture $EXITVAL);

#simply a wrapper for hmmscan at the moment

my( $inseqs, $output, $hmmdb );

GetOptions(
    "i=s" => \$inseqs,
    "o=s" => \$output,
    "d=s" => \$hmmdb
    );

#need to hook orf file up to the ffdb and integrate here
my $inseq_path   = $inseqs;
#Run hmmscan
my @args     = ("$hmmdb", "$inseq_path", "> $output");
my $results  = capture( "hmmscan " . "@args" );
if( $EXITVAL != 0 ){
    warn("Error translating sequences in $inseqs: $results\n");
    exit(0);
}
