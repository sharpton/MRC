#!/usr/bin/perl -w

use lib ($ENV{'MRC_LOCAL'} . "/scripts"); ## Allows "MRC.pm" to be found in the MRC_LOCAL directory
use lib ($ENV{'MRC_LOCAL'} . "/lib"); ## Allows "Schema.pm" to be found in the MRC_LOCAL directory. DB.pm needs this.

use strict;
use warnings;
use MRC;
use MRC::DB;
use MRC::Run;
use Getopt::Long qw(GetOptionsFromString);
use Data::Dumper;

#usage: perl post_load_reads.pl --conf-file=<conf_file> --pid=<project_id>

sub get_conf_file_options($$){
    my ( $conf_file, $options ) = @_;
    my $opt_str = '';
    print "Parsing configuration file <${conf_file}>. Note that command line options trump conf-file settings\n";
    open( CONF, $conf_file ) || die "can't open $conf_file for read: $!\n";
    while(<CONF>){
	chomp $_;
	if( $_ =~ m/^\-\-(.*)\=(.*)$/ ){
	    my $key = $1;
	    my $val = $2;
	    next if defined( ${ $options->{$key} } ); #command line opts trump 
	    $opt_str .= " --${key}=${val} ";
	} elsif( $_ =~ m/^\-\-(.*)$/ ){
	    my $key = $1;
	    next if defined( ${ $options->{$key} } ); #command line opts trump 
	    $opt_str .= " --$key ";
	}
    }
    close CONF;
    return $opt_str;
}

my $localScriptDir       = $ENV{'MRC_LOCAL'} . "/scripts" ; # <-- point to the location of the MRC scripts. Auto-detected from MRC_LOCAL variable.

my( $conf_file,            $local_ffdb,            $local_reference_ffdb, $project_dir,         $input_pid,
    $goto,                 $db_username,           $db_pass,              $db_hostname,         $dbname,
    $schema_name,          $db_prefix_basename,    $hmm_db_split_size,    $blast_db_split_size, $family_subset_list,  
    $reps_only,            $nr_db,                 $db_suffix,            $is_remote,           $remote_hostname,
    $remote_user,          $remoteDir,             $remoteExePath,        $use_scratch,         $waittime,
    $multi,                $mult_row_insert_count, $bulk,                 $bulk_insert_count,   $slim,
    $use_hmmscan,          $use_hmmsearch,         $use_blast,            $use_last,            $use_rapsearch,
    $nseqs_per_samp_split, $prerare_count,         $postrare_count,       $trans_method,        $should_split_orfs,
    $filter_length,        $p_evalue,              $p_coverage,           $p_score,             $evalue,
    $coverage,             $score,                 $top_hit,              $top_hit_type,        $stage,
    $hmmdb_build,          $blastdb_build,         $force_db_build,       $force_search,        $small_transfer,
    #non conf-file vars
    $verbose,
    $extraBrutalClobberingOfDirectories,
    $dryRun,
    $reload,
    );

$conf_file       = undef;

my %options = ("ffdb"         => \$local_ffdb
	       , "refdb"      => \$local_reference_ffdb
	       , "projdir"    => \$project_dir
	       # Database-server related variables
	       , "dbuser"     => \$db_username
	       , "dbpass"     => \$db_pass
	       , "dbhost"     => \$db_hostname
	       , "dbname"     => \$dbname
	       , "dbschema"   => \$schema_name
	       # FFDB Search database related options
	       , "searchdb-prefix"   => \$db_prefix_basename
	       , "hmmsplit"   => \$hmm_db_split_size
	       , "blastsplit" => \$blast_db_split_size
	       , "sub"        => \$family_subset_list	  
	       , "reps-only"  => \$reps_only
	       , "nr"         => \$nr_db
	       , "db_suffix"  => \$db_suffix
	       # Remote computational cluster server related variables
	       , "remote"     => \$is_remote
	       , "rhost"      => \$remote_hostname
	       , "ruser"      => \$remote_user
	       , "rdir"       => \$remoteDir
	       , "rpath"      => \$remoteExePath
	       , "scratch"    => \$use_scratch
	       , "wait"       => \$waittime        #   <-- in seconds
	       #db communication method (NOTE: use EITHER multi OR bulk OR neither)
	       ,    "multi"        => \$multi
	       ,    "multi_count"  => \$mult_row_insert_count
	       ,    "bulk"         => \$bulk
	       ,    "bulk_count"   => \$bulk_insert_count
	       ,    "slim"         => \$slim
	       #search methods
	       ,    "use_hmmscan"   => \$use_hmmscan
	       ,    "use_hmmsearch" => \$use_hmmsearch
	       ,    "use_blast"     => \$use_blast
	       ,    "use_last"      => \$use_last
	       ,    "use_rapsearch" => \$use_rapsearch
	       #general options
	       ,    "seq-split-size" => \$nseqs_per_samp_split
	       ,    "prerare-samps"  => \$prerare_count
	       ,    "postrare-samps" => \$postrare_count
	       #translation options
	       ,    "trans-method"   => \$trans_method
	       ,    "split-orfs"     => \$should_split_orfs
	       ,    "min-orf-len"    => \$filter_length
	       #search result parsing thresholds (less stringent, optional, defaults to family classification thresholds)
	       ,    "parse-evalue"   => \$p_evalue
	       ,    "parse-coverage" => \$p_coverage
	       ,    "parse-score"    => \$p_score
	       ,    "small-transfer" => \$small_transfer
	       #family classification thresholds (more stringent)
	       ,    "class-evalue"   => \$evalue
	       ,    "class-coverage" => \$coverage
	       ,    "class-score"    => \$score
	       ,    "top-hit"        => \$top_hit
	       ,    "hit-type"       => \$top_hit_type
    );

GetOptions(\%options
	   , "conf-file|c=s"         => \$conf_file
	   , "pid=i"                 => \$input_pid          
	   , "goto|g=s"              => \$goto     
	    , "ffdb|d=s"             , "refdb=s"            , "projdir|i=s"      
	    # Database-server related variables
	    , "dbuser|u=s"           , "dbpass|p=s"         , "dbhost=s"          , "dbname=s"        , "dbschema=s"   
	    # FFDB Search database related options
	    , "searchdb-prefix=s"           , "hmmsplit=i"         , "blastsplit=i"      , "sub=s"           , "reps-only!"      , "nr!"             , "db_suffix:s"  
	    # Remote computational cluster server related variables
	    , "remote!"              , "rhost=s"            , "ruser=s"           , "rdir=s"          , "rpath=s"         , "scratch!"        , "wait|w=i"    
	    #db communication method (NOTE: use EITHER multi OR bulk OR neither)
	    ,    "multi!"            ,    "multi_count:i"   ,    "bulk!"          ,    "bulk_count:i" ,    "slim!"         
	    #search methods
	    ,    "use_hmmscan!"       ,    "use_hmmsearch!"   ,    "use_blast!"      ,    "use_last!"     ,    "use_rapsearch!" 
	    #general options
	    ,    "seq-split-size=i"  ,    "prerare-samps:i" ,    "postrare-samps:i" 
	    #translation options
	    ,    "trans-method:s"    ,    "split-orfs!"     ,    "min-orf-len:i"    
	    #search result parsing thresholds (less stringent, optional, defaults to family classification thresholds)
 	   ,    "parse-evalue:f"    ,    "parse-coverage:f",    "parse-score:f"   ,    "small-transfer!"
	    #family classification thresholds (more stringent)
	    ,    "class-evalue:f"    ,    "class-coverage:f",    "class-score:f"   ,    "top-hit!"     ,    "hit-type:s"       

	   #forcing statements
	   ,    "stage!"       => \$stage # should we "stage" the database onto the remote machine?
	   ,    "hdb!"         => \$hmmdb_build
	   ,    "bdb!"         => \$blastdb_build
	   ,    "forcedb!"     => \$force_db_build
	   ,    "forcesearch!" => \$force_search
	   ,    "verbose|v!"   => \$verbose
	   ,    "clobber"      => \$extraBrutalClobberingOfDirectories
	   ,    "dryrun|dry!"  => \$dryRun
	   ,    "reload!"      => \$reload
    );

### =========== GRAB INPUTS FROM CONF FILE =================
#note: command line options TRUMP conf file options!
if( defined( $conf_file ) ){
    if( ! -e $conf_file ){ dieWithUsageError( "The path you supplied for --conf-file doesn't exist! You used <$conf_file>\n" ); }
    my $opt_str = get_conf_file_options( $conf_file, \%options );
    GetOptionsFromString( $opt_str, \%options,
	    , "ffdb|d=s"             , "refdb=s"            , "projdir|i=s"      
	    # Database-server related variables
	    , "dbuser|u=s"           , "dbpass|p=s"         , "dbhost=s"          , "dbname=s"        , "dbschema=s"   
	    # FFDB Search database related options
	    , "searchdb-prefix=s"           , "hmmsplit=i"         , "blastsplit=i"      , "sub=s"           , "reps-only!"      , "nr!"             , "db_suffix:s"  
	    # Remote computational cluster server related variables
	    , "remote!"              , "rhost=s"            , "ruser=s"           , "rdir=s"          , "rpath=s"         , "scratch!"        , "wait|w=i"    
	    #db communication method (NOTE: use EITHER multi OR bulk OR neither)
	    ,    "multi!"            ,    "multi_count:i"   ,    "bulk!"          ,    "bulk_count:i" ,    "slim!"         
	    #search methods
	    ,    "use_hmmscan!"       ,    "use_hmmsearch!"   ,    "use_blast!"      ,    "use_last!"     ,    "use_rapsearch!"
	    #general options
	    ,    "seq-split-size=i"  ,    "prerare-samps:i" ,    "postrare-samps:i" 
	    #translation options
	    ,    "trans-method:s"    ,    "split-orfs!"     ,    "min-orf-len:i"    
	    #search result parsing thresholds (less stringent, optional, defaults to family classification thresholds)
	    ,    "parse-evalue:f"    ,    "parse-coverage:f",    "parse-score:f"   ,  "small-transfer!",  
	    #family classification thresholds (more stringent)
	    ,    "class-evalue:f"    ,    "class-coverage:f",    "class-score:f"   ,    "top-hit!"     ,    "hit-type:s"       
	);
}


my $analysis = MRC->new();  #Initialize the project
$analysis->set_scripts_dir($localScriptDir);
$analysis->set_remote_exe_path($remoteExePath);
$analysis->set_dbi_connection("DBI:mysql:$dbname:$db_hostname", $dbname, $db_hostname); 
$analysis->set_username($db_username); 
if( defined( $db_pass ) ){
    $analysis->set_password($db_pass); 
}
elsif( defined( $conf_file ) ){
    my $pass = $analysis->get_password_from_file( $conf_file );
    $analysis->set_password( $pass );
}

$analysis->set_schema_name($schema_name);
$analysis->build_schema();
$analysis->set_ffdb($local_ffdb); 
$analysis->MRC::Run::get_partitioned_samples($project_dir);
$analysis->MRC::Run::back_load_project($input_pid);
$analysis->MRC::Run::back_load_samples();

my %samples = %{$analysis->get_sample_hashref()}; # de-reference the hash reference

foreach my $samp( keys( %samples ) ){
    my $sample_id = $samples{$samp}->{"id"};
    my $file;
    if( -e $project_dir . $samp . ".fa" ){
	$file = $project_dir . $samp . ".fa";
    } elsif (  -e $project_dir . $samp . ".fna" ){
	$file = $project_dir . $samp . ".fna";
    } else {
	"Can't find file for ${sample_id}. Trying " . $project_dir . $samp . ".fa" . "\n";
    }
    $samples{$samp}->{"path"} = $file;
    print $sample_id . "\n";
    print $samples{$samp}->{"path"} . "\n";
    my $tmp    = "/tmp/" . $samp . ".sql";	    
    my $table  = "metareads";
    my $nrows  = 10000;
    my @fields = ( "sample_id", "read_alt_id", "seq" );
    my $fks    = { "sample_id" => $sample_id }; #foreign keys and fields not in file 
    $analysis->MRC::DB::bulk_import( $table, $samples{$samp}->{"path"}, $tmp, $nrows, $fks, \@fields );
}
