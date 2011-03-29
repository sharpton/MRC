#!/usr/bin/perl -w

#MRC::Sim.pm - MRC simulation methods handler

package MRC::Sim;

use strict;
use IMG::Schema;
use Data::Dumper;
use File::Basename;

sub get_rand_geneid{
    my $self  = shift;
    my $famid = shift;
    my $schema = $self->{"schema"};
    my $fm_rs = $schema->resultset("Familymember");
    my $fammembers = $fm_rs->search({ famid => $famid });
    my $rand = int( rand( $fammembers->count() ) );
    my @geneids = $fammembers->get_column('gene_oid')->all();
    my $rand_id = $geneids[$rand-1];
    return $rand_id;
}

1;
