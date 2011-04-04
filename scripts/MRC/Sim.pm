#!/usr/bin/perl -w

#MRC::Sim.pm - MRC simulation methods handler
#Copyright (C) 2011  Thomas J. Sharpton 
#author contact: thomas.sharpton@gladstone.ucsf.edu
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#    
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#    
#You should have received a copy of the GNU General Public License
#along with this program (see LICENSE.txt).  If not, see 
#<http://www.gnu.org/licenses/>.

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
