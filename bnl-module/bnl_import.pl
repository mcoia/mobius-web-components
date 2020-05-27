#!/usr/bin/perl
# /production/sites/default/settings.php

use lib qw(../); 
use Loghandler;
use Data::Dumper;
use File::Path qw(make_path remove_tree);
use File::Copy;
use DBhandler;
use Encode;
use Text::CSV;
use DateTime;
use DateTime::Format::Duration;
use DateTime::Span;
use JSON;
use Selenium::Remote::Driver;
use Selenium::Firefox;
use Selenium::Remote::WebElement;
use pQuery;
use Getopt::Long;
use Cwd;

use sierraCluster;
use innreachServer;

our $stagingTablePrefix = "mobius_bnl";
our $pidfile = "/tmp/bnl_import.pl.pid";


our $driver;
our $dbHandler;
our $databaseName = '';
our $log;
our $drupalconfig;
our $debug = 0;
our $recreateDB = 0;
our $dbSeed,
our $blindDate = 0;
our $monthsBack = 1;


GetOptions (
"log=s" => \$log,
"drupal-config=s" => \$drupalconfig,
"debug" => \$debug,
"recreateDB" => \$recreateDB,
"dbSeed=s" => \$dbSeed,
"blindDate" => \$blindDate,
"monthsBack=s" => \$monthsBack
)
or die("Error in command line arguments\nYou can specify
--log path_to_log_output.log                  [Path to the log output file - required]
--drupal-config                               [Path to the drupal config file]
--debug                                       [Cause more log output]
--recreateDB                                  [Deletes the tables and recreates them]
--dbSeed                                      [DB Seed file - populating the base data]
--blindDate                                   [Should the software re-generate previously generated datasets]
--monthsBack                                  [How far back should we gather data Integer in months. Default is 1]
\n");


if(!$log)
{
    print "Please specify a logfile \n";
    exit;
}

if(!$drupalconfig)
{
    print "Please specify a drupal config logfile \n";
    exit;
}

$log = new Loghandler($log);

figurePIDFileStuff();

$drupalconfig = new Loghandler($drupalconfig);

$log->truncFile("");
$log->addLogLine("****************** Starting ******************");

setupDB();

createDatabase();

initializeBrowser();

my $writePid = new Loghandler($pidfile);
$writePid->truncFile("running");

my $cwd = getcwd();
$cwd .= "/screenshots";

my @all = @{getClusters()};
if(@all[1])
{
    my @order = @{@all[1]};
    my %clusters = %{@all[0]};
    mkdir $cwd unless -d $cwd;

    print "Months Back $monthsBack\n";
    foreach(@order)
    {
        print "Processing: $_\n";
        my $cluster;
        if($clusters{$_} =~ m/sierra/)  ## Right now, there are two typs: sierra and innreach
        {
            $cluster = new sierraCluster($_,$dbHandler,$stagingTablePrefix,$driver,$cwd,$monthsBack,$blindDate,$log,$debug);
        }
        else
        {
            $cluster = new innreachServer($_,$dbHandler,$stagingTablePrefix,$driver,$cwd,$monthsBack,$blindDate,$log,$debug);
        }
        $cluster->scrape();
    }
}   

undef $writePid;
closeBrowser();
$log->addLogLine("****************** Ending ******************");

sub getClusters
{
    my @ret = ();
    my %clusters = ();
    my @order = ();
    my $query = "
    SELECT
    name,type
    FROM
    $stagingTablePrefix"."_cluster
    where
    scrape_data is true
    -- and name = 'Archway'
    order by 2 desc,1
    -- limit 10 offset 3
    ";
    # where type='innreach' and name='prospector'
    # and
    # (
    # (
    # type='innreach'
    # and name='Prospector'
    # )
    # or
    # (
    # type='sierra'
    # and name='Archway'
    # )
    # )
    # -- and type='sierra' and name='merlin'
    $log->addLogLine($query);
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $clusters{@row[0]} = @row[1];
        push @order, @row[0];
    }
    @ret = (\%clusters,\@order);
    return \@ret;
}

sub escapeData
{
    my $d = shift;
    $d =~ s/'/\\'/g;
    return $d;
}

sub unEscapeData
{
    my $d = shift;
    $d =~ s/\\'/'/g;
    return $d;
}

sub initializeBrowser
{
    $Selenium::Remote::Driver::FORCE_WD3=1;

    # my $driver = Selenium::Firefox->new();
    $driver = Selenium::Remote::Driver->new
        (
            binary => '/usr/bin/geckodriver',
            browser_name  => 'firefox',
        );
    $driver->set_window_size(1200,3500); # Need it wide to capture more of the header on those large HTML tables
}

sub closeBrowser
{
    $driver->quit;

    # $driver->shutdown_binary;
}

sub setupDB
{
    my @lines = @{$drupalconfig->readFile()};
    my @lookingfor = ("'database'","'username'","'password'","'host'","'port'");
    my %answers = ();

    foreach(@lines)
    {
        my $line = trim($_);
        foreach(@lookingfor)
        {
            if( ($line =~ m/$_/) && ($line =~ m/^'/) )
            {
                my $v = $_;
                $v =~ s/'//g;
                my $parse = $line;
                $parse =~ s/$_//;
                #print "Parse = $parse\n";
                my @sp = split(/['"]/,$parse);
                $answers{$v} = @sp[1];
                #print "$v = ".$answers{$v}."\nline was:\n$line\n";
            }
         }  
    }
    undef $answers{'port'} if length($answers{'port'}) == 0;
    $databaseName = $answers{'database'};
    $dbHandler = new DBhandler($answers{'database'},$answers{'host'},$answers{'username'},$answers{'password'},$answers{'port'}||"3306","mysql");
}

sub createDatabase
{

    if($recreateDB)
    {
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_agency_owning_cluster ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_branch_name_dedupe ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW $stagingTablePrefix"."_same_branch_normal_name_expanded ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_same_branch_normal_name ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_branch_connection_map ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_branch_system ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_branch_cluster ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_branch_final_cluster_map ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_branch_cluster_owner_filter ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP VIEW IF EXISTS $stagingTablePrefix"."_bnl_final_branch_map ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP FUNCTION IF EXISTS $stagingTablePrefix"."_normalize_library_name ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_shortname_override ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_ignore_name ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_branch_shortname_agency_translate ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_normalize_branch_name ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_manual_branch_to_cluster ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_bnl_stage ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_bnl";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_branch ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_branch_name_final ";
        $log->addLine($query);
        $dbHandler->update($query);
        my $query = "DROP TABLE $stagingTablePrefix"."_cluster ";
        $log->addLine($query);
        $dbHandler->update($query);
    }

    my @exists = @{$dbHandler->query("SELECT table_name FROM information_schema.tables WHERE table_schema RLIKE '$databaseName' AND table_name RLIKE '$stagingTablePrefix'")};
    if(!$exists[0])
    {
    
        ##################
        # FUNCTIONS
        ##################
        my $query = "
         CREATE FUNCTION $stagingTablePrefix"."_normalize_library_name (raw_name TEXT) RETURNS VARCHAR(100)
            BEGIN
                RETURN replace(replace(lower(raw_name),'library',''),'  ',' ');
            END;
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);


        ##################
        # TABLES
        ##################
        $query = "CREATE TABLE $stagingTablePrefix"."_cluster (
        id int not null auto_increment,
        name varchar(100),
        type varchar(100),
        scrape_data boolean DEFAULT 1,
        report_base_url varchar(1000),
        report_username varchar(100),
        report_pass varchar(100),
        postgres_url varchar(100),
        postgres_db varchar(100),
        postgres_port varchar(100),
        postgres_username varchar(100),
        postgres_password varchar(100),
        PRIMARY KEY (id),
        INDEX (name)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_branch_name_final (
        id int not null auto_increment,
        name varchar(100),
        PRIMARY KEY (id),
        UNIQUE INDEX (name)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_branch (
        id int not null auto_increment,
        cluster int,
        institution varchar(100),
        shortname varchar(100),
        institution_normal varchar(100),
        final_branch int,
        PRIMARY KEY (id),
        UNIQUE INDEX (cluster, shortname),
        INDEX (institution_normal),
        INDEX (shortname),
        FOREIGN KEY (final_branch) REFERENCES $stagingTablePrefix"."_branch_name_final(id) ON DELETE CASCADE,
        FOREIGN KEY (cluster) REFERENCES $stagingTablePrefix"."_cluster(id) ON DELETE CASCADE
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        $query = "CREATE TABLE $stagingTablePrefix"."_bnl (
        id int not null auto_increment,
        owning_cluster int,
        owning_branch int,
        borrowing_cluster int,
        borrowing_branch int,
        quantity int,
        borrow_date date,
        match_key varchar(50),
        insert_time datetime DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        INDEX (borrow_date),
        UNIQUE INDEX (owning_cluster, owning_branch, borrowing_cluster, borrowing_branch, borrow_date),
        FOREIGN KEY (owning_cluster) REFERENCES $stagingTablePrefix"."_cluster(id) ON DELETE CASCADE,
        FOREIGN KEY (borrowing_cluster) REFERENCES $stagingTablePrefix"."_cluster(id) ON DELETE CASCADE,
        FOREIGN KEY (owning_branch) REFERENCES $stagingTablePrefix"."_branch(id) ON DELETE CASCADE,
        FOREIGN KEY (borrowing_branch) REFERENCES $stagingTablePrefix"."_branch(id) ON DELETE CASCADE
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        $query = "CREATE TABLE $stagingTablePrefix"."_bnl_stage (
        id int not null auto_increment,
        working_hash varchar(50),
        owning_lib varchar(100),
        borrowing_lib varchar(100),
        quantity int,
        borrow_date date,
        match_key varchar(50),
        insert_time datetime DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        INDEX (match_key),
        INDEX (owning_lib),
        INDEX (owning_lib),
        INDEX (working_hash)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_manual_branch_to_cluster (
        id int not null auto_increment,
        name varchar(100),
        cluster varchar(100),
        PRIMARY KEY (id),
        INDEX (name),
        INDEX (cluster)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_normalize_branch_name (
        id int not null auto_increment,
        variation varchar(100),
        normalized varchar(100),
        PRIMARY KEY (id),
        UNIQUE INDEX (variation),
        INDEX (normalized)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        $query = "CREATE TABLE $stagingTablePrefix"."_branch_shortname_agency_translate (
        id int not null auto_increment,
        shortname varchar(100),
        institution varchar(100),
        PRIMARY KEY (id),
        UNIQUE INDEX (shortname),
        INDEX (institution)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "CREATE TABLE $stagingTablePrefix"."_ignore_name (
        id int not null auto_increment,
        name varchar(100),
        PRIMARY KEY (id)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        $query = "CREATE TABLE $stagingTablePrefix"."_shortname_override (
        id int not null auto_increment,
        shortname varchar(100),
        institution varchar(100),
        PRIMARY KEY (id)
        )
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        ##################
        # VIEWS
        ##################

        ## This view is used to make queries cleaner. 
        ## Results in bnl final branch ID instead of branch ID for each bnl quantity
        $query = "
        CREATE OR REPLACE VIEW $stagingTablePrefix"."_bnl_final_branch_map
        AS
        SELECT
        owning_cluster.type \"cluster_type\",
        owning_branch_final.id \"owning_id\",
        borrowing_branch_final.id \"borrowing_id\",
        bnl.borrow_date \"borrow_date\",
        bnl.quantity \"quantity\"
        from
        $stagingTablePrefix"."_bnl bnl,
        $stagingTablePrefix"."_cluster owning_cluster,
        $stagingTablePrefix"."_cluster borrowing_cluster,
        $stagingTablePrefix"."_branch owning_branch,
        $stagingTablePrefix"."_branch borrowing_branch,
        $stagingTablePrefix"."_branch_name_final owning_branch_final,
        $stagingTablePrefix"."_branch_name_final borrowing_branch_final
        WHERE
        bnl.owning_branch = owning_branch.id AND
        bnl.owning_cluster = owning_cluster.id AND
        bnl.borrowing_branch = borrowing_branch.id AND
        bnl.borrowing_cluster = borrowing_cluster.id AND
        owning_branch.final_branch = owning_branch_final.id AND
        borrowing_branch.final_branch = borrowing_branch_final.id
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        ## Building block for compound view _branch_final_cluster_map
        $query = "
        CREATE OR REPLACE VIEW $stagingTablePrefix"."_branch_cluster_owner_filter
        AS
        SELECT
        branch.id,branch.cluster
        FROM
        $stagingTablePrefix"."_branch branch
        WHERE
        lower(trim(branch.shortname)) not in(select lower(trim(shortname)) from $stagingTablePrefix"."_branch_shortname_agency_translate)
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        ## Building block for compound view _branch_cluster
        $query = "
        CREATE OR REPLACE VIEW $stagingTablePrefix"."_branch_final_cluster_map
        AS
        SELECT
        final_branch.id as \"id\", group_concat(distinct cluster.type) as \"types\"
        from
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_branch_cluster_owner_filter owner_filter
        where
        owner_filter.id = branch.id AND
        branch.final_branch = final_branch.id AND
        branch.cluster = cluster.id
        group by 1
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        ## Creates a map between each branch and the clsuter they belong to.
        ## This relies on the above views (above views are not used in this project)
        $query = "
        CREATE OR REPLACE VIEW $stagingTablePrefix"."_branch_cluster
        AS
        -- Find branches with that appear on innreach and sierra. Prefer sierra cluster ID for sierra entries
        select DISTINCT 
        final_branch.id \"fid\",cluster.name \"cname\",cluster.id \"cid\"
        FROM
        $stagingTablePrefix"."_branch_final_cluster_map cluster_map,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_branch_cluster_owner_filter cluster_filter
        WHERE
        branch.id=cluster_filter.id AND
        cluster_filter.cluster = cluster.id AND
        branch.final_branch = final_branch.id AND
        cluster_map.id=branch.final_branch AND
        cluster.id=branch.cluster AND
        lower(cluster.type) = 'sierra' AND
        lower(cluster_map.types) LIKE '%innreach%' AND
        lower(cluster_map.types) LIKE '%sierra%' AND
        lower(final_branch.name) NOT IN(select lower(name) from $stagingTablePrefix"."_manual_branch_to_cluster)
        
        UNION ALL
        
        -- Find branches with that appear on innreach and sierra. Prefer sierra cluster ID for innreach entries
        select DISTINCT 
        final_branch.id \"fid\",sierra_cluster.name \"cname\",sierra_cluster.id \"cid\"
        FROM
        $stagingTablePrefix"."_branch_final_cluster_map cluster_map,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_branch sierra_branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_cluster sierra_cluster,
        $stagingTablePrefix"."_branch_cluster_owner_filter cluster_filter
        WHERE
        sierra_branch.id=cluster_filter.id AND
        cluster_filter.cluster = sierra_cluster.id AND
        sierra_branch.final_branch = branch.final_branch AND
        sierra_branch.cluster = sierra_cluster.id AND
        branch.final_branch = final_branch.id AND
        cluster_map.id=branch.final_branch AND
        cluster.id=branch.cluster AND
        lower(sierra_cluster.type) = 'sierra' AND
        lower(cluster.type) = 'innreach' AND
        lower(cluster_map.types) LIKE '%innreach%' AND
        lower(cluster_map.types) LIKE '%sierra%' AND
        lower(final_branch.name) NOT IN(select lower(name) from $stagingTablePrefix"."_manual_branch_to_cluster)

        UNION ALL

        -- Find branches that appear on innreach only AND ARE manually assigned a cluster
        select DISTINCT 
        final_branch.id \"fid\",cluster_assigned.name \"cname\",cluster_assigned.id \"cid\"
        FROM
        $stagingTablePrefix"."_branch_final_cluster_map cluster_map,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_cluster cluster_assigned,
        $stagingTablePrefix"."_manual_branch_to_cluster manual_branch_cluster
        WHERE
        lower(manual_branch_cluster.name) = lower(final_branch.name) AND
        branch.final_branch = final_branch.id AND
        cluster_map.id=branch.final_branch AND
        lower(cluster_assigned.name)=lower(manual_branch_cluster.cluster) AND
        lower(cluster.type) = 'innreach' AND
        lower(cluster_map.types) LIKE '%innreach%' AND
        lower(cluster_map.types) NOT LIKE '%sierra%'

        UNION ALL

        -- Find branches that appear on sierra only AND are NOT manually assigned to a cluster
        select DISTINCT 
        final_branch.id \"fid\",cluster.name \"cname\",cluster.id \"cid\"
        FROM
        $stagingTablePrefix"."_branch_final_cluster_map cluster_map,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_branch_cluster_owner_filter cluster_filter
        WHERE
        branch.id=cluster_filter.id AND
        cluster_filter.cluster = cluster.id AND
        branch.final_branch = final_branch.id AND
        cluster_map.id=branch.final_branch AND
        cluster.id=branch.cluster AND
        lower(cluster.type) = 'sierra' AND
        lower(cluster_map.types) NOT LIKE '%innreach%' AND
        lower(final_branch.name) NOT IN(select lower(name) from $stagingTablePrefix"."_manual_branch_to_cluster)
        
        UNION ALL

        -- Find branches that appear on sierra only AND are manually assigned to a cluster
        select DISTINCT 
        final_branch.id \"fid\",cluster_assigned.name \"cname\",cluster_assigned.id \"cid\"
        FROM
        $stagingTablePrefix"."_branch_final_cluster_map cluster_map,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_cluster cluster_assigned,
        $stagingTablePrefix"."_manual_branch_to_cluster manual_branch_cluster
        WHERE
        lower(manual_branch_cluster.name) = lower(final_branch.name) AND
        branch.final_branch = final_branch.id AND
        cluster_map.id=branch.final_branch AND
        lower(cluster_assigned.name)=lower(manual_branch_cluster.cluster) AND
        lower(cluster.type) = 'sierra' AND
        lower(cluster_map.types) NOT LIKE '%innreach%'
        
        UNION ALL

        -- Find branches that appear on sierra and innreach AND are manually assigned to a cluster
        select DISTINCT 
        final_branch.id \"fid\",cluster_assigned.name \"cname\",cluster_assigned.id \"cid\"
        FROM
        $stagingTablePrefix"."_branch_final_cluster_map cluster_map,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_cluster cluster_assigned,
        $stagingTablePrefix"."_manual_branch_to_cluster manual_branch_cluster
        WHERE
        lower(manual_branch_cluster.name) = lower(final_branch.name) AND
        branch.final_branch = final_branch.id AND
        cluster_map.id=branch.final_branch AND
        lower(cluster_assigned.name)=lower(manual_branch_cluster.cluster) AND
        lower(cluster.type) = 'sierra' AND
        lower(cluster_map.types) LIKE '%innreach%'
        
        UNION ALL

        -- Find branches that appear on innreach only AND are NOT manually assigned to a cluster
        select DISTINCT 
        final_branch.id \"fid\",cluster.name \"cname\",cluster.id \"cid\"
        FROM
        $stagingTablePrefix"."_branch_final_cluster_map cluster_map,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_cluster cluster,
        $stagingTablePrefix"."_branch_cluster_owner_filter cluster_filter
        WHERE
        branch.id=cluster_filter.id AND
        cluster_filter.cluster = cluster.id AND
        branch.final_branch = final_branch.id AND
        cluster_map.id=branch.final_branch AND
        cluster.id=branch.cluster AND
        lower(cluster.type) = 'innreach' AND
        lower(cluster_map.types) NOT LIKE '%sierra%' AND
        lower(final_branch.name) NOT IN(select lower(name) from $stagingTablePrefix"."_manual_branch_to_cluster)
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        ## Creates a map between each branch and the system they belong to
        $query = "
        CREATE OR REPLACE VIEW $stagingTablePrefix"."_branch_system
        AS
        -- Every branch that has a cluster assigned IS considered a MOBIUS branch,
        -- and because we insert the MOBIUS system innreach entry in the cluster table first, we know
        -- we can bubble up the MOBIUS cluster by getting the min(id)
        select DISTINCT 
        final_branch.id \"fid\",min(cluster_innreach.id) \"cid\"
        FROM
        $stagingTablePrefix"."_branch_cluster branch_cluster,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_cluster cluster_innreach
        WHERE
        branch_cluster.fid = final_branch.id AND
        lower(cluster_innreach.type) = 'innreach'
        group by 1

        UNION ALL

        -- The rest of the branches are not MOBIUS - which, right now, is only Prospector
        -- So we will get the max(id)
        -- TODO - figure out a way to handle the case when there are more than 2 innreach systems in the data
        select DISTINCT 
        final_branch.id \"fid\",max(cluster_innreach.id) \"cid\"
        FROM
        $stagingTablePrefix"."_branch_name_final final_branch
        LEFT JOIN  $stagingTablePrefix"."_branch_cluster branch_cluster on (branch_cluster.fid = final_branch.id),
        $stagingTablePrefix"."_cluster cluster_innreach
        WHERE
        branch_cluster.fid IS NULL AND
        lower(cluster_innreach.type) = 'innreach'
        group by 1
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "
        CREATE OR REPLACE VIEW  $stagingTablePrefix"."_branch_connection_map
        AS
        select DISTINCT
        branch_final.id as \"fid\",
        branch_final.name as \"fname\",
        cluster.id \"cid\",
        cluster.name as \"cname\",
        cluster.type as \"ctype\"
        from 
        $stagingTablePrefix"."_branch_cluster branch_cluster,
        $stagingTablePrefix"."_branch_name_final branch_final,
        $stagingTablePrefix"."_cluster cluster
        WHERE
        branch_cluster.fid = branch_final.id AND
        branch_cluster.cid=cluster.id

        UNION ALL

        select DISTINCT
        branch_final.id as \"fid\",
        branch_final.name as \"fname\",
        cluster.id \"cid\",
        cluster.name as \"cname\",
        cluster.type as \"ctype\"
        from 
        $stagingTablePrefix"."_branch_system branch_system,
        $stagingTablePrefix"."_branch_name_final branch_final,
        $stagingTablePrefix"."_cluster cluster
        WHERE
        branch_system.fid = branch_final.id AND
        branch_system.cid=cluster.id
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "
        CREATE VIEW $stagingTablePrefix"."_same_branch_normal_name
        AS
        SELECT
        mbb_inside.institution_normal \"normal_name\"
        , count( * ) as \"count\"
        FROM
        $stagingTablePrefix"."_branch mbb_inside WHERE
        lower(mbb_inside.institution) like '%library%'
        group by 1
        having count( * ) > 1
         ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        $query = "
        CREATE VIEW $stagingTablePrefix"."_same_branch_normal_name_expanded
        AS
        SELECT mbb.id,mbb.institution_normal \"dname\",mbb.institution
        FROM
        $stagingTablePrefix"."_branch mbb,
        $stagingTablePrefix"."_same_branch_normal_name AS normals
        WHERE
        mbb.institution_normal = normals.normal_name
         ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "
        CREATE VIEW $stagingTablePrefix"."_branch_name_dedupe
        AS
        SELECT DISTINCT
        thebottom.institution \"variation\", thetop.institution \"normalized\"
        FROM
        $stagingTablePrefix"."_same_branch_normal_name_expanded AS thetop,
        $stagingTablePrefix"."_same_branch_normal_name_expanded AS thebottom
        WHERE
        thetop.dname=thebottom.dname AND
        thebottom.id!=thetop.id AND
        length(thetop.institution) > length(thebottom.institution)

        UNION ALL

        SELECT
        thetop.institution \"variation\", thebottom.institution \"normalized\"
        FROM
        $stagingTablePrefix"."_same_branch_normal_name_expanded AS thetop,
        $stagingTablePrefix"."_same_branch_normal_name_expanded AS thebottom
        WHERE
        thetop.dname=thebottom.dname AND
        thebottom.id!=thetop.id AND
        length(thetop.institution) < length(thebottom.institution)
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        $query = "
        CREATE VIEW $stagingTablePrefix"."_agency_owning_cluster
        AS
        SELECT DISTINCT 
        branch.shortname as \"shortname\",
        branch_cluster.cid as\"cid\",
        branch_cluster.cname as \"cname\"
        FROM
        $stagingTablePrefix"."_branch branch,
        $stagingTablePrefix"."_branch_shortname_agency_translate sixcodes,
        $stagingTablePrefix"."_branch_name_final final_branch,
        $stagingTablePrefix"."_branch_cluster branch_cluster
        WHERE
        branch.final_branch=final_branch.id and
        final_branch.id=branch_cluster.fid and
        sixcodes.shortname=branch.shortname
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        ##################
        # TRIGGERS
        ##################

         $query = "
         CREATE TRIGGER $stagingTablePrefix"."_bnl_match_key_update BEFORE UPDATE ON $stagingTablePrefix"."_bnl
            FOR EACH ROW
            BEGIN
                SET NEW.match_key = CONCAT(
                        NEW.owning_cluster,'-',
                        NEW.owning_branch,'-',
                        NEW.borrowing_cluster,'-',
                        NEW.borrowing_branch, '-',
                        NEW.borrow_date
                        );
            END;
        
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "
         CREATE TRIGGER $stagingTablePrefix"."_bnl_match_key_insert BEFORE INSERT ON $stagingTablePrefix"."_bnl
            FOR EACH ROW
            BEGIN
                SET NEW.match_key = CONCAT(
                        NEW.owning_cluster,'-',
                        NEW.owning_branch,'-',
                        NEW.borrowing_cluster,'-',
                        NEW.borrowing_branch, '-',
                        NEW.borrow_date
                        );
            END;
        
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        $query = "
         CREATE TRIGGER $stagingTablePrefix"."_branch_institution_normal_update BEFORE UPDATE ON $stagingTablePrefix"."_branch
            FOR EACH ROW
            BEGIN
                SET NEW.institution_normal = $stagingTablePrefix"."_normalize_library_name(NEW.institution);
            END;
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);

        $query = "
         CREATE TRIGGER $stagingTablePrefix"."_branch_institution_normal_insert BEFORE INSERT ON $stagingTablePrefix"."_branch
            FOR EACH ROW
            BEGIN
                SET NEW.institution_normal = $stagingTablePrefix"."_normalize_library_name(NEW.institution);
            END;
        ";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
        ##############
        # Decided not to completely remove the word library from the data. Just normalize it with the proceedures above
        # But in case we decide we want to - these triggers will cause the word "library" to be outlawed from the names everywhere
        ###############
        # $query = "
         # CREATE TRIGGER $stagingTablePrefix"."_bnl_stage_name_normalize_insert BEFORE INSERT ON $stagingTablePrefix"."_bnl_stage
            # FOR EACH ROW
            # BEGIN
                # SET NEW.borrowing_lib = TRIM(REGEXP_REPLACE(NEW.borrowing_lib,'(?i)library',''));
                # SET NEW.owning_lib = TRIM(REGEXP_REPLACE(NEW.borrowing_lib,'(?i)library',''));
            # END;
        # ";
        # $log->addLine($query) if $debug;
        # $dbHandler->update($query);

        # $query = "
         # CREATE TRIGGER $stagingTablePrefix"."_brance_name_normalize_insert BEFORE INSERT ON $stagingTablePrefix"."_branch
            # FOR EACH ROW
            # BEGIN
                # SET NEW.institution = REGEXP_REPLACE(TRIM(REGEXP_REPLACE(NEW.institution,'(?i)library','')),'[[:space:]]+',' ');
                # SET NEW.shortname = REGEXP_REPLACE(TRIM(REGEXP_REPLACE(NEW.shortname,'(?i)library','')),'[[:space:]]+',' ');
            # END;
        # ";
        # $log->addLine($query) if $debug;
        # $dbHandler->update($query);

        # $query = "
         # CREATE TRIGGER $stagingTablePrefix"."_brance_name_normalize_update BEFORE UPDATE ON $stagingTablePrefix"."_branch
            # FOR EACH ROW
            # BEGIN
                # SET NEW.institution = TRIM(REGEXP_REPLACE(NEW.institution,'(?i)library',''));
                # SET NEW.shortname = TRIM(REGEXP_REPLACE(NEW.shortname,'(?i)library',''));
            # END;
        # ";
        # $log->addLine($query) if $debug;
        # $dbHandler->update($query);

        seedDB($dbSeed) if $dbSeed;
    }
    else
    {
        print "Staging table already exists\n";
    }
}

sub seedDB
{
    my $seedFile = shift;
    my $readFile = new Loghandler($seedFile);
    $log->addLine("Reading seeDB File $seedFile");
    my @lines = @{$readFile->readFile()};

    my $currTable = '';
    my @cols = ();
    my $insertQuery = "";
    my @datavals = ();
    foreach(@lines)
    {
        my $line = $_;
        $line = trim($line);
        if($line =~ m/^\[/)
        {
            if( ($#cols > -1) && ($#datavals > -1) )
            {
                # execute the insert
                @flatVals = ();
                my $insertLog = $insertQuery;
                foreach(@datavals)
                {
                    my @row = @{$_};
                    $insertQuery .= "(";
                    $insertLog .= "(";
                    $insertQuery .= ' ? ,' foreach(@row);
                    $insertLog .= " '$_' ," foreach(@row);
                    $insertQuery = substr($insertQuery,0,-1);
                    $insertLog = substr($insertLog,0,-1);
                    $insertQuery .= "),\n";
                    $insertLog .= "),\n";
                    push @flatVals, @row;
                }
                $insertQuery = substr($insertQuery,0,-2);
                $insertLog = substr($insertLog,0,-2);
                $log->addLine($insertLog);
                $dbHandler->updateWithParameters($insertQuery,\@flatVals);
                undef @flatVals;
                @datavals = ();
            }
            $log->addLine("seedDB: Detected cluster delcaration") if $debug;
            $currTable = $line;
            $currTable =~ s/^\[([^\]]*)\]/$1/g;
            $log->addLine("Heading $currTable") if $debug;
            @cols = @{figureColumnsFromTable($currTable)};
            my @temp = ();
            $insertQuery = "INSERT INTO $stagingTablePrefix"."_$currTable (";
            foreach(@cols)
            {
                $insertQuery .= "$_," if($_ ne 'id');
                push @temp, $_ if($_ ne 'id');
            }
            @cols = @temp;
            undef @temp;
            $insertQuery = substr($insertQuery,0,-1);
            $insertQuery .= ")\nvalues\n";
            $log->addLine(Dumper(\@cols)) if $debug;
            $log->addLine(Dumper($#cols)) if $debug;
        }
        elsif($currTable)
        {
            $log->addLine($line);
            
            my @vals = split(/["'],["']/,$line);
            $log->addLine("Split and got\n".Dumper(\@vals)) if $debug;
            $log->addLine("Expecting $#cols and got $#vals") if $debug;
            if($#vals == $#cols) ## Expected number of columns
            {
                my @v = ();
                foreach (@vals)
                {
                    my $val = $_;
                    $val =~ s/^['"]+//;
                    $val =~ s/['"]+$//;
                    push @v, $val;
                }
                push @datavals, [@v];
            }
        }
    }
    if( ($#cols > -1) && ($#datavals > -1) )
    {
        # execute the insert
        @flatVals = ();
        my $insertLog = $insertQuery;
        foreach(@datavals)
        {
            my @row = @{$_};
            $insertQuery .= "(";
            $insertLog .= "(";
            $insertQuery .= ' ? ,' foreach(@row);
            $insertLog .= " '$_' ," foreach(@row);
            $insertQuery = substr($insertQuery,0,-1);
            $insertLog = substr($insertLog,0,-1);
            $insertQuery .= "),\n";
            $insertLog .= "),\n";
            push @flatVals, @row;
        }
        $insertQuery = substr($insertQuery,0,-2);
        $insertLog = substr($insertLog,0,-2);
        $log->addLine($insertLog);
        $dbHandler->updateWithParameters($insertQuery,\@flatVals);
        undef @flatVals;
    }
}

sub figureColumnsFromTable
{
    my $table = shift;
    my @ret = ();
    my $query = "
        SELECT COLUMN_NAME 
        FROM 
        INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA='$databaseName'
        AND TABLE_NAME='$stagingTablePrefix".'_'."$table'";
    $log->addLine($query) if $debug;
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        push @ret, @row[0];
    }
    return \@ret;
}

sub trim
{
    my $st = shift;
    $st =~ s/^[\s\t]*(.*)/$1/;
    $st =~ s/(.*)[\s\t]*$/$1/;
    return $st;
}

sub dirtrav
{
	my @files = @{@_[0]};
	my $pwd = @_[1];
	opendir(DIR,"$pwd") or die "Cannot open $pwd\n";
	my @thisdir = readdir(DIR);
	closedir(DIR);
	foreach my $file (@thisdir) 
	{
		if(($file ne ".") and ($file ne ".."))
		{
			if (-d "$pwd/$file")
			{
				push(@files, "$pwd/$file");
				@files = @{dirtrav(\@files,"$pwd/$file")};
			}
			elsif (-f "$pwd/$file")
			{			
				push(@files, "$pwd/$file");			
			}
		}
	}
	return \@files;
}

sub figurePIDFileStuff
{
    if (-e $pidfile)
    {
        #Check the processes and see if there is a copy running:
        my $thisScriptName = $0;
        my $numberOfNonMeProcesses = scalar grep /$thisScriptName/, (split /\n/, `ps -aef`);
        print "$thisScriptName has $numberOfNonMeProcesses running\n" if $debug;
        # The number of processes running in the grep statement will include this process,
        # if there is another one the count will be greater than 1
        if($numberOfNonMeProcesses > 1)
        {
            print "Sorry, it looks like I am already running.\nIf you know that I am not, please delete $pidfile\n";
            exit;
        }
        else
        {
            #I'm really not running
            unlink $pidFile;
        }
    }
}

sub DESTROY
{
    print "I'm dying, deleting PID file $pidFile\n";
    unlink $pidFile;
}

exit;
