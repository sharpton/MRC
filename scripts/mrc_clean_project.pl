#!/usr/bin/perl -w

use lib ($ENV{'MRC_LOCAL'} . "/scripts"); ## Allows "MRC.pm" to be found in the $MRC_LOCAL directory
use lib ($ENV{'MRC_LOCAL'} . "/lib"); ## Allows "Schema.pm" to be found in the $MRC_LOCAL directory. DB.pm needs this.

use strict;
use MRC;
use MRC::Run;
use MRC::DB;
use Getopt::Long;

if (!exists($ENV{'MRC_LOCAL'})) {
    print STDOUT ("[ERROR]: The MRC_LOCAL environment variable was NOT EXPORTED and is UNDEFINED.\n");
    print STDOUT ("[ERROR]: MRC_LOCAL needs to be defined as the local code directory where the MRC files are located.\n");
    print STDOUT ("[ERROR]: This is where you'll do the github checkout, if you haven't already.\n");
    print STDOUT ("[ERROR]: I recommend setting it to a location in your home directory. Example: export MRC_LOCAL='/some/location/MRC'\n");
    die "Environment variable MRC_LOCAL must be EXPORTED. Example: export MRC_LOCAL='/path/to/your/directory/for/MRC'\n";
}

my $project_id    = undef;
my $dbusername    = undef;
my $dbpassword    = undef;
my $db_hostname   = undef;  #"lighthouse.ucsf.edu";
my $ffdb          = undef;  #= "/bueno_not_backed_up/sharpton/MRC_ffdb/";
my $database_name = undef; #"Sfams_lite";
my $schema_name   = undef; #"Sfams::Schema";

# Alex: options have been normalized to use the same arguments as mrc_handler.pl
GetOptions(
    "pid|i=i"      => \$project_id
    , "dbuser|u=s" => \$dbusername
    , "dbpass|p=s" => \$dbpassword
    , "dbhost=s"   => \$db_hostname
    , "ffdb|d=s" => \$ffdb
    , "dbname=s" => \$database_name
    , "schema=s" => \$schema_name
    );

defined($project_id) or die "--pid must be defined!";
defined($dbusername) or die "--dbuser must be defined!";
defined($dbpassword) or die "--dbpass must be defined!";
defined($db_hostname) or die "--dbhost must be defined!";
defined($ffdb) or die "--ffdb must be defined!";
defined($database_name) or die "--dbname must be defined!";
defined($schema_name) or die "--schema must be defined!";


my $analysis = MRC->new();
$analysis->set_dbi_connection("DBI:mysql:$database_name:$db_hostname", $database_name, $db_hostname);
$analysis->set_username( $dbusername ); $analysis->set_password( $dbpassword );
$analysis->set_schema_name( $schema_name );
$analysis->build_schema();
$analysis->set_ffdb( $ffdb );
$analysis->MRC::Run::clean_project( $project_id );


print STDOUT "Looks like we SUCCESSFULLY cleared out project ID #$project_id from the database.\n(Or it possibly wasn't even there to begin with--this is not actually checked.)\n";
print STDOUT "You can verify this by connecting and running 'select project_id from project;' in mysql---ID #$project_id should no longer be there.\n";

print STDOUT "Note that the 'samples' table may still have an identically-named (but with a different project ID) database. This would still need to be MANUALLY cleared out, possibly!\n";
