#!/usr/bin/perl -w

#MRC.pm - The MRC workflow manager
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

package MRC;

use strict;
use MRC::DB;
use MRC::Run;
use IMG::Schema;
use Data::Dumper;
use File::Basename;

=head2 new

 Title   : new
 Usage   : $project = MRC->new()
 Function: initializes a new MRC analysis object
 Example : $analysus = MRC->new();
 Returns : A MRC analysis object
 Args    : None

=cut

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    my @fcis  = ( 4,6 );
    $self->{"fci"}         = \@fcis; #family construction ids that are allowed to be processed
    $self->{"workdir"}     = undef; #master path to MRC scripts
    $self->{"ffdb"}        = undef; #master path to the flat file database
    $self->{"dbi"}         = undef; #DBI string to interact with DB
    $self->{"user"}        = undef; #username to interact with DB
    $self->{"pass"}        = undef; #password to interact with DB
    $self->{"projectpath"} = undef;
    $self->{"projectname"} = undef;
    $self->{"project_id"}  = undef;
    $self->{"proj_desc"}   = undef;
    $self->{"samples"}     = undef; #hash relating sample names to paths   
    $self->{"rusername"}   = undef;
    $self->{"r_ip"}        = undef;
    $self->{"rscripts"}    = undef;
    $self->{"rffdb"}       = undef;
    $self->{"fid_subse"}   = undef; #an array of famids
    $self->{"schema"}      = undef; #current working DB schema object (DBIx)    
    $self->{"hmmdb"}       = undef; #name of the hmmdb to use in this analysis
    $self->{"is_remote"}   = 0;     #does analysis include remote compute? 0 = no, 1 = yes
    $self->{"is_strict"}   = 1;     #strict (top hit) v. fuzzy (all hits passing thresholds) clustering. 1 = strict. 0 = fuzzy. Fuzzy not yet implemented!
    $self->{"t_evalue"}    = undef; #evalue threshold for clustering
    $self->{"t_coverage"}  = undef; #coverage threshold for clustering
    $self->{"r_hmmscan_script"} = undef; #location of the remote hmmscan script. holds a path string.
    $self->{"r_project_logs"}   = undef; #location of the remote project logs directory. holds a path string.

    bless($self);
    return $self;
}

=head2 get_sample_ids

 Title   : get_sample_ids
 Usage   : $analysis->get_sample_ids( )
 Function: Obtains the unique sample_ids for each sample in the project
 Example : my @sample_ids = @{ analysis->get_sample_ids() };
 Returns : A array of sample_ids (array reference)
 Args    : None

=cut

sub get_sample_ids{
    my $self = shift;
    my @sample_ids = ();
    foreach my $sample( keys( %{ $self->{"samples"} } ) ){
	my $sample_id = $self->{"samples"}->{$sample}->{"id"};
	push( @sample_ids, $sample_id );
    }
    return \@sample_ids;
}

=head2 set_fcis

 Title   : set_fcis
 Usage   : $analysis->set_fcis( 1, 4, 6 )
 Function: Sets which family construction ids should be used in the analysis
 Example : my @sample_ids = @{ analysis->get_sample_ids() };
 Returns : An array of family construction ids (array reference, optional)
 Args    : An array of family construction ids (array reference)

=cut

sub set_fcis{
  my $self = shift;
  my @fcis = @_;
  if( !@fcis ){
    warn "No fci value(s) supplied for set_fcis in MRC.pm. Using default value of ", @{ $self->{"fci"} }, ".\n";
  }
  else{
      warn "Setting fci to @fcis\n";
  }
  $self->{"fci"} = \@fcis;
  return $self->{"fci"};
}

=head2 set_scripts_dir

 Title   : set_scripts_dir
 Usage   : $analysis->set_scripts_dir( "~/projects/MRC/scripts" )
 Function: Indicates where the MRC scripts directory is located
 Example : my $scripts_path = analysis->set_scripts_dir( "~/projects/MRC/scripts" );
 Returns : A string that points to a directory path (scalar, optional)
 Args    : A string that points to a directory path (scalar)

=cut

sub set_scripts_dir{
  my $self = shift;
  my $path = shift;
  if( !defined( $path ) ){
    warn "No scripts path specified for set_scripts_dir in MRC.pm. Cannot continue!\n";
    die;
  }
  if( !( -e $path ) ){
    warn "The method set_scripts_dir cannot access scripts path $path. Cannot continue!\n";
    die;
  }
  $self->{"workdir"} = $path;
  return $self->{"workdir"};
}

=head2 set_ffdb

 Title   : set_ffdb
 Usage   : $analysis->set_ffdb( "~/projects/MRC/ffdb/" )
 Function: Indicates where the MRC flat file database is located
 Example : my $scripts_path = analysis->set_ffdb( "~/projects/MRC/ffdb" );
 Returns : A string that points to a directory path (scalar, optional)
 Args    : A string that points to a directory path (scalar)

=cut

sub set_ffdb{
    my $self = shift;
    my $path = shift;
    if( !defined( $path ) ){
      warn "No ffdb path specified for set_flat_file_db in MRC.pm. Cannot continue!\n";
      die;
    }
    if( !( -e $path ) ){
      warn "The method set_flat_file_db cannot access ffdb path $path. Cannot continue!\n";
    die;
    }
    $self->{"ffdb"} = $path;
    return $self->{"ffdb"};
}

=head2 get_ffdb

 Title   : get_ffdb
 Usage   : $analysis->get_ffdb()
 Function: Identify the location of the MRC flat file database. Must have been previously set with set_ffdb()
 Example : analysis->set_ffdb( "~/projects/MRC/ffdb" );
           my $ffdb = analysis->get_ffdb();
 Returns : A string that points to a directory path (scalar)
 Args    : None

=cut

sub get_ffdb{
  my $self = shift;
  return $self->{"ffdb"};
}

=head2 set_dbi_connection

 Title   : set_dbi_connection
 Usage   : $analysis->set_dbi_conection( "DBI:mysql:IMG" );
 Function: Create a connection with mysql (or other) database
 Example : my $connection = analysis->set_dbi_connection( "DBI:mysql:IMG" );
 Returns : A DBI connection string (scalar, optional)
 Args    : A DBI connection string (scalar)

=cut

sub set_dbi_connection{
    my $self = shift;
    my $path = shift;
    $self->{"dbi"} = $path;
    return $self->{"dbi"};
}

#points to the original project path file, not ffdb version!
sub set_project_path{
    my $self = shift;
    my $path = shift;
    $self->{"projectpath"} = $path;
    return $self->{"projectpath"};
}

#points to the original project path file, not the ffdb version!
sub get_project_path{
    my $self = shift;
    return $self->{"projectpath"};
}

sub get_sample_path{
    my $self = shift;
    my $sample_id = shift;
    my $sample_path = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/". $sample_id . "/";
    return $sample_path;
}

sub set_project_desc{
    my $self = shift;
    my $text = shift;
    $self->{"proj_desc"} = $text;
    return $self->{"proj_desc"};    
}

sub set_samples{
    my $self = shift;
    my $samples = shift;
    $self->{"samples"} = $samples;
    return $self->{"samples"};
}

sub get_schema{
    my $self = shift;
    my $schema = $self->{"schema"};
    return $schema;
}

sub set_username{
    my $self = shift;
    my $path = shift;
    $self->{"user"} = $path;
    return $self->{"user"};
}

sub set_password{
    my $self = shift;
    my $path = shift;
    $self->{"pass"} = $path;
    return $self->{"pass"};
}

sub build_schema{
    my $self = shift;
    my $schema = IMG::Schema->connect( $self->{"dbi"}, $self->{"user"}, $self->{"pass"},
				       #since we have terms in DB that are reserved words in mysql (e.g., order)
				       #we need to put quotes around those field ids when calling SQL
				       {
					   quote_char => '`', #backtick is quote in sql
					   name_sep   => '.'  #allows SQL generator to put quotes in right place
				       }
	);
    $self->{"schema"} = $schema;
    return $self->{"schema"};
}

sub set_project_id{
    my $self = shift;
    my $pid  = shift;
    if( !(defined $pid ) ){
      warn "No project id specified in set_project_id. Cannot continue!\n";
      die;
    }
    $self->{"project_id"} = $pid;
    return $self->{"project_id"};
}

sub get_project_id{
    my $self = shift;
    return $self->{"project_id"};
}

sub set_family_subset{
    my $self   = shift;
    my $subset = shift;
    my $check  = shift;
    #if no subset was provided, grab all famids that match our fcis. this could get big, so we might change in the future
    if( !defined( $subset ) ){
	warn "You did not specify a subset of family ids to process. Processing all families that meet FCI criteria.\n";
	my @all_ids = ();
	foreach my $fci( @{ $self->{"fci"} } ){	    
	    my @ids = $self->{"schema"}->resultset('Family')->search( { familyconstruction_id => $fci } )->get_column( 'famid' )->all;
	    @all_ids = ( @all_ids, @ids );
	}
	$self->{"fid_subset"} = \@all_ids;
    }
    else{
	#process the subset file. one famid per line
	open( SUBSET, $subset ) || die "Can't open $subset for read: $!\n";
	my @retained_ids = ();
	while( <SUBSET> ){
	    chomp $_;
	    push( @retained_ids, $_ );
	}
	close SUBSET;
        #let's make sure they're all from the proper family contruction id     
	if( $check == 1 ){
	    warn "Checking that families are from the proper FCI.\n";
	    my $correct_fci = 0;
	    my @correct_ids = ();
	    my @fcis = @{ $self->{"fci"} }; #get the passable construction ids
	  FID: foreach my $fid( @retained_ids ){
	      foreach my $fci( @fcis ){
		  my $fam_construct_id = $self->{"schema"}->resultset('Family')->find( { famid => $fid } )->get_column( 'familyconstruction_id' );
		  if( $fam_construct_id == $fci ){
		      $correct_fci++;
		      push( @correct_ids, $fid );
		      next FID;
		  }
	      }
	  }
	    warn "Of the ", scalar(@retained_ids), " family subset ids you provided, $correct_fci have a desired family construction id\n";
	    @retained_ids = ();
	    $self->{"fid_subset"} = \@correct_ids;
	}
	#We've checked their fci in the past. skip this process and accept everything.
	else{
	    warn "Skipping check of FCI on the subset of families.\n";
	    #store the raw array as a reference in our project object
	    $self->{"fid_subset"} = \@retained_ids;
	}
    }
    return $self->{"fid_subset"};
}

sub get_samples{
    my $self = shift;
    my $samples = $self->{"samples"}; #a hash reference
    return $samples;
}

sub get_project_desc{
    my $self = shift;
    my $desc = $self->{"proj_desc"};
    return $desc;
}

sub get_subset_famids{
    my $self = shift;
    return $self->{"fid_subset"};
}

sub set_remote_server{
    my $self        = shift;
    my $r_ip        = shift;
    $self->{"r_ip"} = $r_ip;
    return $self->{"r_ip"};
}

sub get_remote_server{
    my $self = shift;
    return $self->{"r_ip"};
}

sub set_remote_username{
    my $self      = shift;
    my $rusername = shift;
    $self->{"rusername"} = $rusername;
    return $self->{"rusername"};
}

sub get_remote_username{
    my $self = shift;
    return $self->{"rusername"};
}

sub set_remote_ffdb{
    my $self = shift;
    my $rffdb = shift;
    $self->{"rffdb"} = $rffdb;
    return $self->{"rffdb"};
}

sub get_remote_ffdb{
    my $self = shift;
    return $self->{"rffdb"};
}

sub get_remote_project_path{
   my ( $self ) = @_;
   my $path = $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/";
   return $path;
}

sub get_remote_sample_path{
    my ( $self, $sample_id ) = @_;
    my $path = $self->get_remote_ffdb() . "projects/" . $self->get_project_id() . "/" . $sample_id . "/";
    return $path;
}

sub set_remote_scripts{
    my $self     = shift;
    my $rscripts = shift;
    $self->{"rscripts"} = $rscripts;
    return $self->{"rscripts"};
}

sub set_hmmdb_name{
    my ( $self, $name ) = @_;
    $self->{"hmmdb"} = $name;
    return $self->{"hmmdb"};
}

sub get_hmmdb_name{
    my $self = shift;
    return $self->{"hmmdb"};
}

sub get_remote_scripts{
    my $self = shift;
    return $self->{"rscripts"};
}

sub get_remote_connection{
    my $self = shift;
    my $username = $self->get_remote_username();
    my $server   = $self->get_remote_server();
    my $connection = $username . "@" . $server;
    return $connection;
}

sub build_remote_ffdb{
    my $self    = shift;
    my $verbose = shift;
    my $rffdb   = $self->{"rffdb"};
    my $connection = $self->get_remote_connection();
    #the -p flag won't produce errors or overwrite if existing, so simply always run this.
    my $command = "mkdir -p " . $rffdb;	
    $self->MRC::Run::execute_ssh_cmd( $connection, $command, $verbose );   
    $command = "mkdir -p " . $rffdb . "/projects/";
    $self->MRC::Run::execute_ssh_cmd( $connection, $command );   
    $command = "mkdir -p " . $rffdb . "/HMMdbs/";
    $self->MRC::Run::execute_ssh_cmd( $connection, $command );   
    return $self;
}

sub set_remote_hmmscan_script{
    my $self     = shift;
    my $filepath = shift; 
    $self->{"r_hmmscan_script"} = $filepath;
    return $self;
}

sub get_remote_hmmscan_script{
    my $self = shift;
    return $self->{"r_hmmscan_script"};
}

sub set_remote_project_log_dir{
    my $self     = shift;
    my $filepath = shift;
    $self->{"r_project_logs"} = $filepath;
    return $self;
}

sub get_remote_project_log_dir{
    my $self = shift;
    return $self->{"r_project_logs"};
}

sub is_remote{
    my $self = shift;
    my $switch = shift;
    if( defined( $switch ) ){
	$self->{"is_remote"} = $switch;
    }
    return $self->{"is_remote"};
}

sub is_strict_clustering{
    my $self = shift;
    my $switch = shift;
    if( defined( $switch ) ){
	$self->{"is_strict"} = $switch;
    }
    return $self->{"is_strict"};
}

sub set_evalue_threshold{
    my ( $self, $value ) = @_;
    $self->{"t_evalue"} = $value;
    return $self->{"t_evalue"};
}

sub get_evalue_threshold{
    my $self = shift;
    return $self->{"t_evalue"};
}

sub set_coverage_threshold{
    my ( $self, $value ) = @_;
    $self->{"t_coverage"} = $value;
    return $self->{"t_coverage"};
}

sub get_coverage_threshold{
    my $self = shift;
    return $self->{"t_coverage"};
}

1;
