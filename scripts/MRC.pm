#!/usr/bin/perl -w

#MRC.pm - The MRC workflow manager

package MRC;

use strict;
use IMG::Schema;
use Data::Dumper;
use File::Basename;

#main
sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    my @fcis  = (6);
    $self->{"fci"}     = \@fcis; #family construction ids that are allowed to be processed
    $self->{"workdir"} = undef; #master path to MRC scripts
    $self->{"ffdb"} = undef; #master path to the flat file database
    $self->{"dbi"}  = undef; #DBI string to interact with DB
    $self->{"user"} = undef; #username to interact with DB
    $self->{"pass"} = undef; #password to interact with DB
    $self->{"schema"} = undef; #current working DB schema object (DBIx)
    $self->{"projectpath"} = undef;
    $self->{"projectname"} = undef;
    $self->{"project_id"}  = undef;
    $self->{"samples"}     = undef; #hash relating sample names to paths
    
    bless($self);
    return $self;
}

sub set_fcis{
  my $self = shift;
  my @fcis = @_;
  if( !defined( @fcis ) ){
    warn "No fci value(s) supplied for set_fcis in MRC.pm. Using default value of ", @{ $self->{"fci"} }, ".\n";
  }
  $self->{"fci"} = \@fcis;
  return $self->{"fci"};
}

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

sub get_ffdb{
  my $self = shift;
  return $self->{"ffdb"};
}

sub set_dbi_connection{
    my $self = shift;
    my $path = shift;
    $self->{"dbi"} = $path;
    return $self->{"dbi"};
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
    my $schema = IMG::Schema->connect( $self->{"dbi"}, $self->{"user"}, $self->{"pass"} );
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

sub get_subset_famids{
    my $self = shift;
    return $self->{"fid_subset"};
}

1;
