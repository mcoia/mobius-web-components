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

# These varialbes might change as time goes on. We are relying on the "KNACK" form IOWA.
# https://silo.knack.com/directory

our $knackDirectoryUrl = "https://us-api.knack.com/v1/scenes/scene_120/views/view_231/records/export/applications/5adf7c79596212286f183285?type=json&format=both&page=1&rows_per_page=25&sort_field=field_248&sort_order=asc";
our $knackContactPage = "https://silo.knack.com/directory#directory/library-details2/PUTKEYHERE/";
our @knackFieldForLibraryName = ("field_248","field_248_raw");
our $stagingTable = "iowa_courier_staging";
our $drupalStructureName = "iowa_libraries";
our $pidfile = "/tmp/ia_shares_import.pl.pid";


our $driver;
our %externalKnackData = ();
our %externalKnackDataLibNames = ();
our $dirRoot;
our $dbHandler;
our $databaseName = '';
our $log;
our $drupalconfig;
our $fullRun = 0;
our $singleKnack;
our $debug = 0;

# This is mostly useless because we are no long importing from CSV
# But remains just in case we ever need to import a CSV again
our %csvColMap = (
    0 => 'silo_code',
    1 => 'num',
    2 => 'library_name',
    3 => 'physical_address',
    4 => 'city',
    5 => 'zip',
    6 => 'state',
    7 => 'contact_card',
    8 => 'hub_city',
    9 => 'hub',
    10 => 'route',
    11 => 'day',
    12 => 'hours',
    13 => 'stat_courier_pick_up_schedule',
    14 => 'delivery_code',
    15 => 'number_of_bags'
    );

# We might want to change the friendly column names away from what Knack says. This is where you do it
# But you need to know the "friendly database" converted column name from the knack which are overriden by %knackColMap 
our %friendlyColOverride = (
    'silo_code' => 'SILO Code',
    'hub' => 'Hub Number',
    'hub_city' => 'Hub City',
    'day' => 'Delivery Day',
    'route' => 'Route Number',
    'stat_courier_pick_up_schedule' => 'Pickup Time',
    'delivery_code' => 'Delivery Code',
    'number_of_bags' => 'Number of bags',
    'physical_address' => 'Delivery Address'
);


# This is a hack to prefer our column naming structure for some* columns
our %knackColMap = (
    'library_name' => 'library_name',
    'city' => 'city',
    'delivery_address_mobius' => 'physical_address',
    'locator_code' => 'silo_code',
    'route_number_mobius' => 'route',
    'hub_city_mobius' => 'hub_city',
    'zip' => 'zip',
    'number_of_bags_mobius' => 'number_of_bags',
    'state' => 'state',
    'delivery_code_mobius' => 'delivery_code',
    'delivery_day_mobius' => 'day',
    'state_courier_pickup_schedule_mobius' => 'stat_courier_pick_up_schedule',
    'hub_number_mobius' => 'hub',
);

# This is only used if we are updating Drupal's controlled tables
# All of the code for this is commented out below
our %drupalFieldMap = (
    'silo_code' => 'field_data_field_silo_code',
    'hub_city' => 'field_data_field_hub_city',
    'hub' => 'field_data_field_hub_id',
    'route' => 'field_data_field_route',
    'day' => 'field_data_field_iowa_day',
    'delivery_code' => 'field_data_field_iowa_delivery_code',
    'day' => 'field_data_field_iowa_day',
    'stat_courier_pick_up_schedule' => 'field_revision_field_iowa_delivery_time'
    );
    

    
    
GetOptions (
"dir-root=s" => \$dirRoot,
"log=s" => \$log,
"drupal-config=s" => \$drupalconfig,
"full" => \$fullRun,
"single=s" => \$singleKnack,
"debug" => \$debug
)
or die("Error in command line arguments\nYou can specify
--dir-root pathToCSVFolder                    [Path to the CSV Folder - optional]
--log path_to_log_output.log                  [Path to the log output file - required]
--drupal-config path_to_drupal_config_file    [Path to the Drupal Config settings.php - AKA /[drupal_dir]/sites/default/settings.php]
--full                                        [cause the software to run through a full import from Knack]
--single                                      [Specify a knack GUID id to download and process]
--debug                                       [Cause more log output]
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

initializeBrowser();

my $writePid = new Loghandler($pidfile);
$writePid->truncFile("running");
undef $writePid;

if($dirRoot)
{
    my @files;
    @files = @{dirtrav(\@files, $dirRoot)};

    foreach(@files)
    {
        updateStagingFromCSV($_);
        updateProduction();
    }
}

if($singleKnack)
{
    my $ID = getIDFromKnack($singleKnack);
    my $answer = scrapeLibraryData($singleKnack);
    $log->addLine(Dumper($answer)) if $debug;
    updateColumnsWithKnackData($answer,$ID) if($answer);
}
elsif($fullRun)
{
    downloadFreshFromKnack();
}

closeBrowser();
$log->addLogLine("****************** Ending ******************");
    
sub updateProduction
{
    
    # See if there are any changed rows
    my @order = ("id","knackid","nid");
    my $query = "SELECT id,knackid,nid,";
    while ( (my $key, my $value) = each(%csvColMap) )
    {
        $query .= $value.",";
        push @order, $value;
    }
    $query = substr($query,0,-1);
    $query.= " from $stagingTable where changed is true";
    
    $log->addLine($query) if $debug;
    

    my @diffs = @{$dbHandler->query($query)};
    $log->addLine(Dumper(\@diffs));
    $log->addLine("Found ".scalar @diffs." difference(s)");
    if($#diffs > -1)
    {
        my $libNameCol = 0;
        my $libAddressCol = 0;
        my $pos = 0;
        foreach(@order)
        {
            $libNameCol = $pos if($_ eq 'library_name');
            $libAddressCol = $pos if($_ eq 'physical_address');
            $pos++;
        }
        $log->addLine("Found lib name at column pos: $libNameCol") if $debug;
        $log->addLine("Found address at column pos: $libAddressCol") if $debug;
        getJSONFromKnack();
        foreach(@diffs)
        {
            my @thisLibRow = @{$_};
            my $thisLibName = @thisLibRow[$libNameCol];
            my $thisLibAddress = @thisLibRow[$libAddressCol];
            $log->addLine($thisLibName) if $debug;
            my $ID= @thisLibRow[0];
            my $knackID = @thisLibRow[1];
            my $nID = @thisLibRow[2];
            $knackID = populateKNACKID($ID,$knackID,$thisLibName,$thisLibAddress);
            if($knackID)  ## Need the Knack ID for further processing
            {
                my $answer = scrapeLibraryData($knackID);
                $log->addLine(Dumper($answer)) if $debug;
                updateColumnsWithKnackData($answer,$ID) if($answer);
            }
        }
    }
}

sub downloadFreshFromKnack
{
    getJSONFromKnack();
    while ( (my $key, my $value) = each(%externalKnackData) )
    {
        ## See if we already have a row for this knackID
        my $query = "select id from $stagingTable where knackid = '$key'";
        my @results = @{$dbHandler->query($query)};
        $log->addLine($query);
        
        if($#results < 0)
        {
            my $uquery = "INSERT INTO $stagingTable (knackid) values( ? )";
            my @vars = ($key);
            $log->addLine("New entry previously unknown");
            $log->addLine($uquery);
            $log->addLine($key);
            $dbHandler->updateWithParameters($uquery,\@vars);
            @results = @{$dbHandler->query($query)};
        }
        if (@results[0])
        {
            my @row = @{@results[0]};
            my $answer = scrapeLibraryData($key);
            updateColumnsWithKnackData($answer, @row[0]) if($answer);
        }
    }
}

sub getIDFromKnack
{
    my $knackID = shift;
    my $query = "select id from $stagingTable where knackid = '$knackID'";
    my @res = @{$dbHandler->query($query)};
    foreach(@res)
    {
        my @row = @{$_};
        return @row[0];
    }
    return 0;
}

sub updateColumnsWithKnackData
{
    my $answer = shift;
    my $ID = shift;
    alignColumns($answer);
    my %libVals = %{$answer};
    $log->addLine("updateColumnsWithKnackData");
    $log->addLine(Dumper(\%libVals)) if $debug;
    my $query = "UPDATE $stagingTable set\n";
    my @vars = ();
    while ( (my $key, my $value) = each(%libVals) )
    {
        my $dbColName = convertStringToFriendlyColumnName($key);
        $dbColName = $knackColMap{$dbColName} if ($knackColMap{$dbColName});
        $query .= "$dbColName = ?,\n";
        push @vars, $value;
    }
    $query .= "changed = ? ";
    push @vars, "0";
    $query .= "\n where id = ?";
    push @vars, $ID;
    $log->addLine($query) if $debug;
    $log->addLine(Dumper(\@vars)) if $debug;
    $dbHandler->updateWithParameters($query,\@vars);
}

sub alignColumns
{
    my %data = %{@_[0]};
    my %colAssignments = ();
    while ( (my $key, my $value) = each(%data) )
    {
        my $friendlyColumnName = convertStringToFriendlyColumnName($key);
        $log->addLine("$key => $friendlyColumnName") if $debug;
        if(!$knackColMap{$friendlyColumnName})
        {
            my $query = "
            SELECT * 
                FROM information_schema.COLUMNS 
                WHERE 
                TABLE_SCHEMA = '$databaseName' 
                AND TABLE_NAME = '$stagingTable' 
                AND COLUMN_NAME = '$friendlyColumnName'
                ";
            my @res = @{$dbHandler->query($query)};
            if($#res == -1)
            {
                my $query = "ALTER TABLE  $stagingTable ADD COLUMN $friendlyColumnName varchar(300)";
                $log->addLine($query);
                $dbHandler->update($query);
            }
            $colAssignments{$friendlyColumnName} = $key;
        }
        else
        {
            $colAssignments{$knackColMap{$friendlyColumnName}} = $key;
        }
    }
    checkColumnLabelRow(\%colAssignments);
}

sub checkColumnLabelRow
{
    my %columnLabels = %{@_[0]};
    my $query = "select id from $stagingTable where id = -1";
    my @res = @{$dbHandler->query($query)};
    my @vars;
    if($#res > -1)
    {
        $query = "update $stagingTable set ";
        while ( (my $key, my $value) = each(%columnLabels) )
        {
            $query .= "$key = ? ,\n";
            push @vars, unEscapeData(getFriendlyColumnOverrides($key,$value));
        }
        $query = substr($query,0,-2);
        $query .= "\n where id = ?";
        push @vars, -1;
    }
    else
    {
        $query = "insert into $stagingTable (";
        my $valuesClause = "";
        while ( (my $key, my $value) = each(%columnLabels) )
        {
            $query .= "$key,";
            push @vars, unEscapeData(getFriendlyColumnOverrides($key,$value));
            $valuesClause .= "?,";
        }
        $query .="id)\n values($valuesClause ? )";
        push @vars, -1;
    }
    $log->addLine($query) if $debug;
    $log->addLine(Dumper(\@vars)) if $debug;
    $dbHandler->updateWithParameters($query, \@vars);
    $dbHandler->update("update $stagingTable set changed=0 where id = -1");
}

sub getFriendlyColumnOverrides
{
    my ($dbCol, $friendlyName) = @_;
    # $log->addLine("Checking $dbCol");
    # $log->addLine("Found it to be: ".$friendlyColOverride{$dbCol}) if $friendlyColOverride{$dbCol};
    my $ret = $friendlyColOverride{$dbCol} || $friendlyName || $dbCol;
    return $ret;
}

sub populateKNACKID
{
    my $ID = shift;
    my $knackID = shift;
    my $thisLibName = shift;
    my $thisLibAddress = shift;
    $log->addLine("populateKNACKID");
    $log->addLine("knack =  $knackID") if ($knackID && $debug);
    
    return $knackID if ($knackID && $knackID ne 'undef');
    my @foundKnackIDs = ();
    my $final;
    
    while ( (my $key, my $value) = each(%externalKnackData) )
    {
        while ( (my $mkey, my $mvalue) = each(%{$externalKnackData{$key}}) )
        {
            if ( (ref $mvalue ne 'HASH') && (ref $mvalue ne 'ARRAY') && (unEscapeData($mvalue) eq $thisLibName) )
            {
                $log->addLine("FOUND!");
                my $alreadyThere = 0;
                $alreadyThere = ( ($_ eq $key) && !$alreadyThere) ? 1 : 0 foreach(@foundKnackIDs);
                push @foundKnackIDs, $key if !$alreadyThere;
                undef $alreadyThere;
            }
        }
    }
    if($#foundKnackIDs > 0)
    {
        
        $log->addLine("Found more than one matched library by name $thisLibName - Investigate this");
        foreach(@foundKnackIDs)
        {
            my $thisKnack = $_;
            while ( (my $key, my $value) = each(%{$externalKnackData{$thisKnack}}) )
            {
               $final = $thisKnack if unEscapeData($value) eq $thisLibAddress;
            }
        }
    }
    if($#foundKnackIDs == 0)
    {
        $final = @foundKnackIDs[0];
        $log->addLine("$thisLibName found Single match: ".@foundKnackIDs[0]) if ($debug);
    }
    
    if($final)
    {
        my $query = "UPDATE $stagingTable set knackid = ? where id = ?";
        my @vars = ($final,$ID);
        $log->addLine($query);
        $log->addLine(Dumper(\@vars));
        $dbHandler->updateWithParameters($query,\@vars);
        return $final;
    }
    return 0;
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
            # 'platform'     => 'MAC',
            # 'extra_capabilities' => {
                # # firefox_binary => '/usr/bin/geckodriver'
                # firefox_binary => '/usr/bin/firefox',
                # firefox_profile  => $profile
            # }
        );
    $driver->set_window_size(1200,1500);
}

sub closeBrowser
{
    $driver->quit;

    # $driver->shutdown_binary;
}

sub scrapeLibraryData
{
    my $lid = shift;

    my $url = $knackContactPage;
    
    $url =~ s/PUTKEYHERE/$lid/g;
    
    $log->addLine("Getting $url");
    $driver->get($url);

    # $driver->capture_screenshot("/mnt/evergreen/test.png", {'full' => 1});

    my $pageLoaded = 0;
    my $giveup = 100;
    my $tries = 0;
    while(!$pageLoaded)
    {
       $pageLoaded = $driver->find_element_by_class("kn-detail");
       sleep 1;
       # $log->addLine("javascript: " . $driver->has_javascript);
       # if($tries == 20)
       # {
            # $driver->capture_screenshot("/home/ma/iowa_courier_data_import/test.png", {'full' => 1});
       # }
       return 0 if ($tries > $giveup);
       $tries++;
    }
    my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
    # $log->addLine("Body of the HTML: " . Dumper($body));
    my %libraryVals = ();
    
    pQuery(".kn-detail",$body)->each(sub {
        my $i = shift;
        my $key;
        my $value;
        pQuery(".kn-detail-label > span", $_)->each(sub {
            $key = pQuery($_)->text();
        })->end();
        pQuery(".kn-detail-body > span", $_)->each(sub {
            $value = pQuery($_)->text();
        })->end();
        if($key && $value)
        {
            $libraryVals{$key} = $value;
        }
        undef $key;
        undef $value;
        # print $i, " => ", pQuery($_)->html(), "\n";
    });
    
    $log->addLine(Dumper(\%libraryVals)) if $debug;

    
    return \%libraryVals;
}

sub updateStagingFromCSV
{
    my $file = shift;
    my $path;
    my @sp = split('/',$file);
   
    $path=substr($file,0,( (length(@sp[$#sp]))*-1) );
            
    checkFileReady($file);
    my $csv = Text::CSV->new ( )
        or die "Cannot use CSV: ".Text::CSV->error_diag ();
    open my $fh, "<:encoding(utf8)", $file or die "$file: $!";
    my $rownum = 0;
    my $success = 0;
    my $queryByHand = '';
    

    my $queryInserts = "INSERT INTO $stagingTable(";
    $queryByHand = "INSERT INTO $stagingTable(";
    my @order = ();
    my $sanitycheckcolumnnums = 0;
    my @queryValues = ();
    while ( (my $key, my $value) = each(%csvColMap) )
    {
        $queryInserts .= $value.",";
        $queryByHand .= $value.",";
        push @order, $key;
        $sanitycheckcolumnnums++;
    }
    $queryInserts = substr($queryInserts,0,-1);
    $queryByHand = substr($queryByHand,0,-1);
    $queryInserts .= ")\nVALUES \n";
    $queryByHand .= ")\nVALUES \n";

    while ( my $row = $csv->getline( $fh ) )
    {
        # $log->addLine(Dumper($row));
        my @rowarray = @{$row};
        my $skip = 0;
        if( ($rownum == 0) && ( lc(@rowarray[0]) =~ /silo/))
        {
            $log->addLine("We are reading a header row");
            $skip = 1;
            createStagingTable($row);
        }
        if(scalar @rowarray != $sanitycheckcolumnnums )
        {
            $log->addLine("Error parsing line $rownum\nIncorrect number of columns: ". scalar @rowarray);
        }
        elsif (!$skip)
        {
            my $siloCode;
            my $thisLineInsert = '';
            my $thisLineInsertByHand = '';
            my @thisLineVals = ();
            
            foreach(@order)
            {
                my $colpos = $_;
                # print "reading $colpos\n";
                $thisLineInsert .= '?,';
                @rowarray[$colpos] = trim(@rowarray[$colpos]);

                $thisLineInsertByHand.="'".@rowarray[$colpos]."',";
                push (@thisLineVals, @rowarray[$colpos]);
                # $log->addLine(Dumper(\@thisLineVals));
                # gather up the special vars
                $siloCode = @rowarray[$colpos] if($csvColMap{$colpos} eq 'silo_code');
            }
            my $existingRow = lookupExistingSiloInStaging($siloCode);
            if($existingRow != -1)
            {
                # $log->addLine("This row already exists in the staging table - converting to update instead of insert");
                my @differentCols = @{findDifferences(\@rowarray,\@order,\%csvColMap,$existingRow)};
                if($#differentCols > -1)
                {
                    $log->addLine( "There are ". scalar @differentCols ." differences");
                    my $updateStatement = "UPDATE $stagingTable set \nchanged=1,\n";
                    my @upvars = ();
                    foreach(@differentCols)
                    {
                       $updateStatement .= $csvColMap{$_}." = ? ,\n";
                       push @upvars, @rowarray[$_];
                    }
                    $updateStatement = substr($updateStatement,0,-2);
                    $updateStatement .= "\nwhere id = ?";
                    push @upvars, $existingRow;
                    $log->addLine($updateStatement);
                    $log->addLine(Dumper(\@upvars));
                    $dbHandler->updateWithParameters($updateStatement,\@upvars);
                    undef $updateStatement;
                    undef @upvars;
                }
            }
            else
            {
                $thisLineInsert = substr($thisLineInsert,0,-1);
                $queryInserts .= '(' . $thisLineInsert . "),\n";
                $queryByHand .= '(' . $thisLineInsertByHand . "),\n";
                foreach(@thisLineVals)
                {
                    # print "pushing $_\n";
                    push (@queryValues, $_);
                }
                $success++;
            }
            undef @thisLineVals;
        }
        $rownum++;
    }
    $queryInserts = substr($queryInserts,0,-2) if $success;
    $queryByHand = substr($queryByHand,0,-2) if $success;
    
    # Handle the case when there is only one row inserted
    if($success == 1)
    {
        $queryInserts =~ s/VALUES \(/VALUES /;            
        $queryInserts = substr($queryInserts,0,-1);
    }

    if($success) # at least one row to insert
    {
        $log->addLine($queryInserts);
        $log->addLine($queryByHand);
        $log->addLine(Dumper(\@queryValues));
        $dbHandler->updateWithParameters($queryInserts,\@queryValues);
    }
    close $fh;
    $log->addLine("Importing $success / $rownum");
    
    # delete the file so we don't read it again
    # unlink $file;
}

sub getJSONFromKnack
{
    $log->addLine("Downloading JSON..");
    my $rawJSON = qx{curl --silent $knackDirectoryUrl};
    $json = JSON->new->allow_nonref;
    my %rawJSON = %{$json->decode( $rawJSON )};
    %externalKnackData = ();
    $log->addLine("Done. Parsing...");
    foreach(@{$rawJSON{"records"}})
    {
        my %thisLib = %{$_};
        my $thisLibID = $thisLib{"id"};
        $externalKnackData{$thisLibID} = \%thisLib;
        
        # The library name is not unique - abandoning this
        # foreach(@knackFieldForLibraryName)
        # {
            # if($thisLib{$_} && length($thisLib{$_}) > 1 )
            # {
                # if( ($externalKnackDataLibNames{$thisLib{$_}}) && ($externalKnackDataLibNames{$thisLib{$_}} ne $thisLibID) )
                # {
                    # print "Found duplicate library name: ". $thisLib{$_} ."\n";
                    # print "ID: $thisLib\n";
                    # print "ID: ".$externalKnackDataLibNames{$thisLib{$_}}."\n";
                    # $log->addLine(Dumper(\%externalKnackData));
                    # $log->addLine(Dumper(\%externalKnackDataLibNames));
                    # exit;
                # }
                # $externalKnackDataLibNames{$thisLib{$_}} = $thisLibID;
            # }
        # }
    }
    # $log->addLine(Dumper(\%externalKnackData));
    # $log->addLine(Dumper(\%externalKnackDataLibNames));
}

sub findDifferences
{
    my @rowarray = @{$_[0]};
    my @order = @{$_[1]};
    my %csvColMap = %{$_[2]};
    my $id = $_[3];
    my @ret = ();
    foreach(@order)
    {
        my $colpos = $_;
        my $query = "select id from $stagingTable where id = $id and ".$csvColMap{$colpos} . " != '".escapeData(@rowarray[$colpos])."'\n";
        # $log->addLine($query);
        my @results = @{$dbHandler->query($query)};
        push(@ret,$colpos) if($#results > -1);
    }
    return \@ret;
}

sub lookupExistingSiloInStaging
{
    my $siloCode = shift;
    
    my $query = "select id from $stagingTable where silo_code='$siloCode'";
    my @results = @{$dbHandler->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        return @row[0];
    }
    return -1;
}

sub checkFileReady
{
    my $file = @_[0];
    my $worked = open (inputfile, '< '. $file);
    my $trys=0;
    if(!$worked)
    {
        print "******************$file not ready *************\n";
    }
    while (!(open (inputfile, '< '. $file)) && $trys<100)
    {
        print "Trying again attempt $trys\n";
        $trys++;
        sleep(1);
    }
    close(inputfile);
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

sub createStagingTable
{
    my @headers = @{$_[0]};
    my @cols = ();
    # Original draft used to ues the csv file to dictate the column names. Now they are hard coded at the top of this script
    # push (@cols, convertStringToFriendlyColumnName($_,\@cols)) foreach(@headers);
    # $dbHandler->update("DROP TABLE $stagingTable");
    # print "SELECT table_name FROM information_schema.tables WHERE table_schema = '$databaseName' AND table_name = '$stagingTable'\n";
    my @exists = @{$dbHandler->query("SELECT table_name FROM information_schema.tables WHERE table_schema = '$databaseName' AND table_name = '$stagingTable'")};
    if(!$exists[0])
    {
        print "doesn't exist\n";
        my $query = "CREATE TABLE $stagingTable (
        id int not null auto_increment,
        changed boolean default true,
        knackid varchar(300),
        nid int,\n";
        while ( (my $key, my $value) = each(%csvColMap) )
        {
            push @cols, $value;
        }
        $query.="$_ varchar(300),\n" foreach(@cols);
        $query.="PRIMARY KEY (id)\n";
        $query.=")\n";
        $log->addLine($query);
        $dbHandler->update($query);        
    }
    else
    {
        print "Staging table already exists\n";
    }
}

sub convertStringToFriendlyColumnName
{
    my $st = shift;
    my @previousCols = @{$_[0]};
    my $ret = lc $st;
    $ret =~s/^\s*//g;
    $ret =~s/\s*$//g;
    $ret =~s/\s/_/g;
    $ret =~s/[\-\.'"\[\]\{\}\/\(\)\?\!\>\<]//g;
    my $first = 1;
    my $exists = 0;
    while($first || $exists)
    {
        $exists = 0;
        $exists = ($_ eq $ret) ? 1 : 0 foreach(@previousCols);
        if($exists)
        {
            $ret.="_0" if $first;
            my @tok = split(/_/,$ret);
            my $rep_num = pop @tok;
            $ret = '';
            $ret.= $_."_" foreach(@tok);            
            $rep_num++;
            $ret .= $rep_num;            
        }
        $first = 0;
    }
    $log->addLine($ret) if $debug;
    return $ret;
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



## Saving this code in case we ever want to try to directly talk to the drupal tables
 # drupal decode:
    # node table contains the main entry where nid is the main key
    # This table also contains the main data: title (library Name is stored here)
    # Then each of the other tbles listed below are forien keys to nid with columns generally named "entity_id" maps to node.nid

    # Location is a modeul in Drupal that changes the game a little
    # We are using Location to collect all of the address information. These fields are connected back to node.nid:
    # location_instance.nid = node.nid
    # location_instance.lid = location.lid
    
    # Contact info is scattered around as well.
    # field_data_field_contact.entity_id = node.nid
    # field_data_field_contact.field_contact_value = field_data_field_email.entity_id and bundle='field_contact' and entity_type='field_collection_tiem'
    
# sub populateNID
# {
    # my $ID = shift;
    # my $nID = shift;
    # my $thisLibName = shift;
    # my $thisLibAddress = shift;
    # return $nID if ($nID && $nID ne 'undef');
    # my $nid = findNID($ID,$thisLibName,$thisLibAddress);
    # if(!$nid)  ## we have a new library to create    
    # {
        # print "Creating new NODE $ID\n";
        # $query = "INSERT into node(type,language,title,created,changed)
        # select '$drupalStructureName','und', library_name,1572299979,1572299979 from 
        # $stagingTable where id = ?";
        # my @vars = ($ID);
        # $log->addLine($query);
        # $dbHandler->updateWithParameters($query,\@vars);
        # $nid = findNID($ID,$thisLibName,$thisLibAddress);

        # # a revision row is required
        # $query = "INSERT into node_revision(nid,language,title)
        # select $nid, library_name from 
        # $stagingTable where id = ?";
        # my @vars = ($ID);
        # $log->addLine($query);
        # $dbHandler->updateWithParameters($query,\@vars);
        # exit;
        
    # }
    # if($nid)
    # {
        # updateInsertFlatFieldAll($ID,$nid);
        # my $query = "update $stagingTable set nid = ? where id = ?";
        # my @vars = ($nid,$ID);
        # $log->addLine($query);
        # $dbHandler->updateWithParameters($query,\@vars);
    # }
    # return $nid;
# }

# sub updateInsertFlatFieldAll
# {
    # my $ID = shift;
    # my $nid = shift;
    # while ( (my $key, my $value) = each(%drupalFieldMap) )
    # {
        # my $query = "select $key from $stagingTable where id = $ID";
        # my @res = @{$dbHandler->query($query)};
        # updateInsertFlatField($value,$nid,@res[0]) if $#res == 0;
    # }
# }

# sub updateInsertFlatField
# {
    # my $table = shift;
    # my $nid = shift;
    # my $value = shift;
    # my $columnName = $table."_value";
    # $columnName =~ s/^field_data_(.*)/\1/g;
    # my $query = "select entity_id from $table where entity_id = $nid";
    # my @res = @{$dbHandler->query($query)};
    # my @vars = ($value,$nid);
    
    # if(@res[0])  ## update
    # {
        # $query = "update $table set $columnName = ? where entity_id = ?";
    # }
    # else ## insert
    # {
        # $query = "insert into $table (entity_type,bundle,language,delta,$columnName,entity_id)
        # values('node','$drupalStructureName','und',0,?,?)";
        # createRevision($table,$nid,$value);
    # }
    # $log->addLine($query);
    # # $dbHandler->updateWithParameters($query,\@vars);
# }

# sub createRevision
# {
    # my $table = shift;
    # my $nid = shift;
    # my $value = shift;
    # my $revisionTableName = $table;
    # $revisionTableName =~ s/^field_data_(.*)/field_revision_\1/g;
    # my $columnName = $table."_value";
    # $columnName =~ s/^field_data_(.*)/\1/g;
    # print "$table revision became $revisionTableName\n";
    # exit;
    # my $query = "select revision_id from $table where entity_id = $nid";
    # my @res = @{$dbHandler->query($query)};
    # my @vars = ($value,$nid);
    
    # if(@res[0])  ## already exists
    # {
        # return @res[0];
    # }
    # else ## insert
    # {
        # $query = "insert into $table (entity_type,bundle,language,delta,$columnName,entity_id)
        # values('node','$drupalStructureName','und',0,?,?)";
    # }
    # $log->addLine($query);
    # exit;
    # $dbHandler->updateWithParameters($query,\@vars);
    # my $query = "select revision_id from $table where entity_id = $nid";
    # my @res = @{$dbHandler->query($query)};
    # my @vars = ($value,$nid);
    
    # if(@res[0])
    # {
        # return @res[0];
    # }
    # return 0;
# }

# sub findNID
# {
    # my $ID = shift;
    # my $thisLibName = shift;
    # my $thisLibAddress = shift;
    # my $qlibname = lc (escapeData($thisLibName));

    # my $final;
    # my $query = "select n.nid from 
    # node n
    # where
    # type = '$drupalStructureName' and
    # lower(title) = '$qlibname'";
    # $log->addLine($query);
    # my @res = @{$dbHandler->query($query)};
    # return @res[0] if($#res == 0);
    # if($#res > 0) # need further clairification from address
    # {
        # my $qlibadd = lc (escapeData($thisLibAddress));
        # my $query = "select n.nid from 
        # node n,
        # $stagingTable st,
        # location_instance li,
        # location l        
        # where
        # li.nid = n.nid and
        # li.lid = l.lid
        # type = '$drupalStructureName' and
        # lower(n.title) = '$qlibname' and
        # lower(l.street) = '$qlibadd'
        # ";
        # $log->addLine($query);
        # @res = @{$dbHandler->query($query)};
        # return @res[0] if($#res == 0);
    # }
    # return 0;
# }

# sub findDrupalNIDFromLibName
# {
    # my $libName = shift;
    # my $query = "select nid from node where type = '$drupalStructureName' and title = '".escapeData($drupalStructureName)."'";
    # my @an = @{$dbHandler->query($query)};
    # foreach(@an)
    # {
        # my @row = @{$_};
        # return @row[0];
    # }
    # return -1;
# }

sub figurePIDFileStuff
{
    if (-e $pidfile)
    {
        #Check the processes and see if there is a copy running:
        my $thisScriptName = $0;
        my $numberOfNonMeProcesses = scalar grep /$thisScriptName/, (split /\n/, `ps -aef`);
        print "$thisScriptName has $numberOfNonMeProcesses running\n";
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
