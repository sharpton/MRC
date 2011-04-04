#!/usr/bin/perl -w

#MRC::DB.pm - Database Interfacer

package MRC::DB;

use strict;
use IMG::Schema;
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path 'rmtree';

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

sub delete_project{
    my $self       = shift;
    my $project_id = shift;
    my $project   = $self->{"schema"}->resultset("Project")->search(
	{
	    project_id => $project_id,
	}
	);
    $project->delete();
    return $self;
}

sub delete_orfs_by_sample_id{
    my $self = shift;
    my $sample_id = shift;
    my $orfs = $self->{"schema"}->resultset("Orf")->search(
	{
	    sample_id => $sample_id,
	}
    );
    $orfs->delete();
    return $self;
}


sub delete_reads_by_sample_id{
    my $self = shift;
    my $sample_id = shift;
    my $reads = $self->{"schema"}->resultset("Metaread")->search(
	{
	    sample_id => $sample_id,
	}
    );
    $reads->delete();
    return $self;
}

sub delete_sample{
    my $self = shift;
    my $sample_id = shift;
    my $sample = $self->{"schema"}->resultset("Sample")->search(
	{
	    sample_id => $sample_id,
	}
	);
    $sample->delete();
    return $self;
}

sub delete_ffdb_project{
    my $self       = shift;
    my $project_id = shift;
    my $ffdb = $self->{"ffdb"};
    my $project_ffdb = $ffdb . "projects/" . $project_id;
    rmtree( $project_ffdb );
    return $self;
}

sub create_sample{
    my $self = shift;
    my $sample_name = shift;
    my $project_id = shift;    
    my $proj_rs = $self->{"schema"}->resultset("Sample");
    my $inserted = $proj_rs->create(
	{
	    name       => $sample_name,
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

sub build_hmmdb_ffdb{
    my $self = shift;
    my $path = shift;
    mkdir( $path ) || die "Can't create directory $path in build_hmmdb_ffdb: $!\n";
    return $self;       
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
    my $ffdb = $self->{"ffdb"};
    my $proj_dir = $ffdb . "/projects/" . $self->{"project_id"} . "/";
    foreach my $sample( keys( %{ $self->{"samples"} } ) ){
	my $sample_dir = $proj_dir . $self->{"samples"}->{$sample}->{"id"} . "/";
	my $raw_sample = $sample_dir . "raw.fa";
	my $search_res = $sample_dir . "search_results/";
	if( -d $sample_dir ){
	    warn "Sample directory already exists at $sample_dir. Will not overwrite!\n";
	}
	else{
	    mkdir( $sample_dir ) || die "Can't create directory $sample_dir in build_sample_ffdb: $!\n";
	}
	if( -e $raw_sample ){
	    warn "Data already exists in $raw_sample. Will not overwrite!\n";
	    die;
	}
	else{
	    copy( $self->{"samples"}->{$sample}->{"path"}, $raw_sample ) || die "Copy of $sample failed in build_project_ffdb: $!\n";
	}
	if( -d $search_res ){
	    warn "Search results_dir already exists for $sample at $search_res. Will not overwrite!\n";
	    die;
	}
	else{
	    mkdir( $search_res ) || die "Can't create directory $search_res in build_sample_ffdb: $!\n";
	}
    }
    return $self;
}

sub get_hmmdbs{
    my $self       = shift;
    my $hmmdb_name = shift;
    my $ffdb = $self->{"ffdb"};
    my $hmmdb_path = $ffdb . "/HMMdbs/" . $hmmdb_name . "/";
    opendir( HMMS, $hmmdb_path ) || die "Can't opendir $hmmdb_path for read: $!\n";
    my @files = readdir( HMMS );
    closedir( HMMS );
    my %hmmdbs = ();
    foreach my $file ( @files ){
	next if( $file =~ m/^\./ );
	next if( $file =~ m/\.h3[i|m|p|f]/ );
	$hmmdbs{$file} = $hmmdb_path . $file;
    }
    warn "Grabbed ", scalar( keys( %hmmdbs ) ), " HMM dbs from $hmmdb_path\n";
    return \%hmmdbs;
}

1;
