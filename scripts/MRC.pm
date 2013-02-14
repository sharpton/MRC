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

use strict;
use warnings;

package MRC;

use MRC::DB;
use MRC::Run;
use Sfams::Schema;
use IMG::Schema;
use Data::Dumper;
use File::Basename;

my $USE_COLORS_CONSTANT = 1; ## Set this to '0' to avoid printing colored output to the terminal, or '1' to print colored output.

sub tryToLoadModule($) {
    my $x = eval("require $_[0]");
    if ((defined($@) && $@)) {
	warn "Module loading of $_[0] FAILED. Skipping this module.";
	return 0;
    } else {
	$_[0]->import();
	return 1;
    }
}

if (!tryToLoadModule("Term::ANSIColor")) {
    $USE_COLORS_CONSTANT = 0; # Failed to load the ANSI color terminal, so don't use colors!
}

sub safeColor($;$) { # one required and one optional argument
    ## Prints colored text, but only if USER_COLORS_CONSTANT is set.
    ## Allows you to totally disable colored printing by just changing USE_COLORS_CONSTANT to 0 at the top of this file
    my ($str, $color) = @_;
    return (($USE_COLORS_CONSTANT) ? Term::ANSIColor::colored($str, $color) : $str);
}

sub dryNotify(;$) { # one optional argument
    my ($msg) = @_;
    $msg = (defined($msg)) ? $msg : "This was only a dry run, so we skipped executing a command.";
    chomp($msg);
    print STDERR safeColor("[DRY RUN]: $msg\n", "black on_yellow");
}

sub notifyAboutScp($) {
    my ($msg) = @_;
    chomp($msg);
    my $parentFunction = defined((caller(2))[3]) ? (caller(2))[3] : '';
    print STDERR (safeColor("[SCP]: $parentFunction: $msg\n", "green on_black")); ## different colors from normal notification message
    # no point in printing the line number for an SCP command, as they all are executed from Run.pm anyway
}

sub notifyAboutRemoteCmd($) {
    my ($msg) = @_;
    chomp($msg);
    my $parentFunction = defined((caller(2))[3]) ? (caller(2))[3] : '';
    print STDERR (safeColor("[REMOTE CMD]: $parentFunction: $msg\n", "black on_green")); 
    ## different colors from normal notification message
    # no point in printing the line number for a remote command, as they all are executed from Run.pm anyway
}

sub notify($) { # one required argument
    my ($msg) = @_;
    chomp($msg);
    print STDERR (safeColor("[NOTE]: $msg\n", "cyan on_black"));
}



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
    $self->{"fci"}         = undef; #family construction ids that are allowed to be processed. array reference
    $self->{"workdir"}     = undef; #master path to MRC scripts
    $self->{"ffdb"}        = undef; #master path to the flat file database
    $self->{"ffdb"}        = undef; #master path to the reference dabase flat file data is located
    $self->{"dbi"}         = undef; #DBI string to interact with DB
    $self->{"user"}        = undef; #username to interact with DB
    $self->{"pass"}        = undef; #password to interact with DB
    $self->{"projectpath"} = undef;
    $self->{"projectname"} = undef;
    $self->{"project_id"}  = undef;
    $self->{"proj_desc"}   = undef;
    $self->{"samples"}     = undef; #hash relating sample names to paths   
    $self->{"rusername"}   = undef;
    $self->{"r_ip"}                 = undef;
    $self->{"remote_script_dir"}    = undef;
    $self->{"rffdb"}       = undef;
    $self->{"fid_subset"}  = undef; #an array of famids
    $self->{"schema"}      = undef; #current working DB schema object (DBIx)    
    $self->{"hmmdb"}       = undef; #name of the hmmdb to use in this analysis
    $self->{"blastdb"}     = undef; #name of the blastdb to use in this analysis
    $self->{"is_remote"}   = 0;     #does analysis include remote compute? 0 = no, 1 = yes
    $self->{"is_strict"}   = 1;     #strict (top hit) v. fuzzy (all hits passing thresholds) clustering. 1 = strict. 0 = fuzzy. Fuzzy not yet implemented!
    $self->{"t_evalue"}    = undef; #evalue threshold for clustering
    $self->{"t_coverage"}  = undef; #coverage threshold for clustering
    $self->{"r_hmmscan_script"}   = undef; #location of the remote hmmscan script. holds a path string.
    $self->{"r_hmmsearch_script"} = undef; #location of the remote hmmsearch script. holds a path string.
    $self->{"r_blast_script"}     = undef; #location of the remote blast script. holds a path string.
    $self->{"r_last_script"}      = undef; #location of the remote last script. holds a path string.
    $self->{"r_formatdb_script"}  = undef; #location of the remote formatdb script (for blast). holds a path string.
    $self->{"r_lastdb_script"}    = undef; #location of the remote lastdb script (for last). holds a path string.
    $self->{"r_project_logs"}     = undef; #location of the remote project logs directory. holds a path string.
    $self->{"multiload"}          = 0; #should we multiload our insert statements?
    $self->{"bulk_insert_count"}  = undef; #how many rows should be added at a time when using multi_load?
    $self->{"schema_name"}        = undef; #stores the schema module name, e.g., Sfams::Schema
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

sub get_scripts_dir{
    my $self = shift;
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

sub set_ref_ffdb{
    my $self = shift;
    my $path = shift;
    if( !defined( $path ) ){
      warn "No ref_ffdb path specified for set_ref_ffdb in MRC.pm. Cannot continue!\n";
      die;
    }
    if( !( -e $path ) ){
      warn "The method set_ffdb cannot access ref_ffdb path $path. Cannot continue!\n";
      die;
    }
    $self->{"ref_ffdb"} = $path;
    return $self->{"ref_ffdb"};
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

sub get_ffdb()     {  my $self = shift;  return $self->{"ffdb"};}
sub get_ref_ffdb() {  my $self = shift;  return $self->{"ref_ffdb"};}

=head2 set_dbi_connection

 Title   : set_dbi_connection
 Usage   : $analysis->set_dbi_conection( "DBI:mysql:IMG" );
 Function: Create a connection with mysql (or other) database
 Example : my $connection = analysis->set_dbi_connection( "DBI:mysql:IMG" );
 Returns : A DBI connection string (scalar, optional)
 Args    : A DBI connection string (scalar)

=cut

sub set_dbi_connection {
    my ($self, $dbipath, $database_name, $db_hostname) = @_;
    $self->{"dbi"} = $dbipath;
    $self->{"db_name"}     = $database_name; # <-- usually something like "Sfams_tmp" or whatever. Allowed to be UNDEFINED!
    $self->{"db_hostname"} = $db_hostname; # <-- something like "test.myserver.com". Allowed to be UNDEFINED!
}

sub get_db_name()        { my $self = shift; return $self->{"db_name"}; }
sub get_db_hostname()    { my $self = shift; return $self->{"db_hostname"}; }
sub get_dbi_connection() { my $self = shift; return $self->{"dbi"}; }


sub set_multiload {
    my ($self, $multi) = @_;
    if ($multi != 0 && $multi != 1) { die "The multi variable must be either 0 or 1!"; }
    $self->{"multiload"} = $multi;
}
sub is_multiload() { # supposed to be a true/false value
    my ($self) = @_;
    return($self->{"multiload"});
}


sub get_bulk_insert_count{
    my $self = shift;
    return $self->{"bulk_insert_count"};
}

sub set_bulk_insert_count{
    my ($self, $count) = @_;
    $self->{"bulk_insert_count"} = $count;
}

=head2 set_project_path

 Title   : set_project_path
 Usage   : $analysis->set_project_path( "~/data/metaprojects/project1/" );
 Function: Point to the raw project data directory (not the ffdb version)
 Example : my $path = analysis->set_project_path( "~/data/metaprojects/project1/" );
 Returns : A filepath (string)
 Args    : A filepath (string)

=cut 

sub set_project_path{
    my $self = shift;
    my $path = shift;
    $self->{"projectpath"} = $path;
    return $self->{"projectpath"};
}

=head2 get_project_path

 Title   : get_project_path
 Usage   : $analysis->get_project_path();
 Function: Point to the raw project data directory (not the ffdb version)
 Example : my $path = analysis->get_project_path();
 Returns : A filepath (string)
 Args    : None

=cut 

sub get_project_path{
    my $self = shift;
    return $self->{"projectpath"};
}

=head2 get_sample_path

 Title   : get_sample_path
 Usage   : $analysis->get_sample_path( $sample_id );
 Function: Retrieve a sample's ffdb filepath
 Example : my $path = analysis->get_sample_path( 7201 );
 Returns : A filepath (string)
 Args    : A sample_id

=cut 

sub get_sample_path{
    my $self = shift;
    my $sample_id = shift;
    my $sample_path = $self->get_ffdb() . "/projects/" . $self->get_project_id() . "/". $sample_id . "/";
    return $sample_path;
}

=head2 set_username 

 Title   : set_username
 Usage   : $analysis->set_username( $username );
 Function: Set the MySQL username
 Example : my $username = $analysis->set_username( "joebob" );
 Args    : A username (string)

=cut 

sub set_username { # note: this is the MYSQL username!
    my ($self, $user) = @_; $self->{"user"} = $user;
}
sub get_username() { my $self = shift; return $self->{"user"}; }

=head2 set_password

 Title   : set_password
 Usage   : $analysis->set_password( $password );
 Function: Set the MySQL password
 Example : my $username = $analysis->set_password( "123456abcde" );
 Args    : A password (string)

=cut 

#NOTE: This is pretty dubious! Need to add encryption/decryption function before official release

sub set_password{
    my $self = shift;
    my $path = shift;
    warn "In MRC.pm (function: set_password()): Note: we are setting the password in plain text here. This should ideally be eventually changed to involve encryption or something.";
    $self->{"pass"} = $path;
}

sub get_password { my $self = shift; return $self->{"pass"}; }

sub set_schema_name{
    my ($self, $new_name) = @_;
    if ($new_name =~ m/::Schema$/) { ## <-- does the new schema end in the literal text '::Schema'?
	$self->{"schema_name"} = $new_name; # Should end in ::Schema . "::Schema";
    } else {
	warn("Note: you passed the schema name in as \"$new_name\", but names should always end in the literal text \"::Schema\". So we have actually modified the input argument, now the schema name is being set to: \"$new_name::Schema\" ");
	$self->{"schema_name"} = $new_name . "::Schema"; # Append "::Schema" to the name.
    }
}

=head2 build_schema

 Title   : build_schema
 Usage   : $analysis->build_schema();
 Function: Construct the DBIx schema for the DB that MRC interfaces with. Store it in the MRC object
 Example : my $schema = $analysis->build_schema();
 Returns : A DBIx schema
 Args    : None, but requires that set_username, set_password and set_dbi_connection have been called first

=cut

sub build_schema{
    my $self   = shift;
#    my $schema = Sfams::Schema->connect( $self->{"dbi"}, $self->{"user"}, $self->{"pass"},
    my $schema = $self->{"schema_name"}->connect( $self->{"dbi"}, $self->{"user"}, $self->{"pass"},
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

=head2 get_schema

 Title   : get_schema
 Usage   : $analysis->get_schema();
 Function: Obtain the DBIx schema for the database MRC interfaces with
 Example : my $schema = $analysis->get_schema( );
 Returns : A DBIx schema object
 Args    : None

=cut 

sub get_schema{
    my $self = shift;
    my $schema = $self->{"schema"};
    return $schema;
}

=head2 set_project_id

 Title   : set_project_id
 Usage   : $analysis->set_project_id( $project_id );
 Function: Store the project's database identifier (project_id) in the MRC object
 Example : my $project_id = MRC::DB::insert_project();
           $analysis->set_project_id( $project_id );
 Returns : The project_id (scalar)
 Args    : The project_id (scalar)

=cut 

#NOTE: Check that the MRC::DB::insert_project() function is named/called correctly above

sub set_project_id{
    my ($self, $pid) = @_;
    if (!defined($pid)) {
      warn "No project id specified in set_project_id. Cannot continue!\n";
      die "No project id specified in set_project_id. Cannot continue!\n";
    }
    $self->{"project_id"} = $pid;
}

=head2 get_project_id

 Title   : get_project_id
 Usage   : $analysis->get_project_id();
 Function: Get the project's DB identifier (project_id) from the MRC object. Does not touch the DB.
 Example : my $project_id = $analysis->get_project_id( );
 Returns : The project_id (scalar)
 Args    : None

=cut 

sub get_project_id{
    my $self = shift;
    return $self->{"project_id"};
}

=head2 set_family_subset

 Title   : set_family_subset
 Usage   : $analysis->set_family_subset( $subset_file_path, $check_fci );
 Function: Determine which families should be used in this analysis. Can either specify a set of families via a file (one 
           famid per line)or select all families associated with various family construction ids. Note that the fci array 
           must be set in the MRC object prior to calling this function. If a subset is specified, you have the option of 
           checking whether the families in the file are from the construction_ids that you have set in the MRC object.
 Example : my @families = @{ $analysis->get_family_subset( "~/data/large_family_ids, 1 ) };
 Returns : An array reference of family ids that will be used in the downstream analyses
 Args    : Subset file path (string), Binary for whether fci should be checked. Both are optional.

=cut 

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

=head2 get_family_subset

 Title   : get_family_subset
 Usage   : $analysis->get_family_subset( );
 Function: Obtain a list of family ids that will be used in this analysis. See set_family_subset for more information on this list
 Example : my @families = @{ $analysis->get_family_subset( ) };
 Returns : An array reference of family ids that will be used in the downstream analyses
 Args    : None

=cut 

sub get_family_subset{
    my $self = shift;
    return $self->{"fid_subset"};
}

=head2 set_samples

 Title   : set_samples
 Usage   : $analysis->set_samples( $sample_paths_hash_ref );
 Function: Store a hash that relates sample names to sample ffdb paths in the MRC object   
 Example : my $hash_ref = $analysis->set_samples( \%sample_paths );
 Returns : A hash_ref of sample names to sample ffdb paths (hash reference)
 Args    : A hash_ref of sample names to sample ffdb paths (hash reference)

=cut 

sub set_samples{
    my $self = shift;
    my $samples = shift;
    $self->{"samples"} = $samples;
    return $self->{"samples"};
}

=head2 get_samples

 Title   : get_samples
 Usage   : $analysis->get_samples()
 Function: Retrieve a hash reference that relates sample names to sample ffdb path from the MRC object
 Example : my %samples = %{ $analysis->get_samples() };
 Returns : A hash_ref of sample names to sample ffdb paths (hash reference)
 Args    : None

=cut 

sub get_samples{
    my $self = shift;
    my $samples = $self->{"samples"}; #a hash reference
    return $samples;
}

=head2 set_project_desc

 Title   : set_project_desc
 Usage   : $analysis->set_project_desc( $projet_description_text );
 Function: Obtain the project description and store in the MRC object
 Example : my $description = $analysis->set_project_description( "A metagenomic study of the Global Open Ocean, 28 samples total" );
 Returns : The project description (string)
 Args    : The project description (string)

=cut 

sub set_project_desc{
    my $self = shift;
    my $text = shift;
    $self->{"proj_desc"} = $text;
    return $self->{"proj_desc"};    
}

=head2 get_project_desc

 Title   : get_project_desc
 Usage   : $analysis->get_project_desc( );
 Function: Obtain the project description from the MRC object. The DB is not touched here.
 Example : my $description = $analysis->get_project_desc();
 Returns : The project description (string)
 Args    : None

=cut 

sub get_project_desc{
    my $self = shift;
    my $desc = $self->{"proj_desc"};
    return $desc;
}

=head2 set_hmmdb_name
 Function: Set the name of the hmm database you want to use. Should be unique if you want to build a new database
 Example : my $remote_scripts_path = $analysis->get_hmmdb_name( "ALL_HMMS_FCI_1" );
 Args    : The name of the hmm database to use (string) 

=cut 

sub set_hmmdb_name {
    my ($self, $name) = @_;
    (defined($name) && length($name) > 0) or die "Invalid argument: You passed in an empty value apparently.";
    $self->{"hmmdb"} = $name;
}
sub get_hmmdb_name {     my $self = shift;  return $self->{"hmmdb"};   }

sub set_blastdb_name {
    my ($self, $name) = @_; 
    (defined($name) && length($name) > 0) or die "Invalid argument: You passed in an empty value apparently.";
    $self->{"blastdb"} = $name;
}
sub get_blastdb_name {   my $self = shift;  return $self->{"blastdb"}; }




=head2 set_remote_server

 Title   : set_remote_server
 Usage   : $analysis->set_remote_server( $remote_hostname );
 Function: Set the ip address (hostname) of the remote server in the MRC object
 Example : my $remote_host = $analysis->set_remote_server( "compute.awesomeuniversity.edu" );
 Returns : The remote hostname (ip address)
 Args    : The remote hostname (ip address)

=cut 

sub set_remote_server{
    my $self        = shift;
    my $r_ip        = shift;
    $self->{"r_ip"} = $r_ip;
    return $self->{"r_ip"};
}

=head2 get_remote_server

 Title   : get_remote_server
 Usage   : $analysis->get_remote_server( );
 Function: Get the ip address (hostname) of the remote server from the MRC object
 Example : my $remote_host = $analysis->get_remote_server( ); 
 Returns : The remote hostname (ip address)
 Args    : None 

=cut 

sub get_remote_server{
    my $self = shift;
    return $self->{"r_ip"};
}

=head2 set_remote_username

 Title   : set_remote_username
 Usage   : $analysis->set_remote_username( );
 Function: Set the username of the remote account being used in the MRC object. Note that this software assumes that
           you are using ssh keys to connect. Thus, no password is ever set in the software to connect to remote machine.
 Example : my $remote_username = $analysis->set_remote_username( "joebob" ); 
 Returns : The remote username (string)
 Args    : The remote username (string)

=cut 

sub set_remote_username{
    my $self      = shift;
    my $rusername = shift;
    $self->{"rusername"} = $rusername;
    return $self->{"rusername"};
}

=head2 get_remote_username

 Title   : get_remote_username
 Usage   : $analysis->get_remote_username( );
 Function: Get the username of the remote account being used grom the MRC object. Note that this software assumes that
           you are using ssh keys to connect. Thus, no password is ever set in the software to connect to remote machine.
 Example : my $remote_username = $analysis->set_remote_username( ); 
 Returns : The remote username (string)
 Args    : None

=cut 

sub get_remote_username{
    my $self = shift;
    return $self->{"rusername"};
}

=head2 set_remote_ffdb

 Title   : set_remote_ffdb
 Usage   : $analysis->set_remote_ffdb( );
 Function: Set the location (filepath) of the remote flat file database in the MRC object.
 Example : my $remote_ffdb = $analysis->set_remote_ffdb( "~/path/to/remote/ffdb/" ); 
 Returns : The remote ffdb filepath (string)
 Args    : The remote ffdb filepath (string)

=cut 

sub set_remote_ffdb{
    my $self = shift;
    my $rffdb = shift;
    $self->{"rffdb"} = $rffdb;
    return $self->{"rffdb"};
}

=head2 get_remote_ffdb

 Title   : get_remote_ffdb
 Usage   : $analysis->get_remote_ffdb( );
 Function: Get the location (filepath) of the remote flat file database from the MRC object.
 Example : my $remote_ffdb = $analysis->set_remote_ffdb();
 Returns : The remote ffdb filepath (string)
 Args    : None

=cut 

sub get_remote_ffdb{
    my $self = shift;
    return $self->{"rffdb"};
}

=head2 get_remote_project_path

 Title   : get_remote_project_path
 Usage   : $analysis->get_remote_project_path( );
 Function: Get the location (filepath) of the project in the remote flat file database from the MRC object.
 Example : my $remote_project_path = $analysis->get_remote_project_path();
 Returns : The remote project filepath (string)
 Args    : None

=cut 

sub get_remote_project_path{
   my ($self) = @_;
   (defined($self->get_remote_ffdb())) or warn "get_remote_project_path: Remote ffdb path was NOT defined at this point, but we requested it anyway!\n";
   (defined($self->get_project_id())) or warn "get_remote_project_path: Project ID was NOT defined at this point, but we requested it anyway!.\n";
   my $path = $self->get_remote_ffdb() . "/projects/" . $self->get_project_id() . "/";
   return $path;
}

=head2 get_remote_sample_path

 Title   : get_remote_sample_path
 Usage   : $analysis->get_remote_sample_path( );
 Function: Given a sample id, get the location (filepath) of the sample in the remote flat file database from the MRC object.
 Example : my $remote_sample_path = $analysis->get_remote_sample_path();
 Returns : The remote sample filepath (string)
 Args    : A sample id (scalar)

=cut 

sub get_remote_sample_path{
    my ( $self, $sample_id ) = @_;
    my $path = $self->get_remote_ffdb() . "/projects/" . $self->get_project_id() . "/" . $sample_id . "/";
    return $path;
}



sub set_remote_script_dir{
    my ($self, $remote_script_dir) = @_;
    $self->{"remote_script_dir"} = $remote_script_dir;
}
sub get_remote_script_dir{ # remote script DIRECTORY
    my ($self) = @_;
    return $self->{"remote_script_dir"}; # remote script directory
}

=head2 get_remote_connection

 Title   : get_remote_connection
 Function: Get the connection string to the remote host (i.e., username@hostname). Must have set remote_username and
           remote_server before running this command
 Returns : A connection string(string) 
=cut 
sub get_remote_connection{
    my ($self) = @_;
    return($self->get_remote_username() . "@" . $self->get_remote_server());
}

=head build_remote_ffdb

 Title   : build_remote_ffdb
 Usage   : $analysis->build_remote_ffdb();
 Function: Makes some directories on the remote host. Build the ffdb on the remote host. Includes setting up projects/, HMMdbs/ dirs if they don't exist. Must have set
           the location of the remote ffdb and have a complete connection string to the remote host.
 Example : $analysis->build_remote_ffdb();
 Args    : (optional) $verbose: true/false (whether or not to print verbose output)

=cut 

sub build_remote_ffdb {
    my ($self, $verbose) = @_;
    my $rffdb      = $self->{"rffdb"};
    my $connection = $self->get_remote_connection();
    MRC::Run::execute_ssh_cmd( $connection, "mkdir -p $rffdb"          , $verbose); # <-- 'mkdir' with the '-p' flag won't produce errors or overwrite if existing, so simply always run this.
    MRC::Run::execute_ssh_cmd( $connection, "mkdir -p $rffdb/projects", $verbose);
    MRC::Run::execute_ssh_cmd( $connection, "mkdir -p $rffdb/HMMdbs"  , $verbose);   
    MRC::Run::execute_ssh_cmd( $connection, "mkdir -p $rffdb/BLASTdbs", $verbose);
}

=head set_remote_hmmscan_script

 Title   : set_remote_hmmscan_script
 Usage   : $analysis->set_remote_hmmscan_script();
 Function: Set the location of the script that is located on the remote server that runs the hmmscan jobs
 Example : my $filepath = $analysis->set_remote_hmmscan_script( "~/projects/MRC/scripts/run_hmmscan.sh" )
 Returns : A filepath to the script (string)
 Args    : A filepath to the script (string)

=cut 

sub set_remote_hmmscan_script{
    my $self     = shift;
    my $filepath = shift; 
    $self->{"r_hmmscan_script"} = $filepath;
    return $self;
}

sub set_remote_hmmsearch_script{
    my $self     = shift;
    my $filepath = shift; 
    $self->{"r_hmmsearch_script"} = $filepath;
    return $self;
}


sub set_remote_blast_script{
    my $self     = shift;
    my $filepath = shift; 
    $self->{"r_blast_script"} = $filepath;
    return $self;
}

sub set_remote_last_script{
    my $self     = shift;
    my $filepath = shift; 
    $self->{"r_last_script"} = $filepath;
    return $self;
}


sub set_remote_formatdb_script{
    my $self     = shift;
    my $filepath = shift; 
    $self->{"r_formatdb_script"} = $filepath;
    return $self;
}

sub set_remote_lastdb_script{
    my $self     = shift;
    my $filepath = shift; 
    $self->{"r_lastdb_script"} = $filepath;
    return $self;
}

=head get_remote_hmmscan_script

 Title   : get_remote_hmmscan_script
 Usage   : $analysis->get_remote_hmmscan_script();
 Function: Get the location of the script that is located on the remote server that runs the hmmscan jobs
 Example : my $filepath = $analysis->get_remote_hmmscan_script();
 Returns : A filepath to the script (string)
 Args    : None

=cut 

sub get_remote_hmmscan_script{
    my $self = shift;
    return $self->{"r_hmmscan_script"};
}


sub get_remote_hmmsearch_script{
    my $self = shift;
    return $self->{"r_hmmsearch_script"};
}


sub get_remote_blast_script{
    my $self = shift;
    return $self->{"r_blast_script"};
}

sub get_remote_last_script{
    my $self = shift;
    return $self->{"r_last_script"};
}

sub get_remote_lastdb_script{
    my $self = shift;
    return $self->{"r_lastdb_script"};
}


=head set_remote_project_log_dir

 Title   : set_remote_project_log_dir
 Usage   : $analysis->set_remote_project_log_dir();
 Function: Set the location of the directory that is located on the remote server that will contain the run logs
 Example : my $filepath = $analysis->set_remote_project_log_dir( "~/projects/MRC/scripts/logs" );
 Returns : A filepath to the directory (string)
 Args    : A filepath to the directory (string)

=cut 

sub set_remote_project_log_dir{
    my $self     = shift;
    my $filepath = shift;
    $self->{"r_project_logs"} = $filepath;
    return $self;
}

=head get_remote_project_log_dir

 Title   : get_remote_project_log_dir
 Usage   : $analysis->get_remote_project_log_dir();
 Function: Get the location of the directory that is located on the remote server that will contain the run logs
 Example : my $filepath = $analysis->get_remote_project_log_dir();
 Returns : A filepath to the directory (string)
 Args    : None

=cut 

sub get_remote_project_log_dir{
    my $self = shift;
    return $self->{"r_project_logs"};
}

=head is_remote

 Title   : is_remote
 Usage   : $analysis->is_remote( 1 )
 Function: If the project will use a remote compute infrastructure, set this switch
 Example : my $is_remote = $analysis->is_remote( 1 );
 Returns : A binary of whether the project uses a remote infrastructure (binary)
 Args    : A binary of whether the project uses a remote infrastructure (binary)

=cut 

sub is_remote{
    my $self = shift;
    my $switch = shift;
    if( defined( $switch ) ){
	$self->{"is_remote"} = $switch;
    }
    return $self->{"is_remote"};
}

=head is_strict_clustering

 Title   : is_strict_clustering
 Usage   : $analysis->is_strict_clustering( 1 );
 Function: If the project uses strict clustering, set this switch. Future implementation may alternatively enable
           fuzzy clustering. Maybe.
 Example : my $is_strict = $analysis->is_strict_clustering( 1 );
 Returns : A binary of whether the project uses strict clusterting (binary)
 Args    : A binary of whether the project uses strict clusterting (binary)

=cut 

sub is_strict_clustering{
    my $self = shift;
    my $switch = shift;
    if( defined( $switch ) ){
	$self->{"is_strict"} = $switch;
    }
    return $self->{"is_strict"};
}

=head set_evalue_threshold

 Title   : set_evalue_threshold
 Usage   : $analysis->set_evalue_threshold( 0.001 );
 Function: What evalue threshold should be used to assess classification of reads into families?
 Example : my $e_value = $analysis->set_evalue_threshold( 0.001 );
 Returns : An evalue (float)
 Args    : An evalue (float)

=cut 

sub set_evalue_threshold{
    my ( $self, $value ) = @_;
    $self->{"t_evalue"} = $value;
    return $self->{"t_evalue"};
}

=head get_evalue_threshold

 Title   : get_evalue_threshold
 Usage   : $analysis->get_evalue_threshold( );
 Function: Get the evalue threshold used to assess classification of reads into families
 Example : my $e_value = $analysis->set_evalue_threshold();
 Returns : An evalue (float)
 Args    : None

=cut 

sub get_evalue_threshold{
    my $self = shift;
    return $self->{"t_evalue"};
}

=head set_coverage_threshold

 Title   : set_coverage_threshold
 Usage   : $analysis->set_coveragethreshold( );
 Function: Set the coverage threshold used to assess classification of reads into families
 Example : my $coverage = $analysis->set_coverage_threshold();
 Returns : A coverage threshold (float)
 Args    : A coverage threshold (float)

=cut 

#Note: double check this is a float and not a percentage!

sub set_coverage_threshold{
    my ( $self, $value ) = @_;
    $self->{"t_coverage"} = $value;
    return $self->{"t_coverage"};
}

=head get_coverage_threshold

 Title   : get_coverage_threshold
 Usage   : $analysis->get_coveragethreshold( );
 Function: Get the coverage threshold used to assess classification of reads into families
 Example : my $coverage = $analysis->get_coverage_threshold();
 Returns : A coverage threshold (float)
 Args    : None

=cut 

#Note: double check this is a float and not a percentage!

sub get_coverage_threshold{
    my $self = shift;
    return $self->{"t_coverage"};
}

sub set_score_threshold{
    my ( $self, $value ) = @_;    
    $self->{"t_score"} = $value;
    return $self->{"t_score"};
}

sub get_score_threshold{
    my $self = shift;
    return $self->{"t_score"};
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
    my $self    = shift;
    my $ra_fcis = shift;
    my @fcis    = @{ $ra_fcis };
    if( !@fcis ){
	warn "No fci value(s) supplied for set_fcis in MRC.pm.\n";
	exit(0)
    }
    $self->{"fci"} = \@fcis;
    return $self->{"fci"};
}

sub get_fcis{
    my $self = shift;
    return $self->{"fci"};
}

1;
