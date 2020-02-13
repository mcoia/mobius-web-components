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

our $stagingTablePrefix = "mobius_bnl";
our $pidfile = "/tmp/bnl_import.pl.pid";


our $driver;
our $dbHandler;
our $databaseName = '';
our $log;
our $drupalconfig;
our $debug = 0;
our $recreateDB = 0;
our $dbSeed;


    
GetOptions (
"log=s" => \$log,
"drupal-config=s" => \$drupalconfig,
"debug" => \$debug,
"recreateDB" => \$recreateDB,
"dbSeed=s" => \$dbSeed
)
or die("Error in command line arguments\nYou can specify
--log path_to_log_output.log                  [Path to the log output file - required]
--drupal-config                               [Path to the drupal config file]
--debug                                       [Cause more log output]
--recreateDB                                  [Deletes the tables and recreates them]
--dbSeed                                      [DB Seed file - populating the base data]
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

my $cluster = new sierraCluster('archway',$dbHandler,$stagingTablePrefix,$driver,$cwd,$log);
$cluster->scrape();

    # my %libraryVals = ();
    
    # pQuery(".kn-detail",$body)->each(sub {
        # my $i = shift;
        # my $key;
        # my $value;
        # pQuery(".kn-detail-label > span", $_)->each(sub {
            # $key = pQuery($_)->text();
        # })->end();
        # pQuery(".kn-detail-body > span", $_)->each(sub {
            # $value = pQuery($_)->text();
        # })->end();
        # if($key && $value)
        # {
            # $libraryVals{$key} = $value;
        # }
        # undef $key;
        # undef $value;
        # # print $i, " => ", pQuery($_)->html(), "\n";
    # });
    
    # $log->addLine(Dumper(\%libraryVals)) if $debug;
    
    

undef $writePid;
closeBrowser();
$log->addLogLine("****************** Ending ******************");


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

    # my $pageLoaded = 0;
    # my $giveup = 100;
    # my $tries = 0;
    # while(!$pageLoaded)
    # {
       # $pageLoaded = $driver->find_element_by_class("kn-detail");
       # sleep 1;
       # # $log->addLine("javascript: " . $driver->has_javascript);
       # # if($tries == 20)
       # # {
            # # $driver->capture_screenshot("/home/ma/iowa_courier_data_import/test.png", {'full' => 1});
       # # }
       # return 0 if ($tries > $giveup);
       # $tries++;
    # }
    # my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
    # # $log->addLine("Body of the HTML: " . Dumper($body));
    # my %libraryVals = ();
    
    # pQuery(".kn-detail",$body)->each(sub {
        # my $i = shift;
        # my $key;
        # my $value;
        # pQuery(".kn-detail-label > span", $_)->each(sub {
            # $key = pQuery($_)->text();
        # })->end();
        # pQuery(".kn-detail-body > span", $_)->each(sub {
            # $value = pQuery($_)->text();
        # })->end();
        # if($key && $value)
        # {
            # $libraryVals{$key} = $value;
        # }
        # undef $key;
        # undef $value;
        # # print $i, " => ", pQuery($_)->html(), "\n";
    # });
    
    # $log->addLine(Dumper(\%libraryVals)) if $debug;

    
    # return \%libraryVals;
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
        my $query = "DROP TABLE $stagingTablePrefix"."_cluster ";
        $log->addLine($query);
        $dbHandler->update($query);
    }

    my @exists = @{$dbHandler->query("SELECT table_name FROM information_schema.tables WHERE table_schema RLIKE '$databaseName' AND table_name RLIKE '$stagingTablePrefix'")};
    if(!$exists[0])
    {
        my $query = "CREATE TABLE $stagingTablePrefix"."_cluster (
        id int not null auto_increment,
        name varchar(100),
        report_base_url varchar(1000),
        report_username varchar(100),
        report_pass varchar(100),
        postgres_url varchar(100),
        postgres_db varchar(100),
        postgres_port varchar(100),
        postgres_username varchar(100),
        postgres_password varchar(100),
        ";
        $query.="PRIMARY KEY (id)\n";
        $query.=")\n";
        $log->addLine($query) if $debug;
        $dbHandler->update($query);
        
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
    my @tables = (
    'cluster'
    );
    
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
            if( ($#cols > 0) && ($#datavals > -1) )
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
    if( ($#cols > 0) && ($#datavals > -1) )
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
