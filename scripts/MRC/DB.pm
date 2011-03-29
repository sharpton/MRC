#!/usr/bin/perl -w

#MRC::DB.pm - Database Interfacer

package MRC::DB;

use strict;
use IMG::Schema;
use Data::Dumper;
use File::Basename;
use File::Copy;

#returns samples result set
sub get_samples_by_project_id{
    my $self    = shift;
    my $samples = $self->{"schema"}->resultset("Sample")->search(
	{
	    project_id => $self->{"project_id"},
	}
    );
    return $samples;
}

sub create_project{
    my $self = shift;
    my $name = shift;
    my $text = shift;
    my $proj_rs = $self->{"schema"}->resultset("Project");
    my $inserted = $proj_rs->create(
	{
	    name => $name,
	    description => $text,
	}
	);
    return $inserted;
}

sub create_sample{
    my $self = shift;
    my $sample_name = shift;
    my $project_id = shift;    
    my $proj_rs = $self->{"schema"}->resultset("Sample");
    my $inserted = $proj_rs->create(
	{
	    sample_alt_id => $sample_name,
	    project_id => $project_id,
	}
	);
    return $inserted;
}

sub create_metaread{
    my $self = shift;
    my $read_name = shift;
    my $sample_id = shift;
    my $proj_rs = $self->{"schema"}->resultset("Metaread");
    my $inserted = $proj_rs->create(
	{
	    sample_id => $sample_id,
	    read_alt_id => $read_name,
	}
	);
    return $inserted;
}

sub insert_orf{
    my $self       = shift;
    my $orf_alt_id = shift;
    my $read_id    = shift;
    my $sample_id  = shift;
    my $orf = $self->{"schema"}->resultset("Orf")->create(
	{
	    read_id    => $read_id,
	    sample_id  => $sample_id,
	    orf_alt_id => $orf_alt_id,
	}
    );
    return $orf;
}

sub get_gene_by_id{
    my( $self, $geneid ) = @_;
    print "$geneid\n";
    my $gene = $self->{"schema"}->resultset('Gene')->find( { gene_oid => $geneid } );
    return $gene;
}

sub build_project_ffdb{
    my $self = shift;
    my $ffdb = $self->{"ffdb"};
    my $proj_dir = $ffdb . "/projects/" . $self->{"project_id"} . "/";
    unless( -d $proj_dir ){ 
	mkdir( $proj_dir ) || die "Can't create directory $proj_dir in build_project_ffdb: $!\n";
    }
    else{
	warn "Project directory already exists at $proj_dir. Will not overwrite!\n";
	die;
    }    
    return $self;
}

sub build_sample_ffdb{
    my $self = shift;
    my $proj_dir = $ffdb . "/projects/" . $self->{"project_id"} . "/";
    foreach my $sample( keys( %{ $self->{"samples"} } ) ){
	my $sample_dir = $proj_dir . $self->{"samples"}->{$sample}->{"sid"} . "/";
	my $raw_sample = $sample_dir . "raw.fa";
	if( -d $sample_dir ){
	    warn "Sample directory already exists at $sample_dir. Will not overwrite!\n";
	}
	else{
	    mkdir( $sample_dir ) || die "Can't create directory $sample_dir in build_project_ffdb: $!\n";
	}
	if( -e $raw_sample ){
	    warn "Data already exists in $raw_sample. Will not overwrite!\n";
	    die;
	}
	else
	    copy( $self->{"samples"}->{$sample}->{"path"}, $raw_sample ) || die "Copy of $sample failed in build_project_ffdb: $!\n";
    }
    return $self;
}

1;
