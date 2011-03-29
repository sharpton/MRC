#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use IPC::System::Simple qw(capture $EXITVAL);

#simply a wrapper for transeq at the moment

my( $input, $output );

GetOptions(
    "i=s" => \$input,
    "o=s" => \$output,
    );

my @args     = ("$input", "$output", "-frame=6");
my $results  = capture( "transeq " . "@args" );
if( $EXITVAL != 0 ){
    warn("Error translating sequences in $input: $results\n");
    exit(0);
}
