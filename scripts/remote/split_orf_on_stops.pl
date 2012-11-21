#!/usr/bin/perl -w

use strict;
use Getopt::Long;

my( $inseqs, $outseqs );
my $seq_len_min = 10; #in AA length; 
GetOptions(
    "i=s" => \$inseqs,
    "o=s" => \$outseqs,
    "l:i" => \$seq_len_min,
    );

open( IN,  $inseqs )     || die "Can't open $inseqs for read: $!\n";
open( OUT, ">$outseqs" ) || die "Can't open $outseqs for write: $!\n";
my $out = *OUT;
my $infile = 0;
my $header = ();
my $seq    = ();
while( <IN> ){
    chomp $_;
    if( $_ =~ m/\>/ ){
	if( $infile ){
	    process_seq( $header, $seq, $seq_len_min, $out );
	    $header = get_header( $_ );
	    $seq    = ();
	}
	else{
	    $header = get_header( $_ );
	    $infile = 1;
	}
    }
    else{
	$seq = $seq . $_;
    }
}
close IN;
close OUT;

#if there are extra characters in the header, such as a description, we don't want them when we modify
#the sequence id
sub get_header{
    my $header = shift;
    if( $header =~ m/^(.*?)\s/ ){
	$header = $1;
    }
    return $header;
}

sub process_seq{
    my( $header, $sequence, $seq_len_min, $out ) = @_;
    my $count = 1;
    if( $sequence =~ m/\*/ ){
	my @seqs  = split( "\\*", $sequence );
	foreach my $seq( @seqs ){
	    if( length( $seq ) < $seq_len_min ){
		next;
	    }
	    my $id = $header . "_" . $count;
	    print $out "$id\n$seq\n";
	    $count++;
	}
    }
    #no stops, but still want consistant format
    else{
	my $id = $header . "_" . $count;
	print $out "$id\n$sequence\n";       
    }
}
