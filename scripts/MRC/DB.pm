#!/usr/bin/perl -w

#MRC::DB.pm - Database Interfacer
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

package MRC::DB;

use strict;
use IMG::Schema;
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path qw(make_path rmtree);

#returns samples result set
sub get_samples_by_project_id{
    my $self    = shift;
    my $samples = $self->get_schema->resultset("Sample")->search(
	{
	    project_id => $self->get_project_id(),
	}
    );
    return $samples;
}

sub get_family_members_by_famid{
    my $self    = shift;
    my $famid   = shift;
    my $members = $self->get_schema->resultset("Familymember")->search(
	{
	    famid => $famid,
	}
    );
    return $members;
}

sub create_project{
    my $self = shift;
    my $name = shift;
    my $text = shift;
    my $proj_rs = $self->get_schema->resultset("Project");
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
    my $project   = $self->get_schema->resultset("Project")->search(
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
    my $orfs = $self->get_schema->resultset("Orf")->search(
	{
	    sample_id => $sample_id,
	}
    );
    $orfs->delete();
    return $self;
}

sub delete_search_result_by_sample_id{
    my $self      = shift;
    my $sample_id = shift;
    my $orfs = $self->get_schema->resultset("Orf")->search(
	{
	    sample_id => $sample_id,
	}
    );
    while( my $orf = $orfs->next() ){
	my $orf_id = $orf->orf_id();
	$self->MRC::DB::delete_search_result_by_orf_id( $orf_id );	
    }
    return $self;
}

sub delete_search_result_by_orf_id{
    my $self   = shift;
    my $orf_id = shift;
    my $search_results  = $self->get_schema->resultset("Searchresult")->search(
	{
	    orf_id => $orf_id,
	}
	);
    while( my $search_result = $search_results->next() ){
	$search_result->delete();
    }
    return $self;
}

sub delete_family_member_by_sample_id{
    my $self = shift;
    my $sample_id = shift;
    my $orfs = $self->get_schema->resultset("Orf")->search(
	{
	    sample_id => $sample_id,
	}
    );
    while( my $orf = $orfs->next() ){
	my $orf_id = $orf->orf_id();
	$self->MRC::DB::delete_family_member_by_orf_id( $orf_id );	
    }
    return $self;
}


sub delete_family_member_by_orf_id{
    my $self = shift;
    my $orf_id = shift;
    my $fam_members  = $self->get_schema->resultset("Familymember")->search(
	{
	    orf_id => $orf_id,
	}
	);
    while( my $fam_member = $fam_members->next() ){
	$fam_member->delete();
    }
    return $self;
}


sub delete_reads_by_sample_id{
    my $self = shift;
    my $sample_id = shift;
    my $reads = $self->get_schema->resultset("Metaread")->search(
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
    my $sample = $self->get_schema->resultset("Sample")->search(
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
    my $ffdb = $self->get_ffdb();
    my $project_ffdb = $ffdb . "projects/" . $project_id;
    rmtree( $project_ffdb );
    return $self;
}

sub create_sample{
    my $self = shift;
    my $sample_name = shift;
    my $project_id = shift;    
    my $proj_rs = $self->get_schema->resultset("Sample");
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
    my $proj_rs = $self->get_schema->resultset("Metaread");
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
    my $orf = $self->get_schema->resultset("Orf")->create(
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
    my $gene = $self->get_schema->resultset('Gene')->find( { gene_oid => $geneid } );
    return $gene;
}

sub build_db_ffdb{
    my $self = shift;
    my $path = shift;
    if( -d $path ){
	rmtree( $path ) || die "Can't remove $path in build_db_ffdb: $!\n";
    }
    make_path( $path ) || die "Can't create directory $path in build_db_ffdb: $!\n";
    return $self;       
}

sub get_hmmdb_path{
    my $self = shift;
    my $hmmdb_path = $self->get_ffdb() . "HMMdbs/" . $self->get_hmmdb_name() . "/";
    return $hmmdb_path;
}

sub get_blastdb_path{
    my $self = shift;
    my $blastdb_path = $self->get_ffdb() . "BLASTdbs/" . $self->get_blastdb_name() . "/";
    return $blastdb_path;
}

sub get_number_db_splits{
    my ( $self, $type ) = @_;
    my $n_splits = 0;
    my $db_path;
    if( $type eq "hmm" ){
	$db_path = $self->MRC::DB::get_hmmdb_path; 
    }
    elsif( $type eq "blast" ){
	$db_path = $self->MRC::DB::get_blastdb_path;
    }
    opendir( DIR, $db_path ) || die "Can't opendir " . $db_path . " for read: $!\n";
    my @files = readdir( DIR );
    closedir( DIR );
    foreach my $file( @files ){
	#don't want to count both the uncompressed and the compressed, so look for the .gz ending on file name
	next unless( $file =~ m/\.gz$/ );
	$n_splits++;
    }
    #total number of sequences/models across the entire database (to correctly scale evalue)
    return $n_splits;
}

#for hmmscan -Z correction
sub get_number_hmmdb_scans{
    my ( $self, $n_seqs_per_db_split ) = @_;
    my $n_splits = 0;
    opendir( DIR, $self->MRC::DB::get_hmmdb_path ) || die "Can't opendir " . $self->get_hmmdb_path . " for read: $!\n";
    my @files = readdir( DIR );
    closedir( DIR );
    foreach my $file( @files ){
	#don't want to count both the uncompressed and the compressed, so look for the .gz ending on file name
	next unless( $file =~ m/\.gz$/ );
	$n_splits++;
    }
    #total number of sequences/models across the entire database (to correctly scale evalue)
    my $n_seqs = $n_splits * $n_seqs_per_db_split;
    return $n_seqs;
}

#for hmmsearch
sub get_number_sequences{
    my( $self, $n_sequences ) = @_;
    my $n_splits = 0;
    foreach my $sample_id( @{ $self->get_sample_ids() } ){
	my $orfs_path = $self->get_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/orfs/";
	opendir( DIR, $orfs_path ) || die "Can't opendir " . $orfs_path . " for read: $!\n";
	my @files = readdir( DIR );
	closedir( DIR );	
	foreach my $file( @files ){
	    next unless( $file =~ m/\.fa/ );
	    $n_splits++;
	}
    }
    my $n_seqs = $n_splits * $n_sequences;
    return $n_seqs;
}

#for blast
sub get_blast_db_length{
    my( $self, $db_name ) = @_;
    my $length  = 0;
    my $db_path = $self->MRC::DB::get_blastdb_path();
    if( -e $db_path . "/database_length.txt" ){
	open( IN, $db_path . "/database_length.txt" ) || 
	    die "Can't open " . $db_path . "/database_length.txt for read: $!\n";
	while( <IN> ){
	    chomp $_;
	    $length = $_;
	}
	close IN;
	return $length;
    }
    else{
	$length = $self->MRC::Run::calculate_blast_db_length();
    }
    return $length;
}

sub build_project_ffdb{
    my $self = shift;
    my $ffdb = $self->{"ffdb"};
    my $proj_dir = $ffdb . "/projects/" . $self->{"project_id"} . "/";
    unless( -d $proj_dir ){ 
	make_path( $proj_dir ) || die "Can't create directory $proj_dir in build_project_ffdb: $!\n";
    }
    else{
	warn "Project directory already exists at $proj_dir. Will not overwrite!\n";
	die;
    }    
    return $self;
}

sub build_sample_ffdb{
    my $self = shift;
    my $nseqs_per_samp_split = shift;
    my $ffdb = $self->get_ffdb;
    my $proj_dir = $ffdb . "/projects/" . $self->get_project_id . "/";
    my $logs     = $proj_dir . "/logs/";
    my $hmmscanlogs   = $logs . "/hmmscan/";
    my $hmmsearchlogs = $logs . "/hmmsearch/";
    my $blastlogs     = $logs . "/blast/";
    my $formatdblogs  = $logs . "/formatdb/";
    my $output        = $proj_dir . "/output/";
    if( -d $output ){
	warn( "Output directory already exists at $output. Will not overwrite!\n");
    }
    else{
	make_path( $output ) || die "Can't create directory $output in build_sample_ffdb: $!\n";
    }
    if( -d $logs ){
	warn( "Logs directory already exists at $logs. Will not overwrite!\n");
    }
    else{
	make_path( $logs ) || die "Can't create directory $logs in build_sample_ffdb: $!\n";
    }
    if( -d $hmmscanlogs ){
	warn( "Logs directory already exists at $hmmscanlogs. Will not overwrite!\n");
    }
    else{
	make_path( $hmmscanlogs ) || die "Can't create directory $hmmscanlogs in build_sample_ffdb: $!\n";
    }
    if( -d $hmmsearchlogs ){
	warn( "Logs directory already exists at $hmmsearchlogs. Will not overwrite!\n");
    }
    else{
	make_path( $hmmsearchlogs ) || die "Can't create directory $hmmsearchlogs in build_sample_ffdb: $!\n";
    }
    if( -d $blastlogs ){
	warn( "Logs directory already exists at $blastlogs. Will not overwrite!\n");
    }
    else{
	make_path( $blastlogs ) || die "Can't create directory $blastlogs in build_sample_ffdb: $!\n";
    }
    if( -d $formatdblogs ){
	warn( "Logs directory already exists at $formatdblogs. Will not overwrite!\n");
    }
    else{
	make_path( $formatdblogs ) || die "Can't create directory $formatdblogs in build_sample_ffdb: $!\n";
    }

    foreach my $sample( keys( %{ $self->get_samples() } ) ){
	my $sample_dir = $proj_dir . $self->get_samples->{$sample}->{"id"} . "/";
	my $raw_sample_dir = $sample_dir . "raw/";
	my $orf_sample_dir = $sample_dir . "orfs/";
	my $search_res     = $sample_dir . "search_results/";
	if( -d $sample_dir ){
	    warn "Sample directory already exists at $sample_dir. Will not overwrite!\n";
	}
	else{
	    make_path( $sample_dir ) || die "Can't create directory $sample_dir in build_sample_ffdb: $!\n";
	}
	if( -d $search_res ){
	    warn "Search results_dir already exists for $sample at $search_res. Will not overwrite!\n";
	    die;
	}
	else{
	    make_path( $search_res ) || die "Can't create directory $search_res in build_sample_ffdb: $!\n";
	    my $hmmscan_results = $search_res . "/hmmscan";
	    make_path( $hmmscan_results ) || die "Can't create directory $hmmscan_results in build_sample_ffdb: $!\n";
	    my $hmmsearch_results = $search_res . "/hmmsearch";
	    make_path( $hmmsearch_results ) || die "Can't create directory $hmmsearch_results in build_sample_ffdb: $!\n";
	    my $blast_results = $search_res . "/blast";
	    make_path( $blast_results ) || die "Can't create directory $blast_results in build_sample_ffdb: $!\n";
	}
	if( -d $raw_sample_dir ){
	    warn "Data already exists in $raw_sample_dir. Will not overwrite!\n";
	    die;
	}
	else{
	    make_path( $raw_sample_dir );
	    #copy( $self->get_samples->{$sample}->{"path"}, $raw_sample ) || die "Copy of $sample failed in build_project_ffdb: $!\n";
	    my $basename = $sample . "_raw_split_";
	    my @split_names = @{ $self->MRC::DB::split_sequence_file( $self->get_samples->{$sample}->{"path"}, $raw_sample_dir, $basename, $nseqs_per_samp_split ) };
	    #because search results may be large in volume, we will break each set of search results into the corresponding search_dir
	    #for each split. We don't do this here anymore. Instead, we have the directory created as part of run_hmmscan. Provides more flexibility and 
	    #enables more consistency (these will be named *raw*, but the file used in hmmscan is *orf*, so it is screwy if we use method below)
	    if( 0 ){
		foreach my $split_name( @split_names ){
		    my $split_search_path = $search_res . $split_name . "/";
		    if( -d $split_search_path ){
			warn "Search result path already exists for $split_search_path!\n";
			die;
		    }
		    else{
			make_path( $split_search_path );
		    }
		}	    
	    }
	}
	if( -d $orf_sample_dir ){
	    warn "orf_sample_dir already exists for $sample at $orf_sample_dir. Will not overwrite!\n";
	    die;
	}
	else{
	    make_path( $orf_sample_dir ) || die "Can't create directory $orf_sample_dir in build_sample_ffdb: $!\n";
	}
    }
    return $self;
}

sub split_sequence_file{
    my $self             = shift;
    my $full_seq_file    = shift;
    my $split_dir        = shift;
    my $basename         = shift;
    my $nseqs_per_split  = shift;
    #a list of filenames
    my @output_names = ();
    my $seqs = Bio::SeqIO->new( -file => "$full_seq_file", -format => "fasta" );
    my $counter = 1;
    my $outname  = $basename . $counter . ".fa";
    my $splitout = $split_dir . "/" . $outname;
    my $output = Bio::SeqIO->new( -file => ">$splitout", -format => "fasta" );
    push( @output_names, $outname );
    print "Will dump to split $splitout\n";
    my $seq_ct = 0;
    while( my $seq = $seqs->next_seq() ){
	if( $seq_ct == $nseqs_per_split ){	
	    $counter++;
	    my $outname  = $basename . $counter . ".fa";
	    my $splitout = $split_dir . "/" . $outname;
	    $output = Bio::SeqIO->new( -file => ">$splitout", -format => "fasta" );	
	    push( @output_names, $outname );
	    print "Will dump to split $splitout\n";
	    $seq_ct = 0;
	}
	$output->write_seq( $seq );
	$seq_ct++;       
    }    
    return \@output_names;
}

sub get_split_sequence_paths{
    my $self      = shift;
    my $split_dir = shift; #dir path that contains the split files
    my $full_path = shift; #0 = filename, 1 = full path 
    my @paths     = ();    
    opendir( DIR, $split_dir ) || die "Error in MRC::DB::get_split_sequence_paths: Can't opendir $split_dir for read: $!\n";
    my @files = readdir( DIR );
    closedir( DIR );
    foreach my $file( @files ){
	next if( $file =~ m/^\./ );
	my $path = $file;
	if( $full_path ){
	    $path = $split_dir . $file;
	}
	push( @paths, $path ) 
    }      
    return \@paths;
}

sub get_hmmdbs{
    my $is_remote  = 0;

    my $self       = shift;
    my $hmmdb_name = shift;
    $is_remote = shift;

    my $ffdb = $self->get_ffdb();
    my $hmmdb_path = $ffdb . "/HMMdbs/" . $hmmdb_name . "/";
    opendir( HMMS, $hmmdb_path ) || die "Can't opendir $hmmdb_path for read: $!\n";
    my @files = readdir( HMMS );
    closedir( HMMS );
    my %hmmdbs = ();
    foreach my $file ( @files ){
	next if( $file =~ m/^\./ );
	next if( $file =~ m/\.h3[i|m|p|f]/ );
	#if grabbing from remote server, use the fact that HMMdb is a mirror to get proper remote path
	if( $is_remote ){
	    $hmmdbs{$file} = $self->get_remote_ffdb . "/HMMdbs/" . $hmmdb_name . "/" . $file;
	}
	else{
	    $hmmdbs{$file} = $hmmdb_path . $file;
	}
    }
    warn "Grabbed ", scalar( keys( %hmmdbs ) ), " HMM dbs from $hmmdb_path\n";
    return \%hmmdbs;
}

sub get_sample_by_sample_id{
    my $self = shift;
    my $sample_id = shift;
    my $sample = $self->get_schema->resultset('Sample')->find(
	{
	  sample_id => $sample_id  
	}
    );
    return $sample;
}

sub get_orf_by_orf_id{
    my $self = shift;
    my $orf_id = shift;
    my $orf = $self->get_schema->resultset('Orf')->find(
	{
	    orf_id => $orf_id,
	}
	);
    return $orf;
}

sub get_number_reads_in_sample{
    my $self   = shift;
    my $sample = shift;
    my $reads  = $self->MRC::DB::get_reads_by_sample_id( $sample );
    return $reads->count();
}

sub get_reads_by_sample_id{
    my $self = shift;
    my $sample_id = shift;
    my $reads = $self->get_schema->resultset('Metaread')->search(
	{
	    sample_id => $sample_id,
	}
    );
    return $reads;
}

sub get_read_alt_id_by_read_id{
    my $self = shift;
    my $read_id = shift;
    my $read = $self->get_schema->resultset('Metaread')->find(
	{
	    read_id => $read_id,
	}
    );
    my $read_alt_id = $read->read_alt_id();
    return $read_alt_id;
}

sub get_orfs_by_read_id{ 
    my $self = shift;
    my $read_id = shift;
    my $orfs = $self->get_schema->resultset('Orf')->search(
	{
	    read_id => $read_id,
	}
    );
    return $orfs;
}

sub get_families_with_orfs_by_project{
    my $self = shift;
    my $project_id = shift;
    if( !defined( $project_id ) ){
	$project_id =  $self->get_project_id();
    }
    my $fams = $self->get_schema->resultset('Familymember')->search(
	{
	    project_id => $project_id
	},
	{
	    join      => { 'orf' => 'sample' },
	
	}
	);
    return $fams;
}    


sub get_families_with_orfs_by_sample{
    my ( $self, $sample_id ) = @_;
    my $fams = $self->get_schema->resultset('Familymember')->search(
	{
	    sample_id => $sample_id
	},
	{
	    join      => 'orf'
	}
	);
    return $fams;
}

sub get_family_members_by_orf_id{
    my $self = shift;
    my $orf_id = shift; 
    my $fam_members = $self->get_schema->resultset('Familymember')->search(
	{
	    orf_id => $orf_id,
	}
    );
    return $fam_members;
}

#my $qorf_id = $self->MRC::DB::get_orf_id_from_alt_id( $qorf, $sample );
sub get_orf_from_alt_id{
    my $self = shift;
    my $orf_alt_id = shift;
    my $sample_id  = shift;
    my $orf = $self->get_schema->resultset('Orf')->find(
	{
	    orf_alt_id => $orf_alt_id,
	    sample_id  => $sample_id,
	}
    );
    return $orf;
}

sub insert_search_result{
    my ( $self, $orf_id, $famid, $evalue, $score, $coverage ) = @_;
    my $inserted = $self->get_schema->resultset("Searchresult")->create(
	{
	    orf_id => $orf_id,
	    famid => $famid,
	    evalue => $evalue,
	    score  => $score,
	    other_searchstats => "coverage=" . $coverage,
	}
	);
    return $inserted;
}

#$self->MRC::DB::insert_family_member_orf( $qorf_id, $hmm );
sub insert_family_member_orf{
    my $self   = shift;
    my $orf_id = shift;
    my $famid  = shift;
    my $inserted = $self->get_schema->resultset("Familymember")->create(
	{
	    famid  => $famid,
	    orf_id => $orf_id,
	}
	);    
    return $inserted;
}

sub get_genomes_by_domain{
    my $self = shift;
    my $domain = shift;
    my $genomes = $self->get_schema->resultset("Genome")->search(
	{
	    domain => $domain,
	}
	);
    return $genomes;
}

sub get_genes{
    my $self  = shift;
    my $genes = $self->get_schema->resultset("Gene");
    return $genes;
}

sub get_genes_by_taxon_oid{
    my $self      = shift;
    my $taxon_oid = shift;
    my $genes     = $self->get_schema->resultset("Gene")->search(
	{
	    taxon_oid => $taxon_oid,
	}
	);
    return $genes;
}

sub get_gene_from_gene_oid{
    my $self = shift;
    my $gene_oid = shift;
    my $gene = $self->get_schema->resultset("Gene")->find(
	{
	    gene_oid => $gene_oid,
	}
	);
    return $gene;
}

sub get_genes_from_taxon_oid{
    my $self = shift;
    my $taxon_oid = shift;
    my $genes = $self->get_schema->resultset("Gene")->search(
	{
	    taxon_oid => $taxon_oid,
	}
	);
    return $genes;
}

sub get_genome_from_taxon_oid{
    my $self = shift;
    my $taxon_oid = shift;
    my $genome = $self->get_schema->resultset("Genome")->find(
	{
	    taxon_oid => $taxon_oid,
	}
	);
    return $genome;

}

sub get_family_from_famid{
    my $self = shift;
    my $famid = shift;
    my $family = $self->get_schema->resultset("Family")->find(
	{
	    famid => $famid,
	}	
	);
    return $family;
}

sub get_projects{
    my $self = shift;
    my $projects = $self->get_schema->resultset("Project");		    
    return $projects;
}

sub get_family_by_fci{
    my $self = shift;
    my $fci  = shift;
    my $families = $self->get_schema->resultset("Family")->search(
	{
	    familyconstruction_id => $fci,
	}
    );
    return $families;
}

sub get_famid_from_geneoid{
    my $self = shift;
    my $gene_oid = shift;
    my @fcis    = @{ $_[0] }; #optional
    my $families = $self->get_schema->resultset("Familymember")->search(
	{
	    gene_oid => $gene_oid,
	}
    );
    if( $families->count() > 1 ){
	if( !( @fcis ) ){
	    	warn( "Got multiple families for gene_oid $gene_oid. Must use fci to determine which family to select!\n" );
		exit( 0 );
	}
    }
    my @selected = ();
    while( my $family = $families->next() ){
	my $famid = $family->famid->famid;
	if( @fcis ){
	    my $family_rs = $self->MRC::DB::get_family_from_famid( $famid );
	    my $fam_fci   = $family_rs->familyconstruction_id();
	    my $is_fci  = 0;
	    foreach my $fci( @fcis ){
		if( $fam_fci == $fci ){
		    $is_fci = 1;
		    last;
		}
	    }
	    if( $is_fci ){
		push( @selected, $famid );
	    }
	}
    }
    if( scalar( @selected ) > 1 ){
	warn( "Even with fci selection there are multiple family ids for gene_oid $gene_oid: " . join( " ", @selected, "\n" ) );
	exit(0);
    }
    else{
	return $selected[0];
    }
}

sub get_famid_from_fam_alt_id{
    my( $self, $fam_alt_id ) = shift;
    my $famid = $self->get_schema->resultset("Family")->search(
	{
	    fam_alt_id => $fam_alt_id,
	}
	);
    return $famid;
}



sub get_family_sequences_by_fci{
    my $self = shift;
    my @fcis = @{ $_[0] };
    my $out  = $_[1]; #optional
    my %seqs = ();
    foreach my $fci( @fcis ){
	my $families = $self->get_schema->resultset("Family")->search(
	    {
		familyconstruction_id => $fci,
	    }
	);
	while( my $family = $families->next() ){
	    my $members = $self->MRC::DB::get_family_members_by_famid( $family->famid() );
	    while( my $member = $members->next() ){
		my $gene_oid_rs = $member->gene_oid;
		if( defined( $gene_oid_rs ) ){
		    my $gene_oid = $gene_oid_rs->gene_oid;
		    if( defined( $gene_oid ) ){
			if( defined( $out ) ){
			    print $out "$gene_oid\n";
			}
			else{
			    $seqs{$gene_oid}++;
			}
		    }
		}					    
	    }
	}
    }
    return \%seqs;
}

sub get_gene_length{
    my $self = shift;
    my $gene_oid = shift;
    my $genes = $self->get_schema->resultset("Gene")->search(
	{
	    gene_oid => $gene_oid,
	}
    );
    my $seqlen;
    while( my $gene = $genes->next() ){
	$seqlen = length( $gene->dna );
	last;
    }
    return $seqlen;
}

###
# DB LOADER FUNCTIONS
###

sub insert_family_construction{
    my $self        = shift;
    my $description = shift;
    my $name        = shift;    
    my $author      = shift;
    my $proj_rs     = $self->get_schema->resultset("Familyconstruction");
    my $inserted    = $proj_rs->create(
	{
	    description => $description,
	    name        => $name,
	    author      => $author,
	}
	);
    return $inserted;
}

sub insert_family{
    my ( $self, $family_name, $family_desc, $fci ) = @_;
    my $inserted = $self->get_schema->resultset("Family")->create(
	{
	    familyconstruction_id => $fci,
#	    fam_alt_id            => $fam_alt_id,
	    name                  => $family_name,
	    description           => $family_desc,
	}
	);
    return $inserted;
}

sub insert_protein_into_genes{
    my ( $self, $gene_oid, $taxon_oid, $id, $type, $protein, $protein_name, $protein_desc, $start, $end, $strand, $locus, $scaffold_name, $scaffold_id, $dna ) = @_;
    my $inserted = $self->get_schema->resultset("Gene")->find_or_create(
	{
	    gene_oid    => $gene_oid,
	    taxon_oid   => $taxon_oid,
	    protein_id  => $id,
	    type        => $type,
	    protein     => $protein,
	    name        => $protein_name,
	    description => $protein_desc,
	    start       => $start,
	    end         => $end,
	    strand      => $strand,
	    locus       => $locus,
	    dna         => $dna,
	    scaffold_name => $scaffold_name,
	    scaffold_id   => $scaffold_id,	    
	}
	);
    return $inserted,
}

sub insert_gene_into_family_members{
    my ( $self, $famid, $gene_oid ) = @_;
    my $inserted = $self->get_schema->resultset("Familymember")->create(
	{
	    famid    => $famid,
	    gene_oid => $gene_oid,
	}
	);
}

sub insert_genome{
    my ( $self, $ncbi_taxon_id, $ncbi_project_id, $completion, $domain, $genome_name, $directory, 
	 $phylum, $class, $order, $family, $genus, $sequencing_center, $gene_count, 
	 $genome_size, $scaffold_count, $img_release, $add_date, $is_public ) = @_;
    my $inserted = $self->get_schema->resultset("Genome")->find_or_create(
	{
	    ncbi_taxon_id => $ncbi_taxon_id,
	    ncbi_project_id   => $ncbi_project_id,
	    completion        => $completion,
	    domain            => $domain,
	    name              => $genome_name,
	    directory         => $directory,
	    phylum            => $phylum,
	    class             => $class,
	    order             => $order,
	    family            => $family,
	    genus             => $genus,
	    sequencing_center => $sequencing_center,
	    gene_count        => $gene_count,
	    genome_size       => $genome_size,
	    scaffold_count     => $scaffold_count,
	    img_release       => $img_release,
	    add_date          => $add_date,
	    is_public         => $is_public,
	}	
	);
    return $inserted;
}

sub get_max_column_value{
    my( $self, $table, $column ) = @_;
    my $maxvalue = $self->get_schema->resultset($table)->get_column($column)->max;
    return $maxvalue;
}

1;
