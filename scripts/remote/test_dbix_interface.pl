#!/usr/bin/perl
#example of using DBIx::Class to query the IMG database

use strict;
use warnings;

use IMG::Schema;
use Data::Dumper;

my $username = $ARGV[0];
my $password = $ARGV[1];

#find out how many genomes are in the database
my $schema = IMG::Schema->connect( "DBI:mysql:IMG", $username, $password );
my $genomes = $schema->resultset('Genome');
print "There are ",$genomes->count() , " genomes.\n";

#Get a list of only Bacteria genomes
#print Dumper $genomes;
my $bacteria = $genomes->search({domain => 'Bacteria'});
print "There are ",$bacteria->count() , " bacteria genomes.\n";
