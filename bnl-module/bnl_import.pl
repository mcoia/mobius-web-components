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
use Try::Tiny;

our $stagingTablePrefix = "mobius_bnl";
our $pidfile = "/tmp/bnl_import.pl.pid";


our $driver;
our $dbHandler;
our $databaseName = '';
our $log;
our $drupalconfig;
our $debug = 0;


# for later
# Query to get branch codes translated to ID's
# select svb.code_num,svl.code from 
# -- select * from
# sierra_view.location svl,
# sierra_view.branch svb
# where
# svb.code_num=svl.branch_code_num

# limit 100
    
    
GetOptions (
"log=s" => \$log,
"drupal-config=s" => \$drupalconfig,
"debug" => \$debug
)
or die("Error in command line arguments\nYou can specify
--log path_to_log_output.log                  [Path to the log output file - required]
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

# setupDB();

initializeBrowser();

my $writePid = new Loghandler($pidfile);
$writePid->truncFile("running");



my $url = "https://archway.searchmobius.org/manage";
 $log->addLine("Getting $url");
    $driver->get($url);
sleep 3;
    $driver->capture_screenshot("/mnt/evergreen/tmp/bnl/mainpage.png", {'full' => 1});


    my $frameNum = 0;
    my $hasWhatIneed = 0;
    my $tries = 0;
    my $error = 0;
    while(!$hasWhatIneed)
    {
        try
        {
            $driver->switch_to_frame($frameNum);
            my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
            if( ($body =~ m/Circ Activity/) && ($body =~ m/<b>CIRCULATION<\/b>/)  )
            {
                $hasWhatIneed=1;
            }
            else
            {
                $frameNum++;
            }
        }
        catch
        {
            $frameNum++;
        };
        # walk back up to the parent frame
        $driver->switch_to_frame();
        $tries++;
        my $error = 1 if $tries > 10;
        $hasWhatIneed = 1 if $tries > 10;
    }
    
    if(!$error)
    {
        $driver->switch_to_frame($frameNum);
        my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
        $log->addLine("Body of the HTML: " . Dumper($body));
        
        my @forms = $driver->find_elements('//form');
        foreach(@forms)
        {
            $thisForm = $_;
            if($thisForm->get_attribute("action") =~ /\/managerep\/startviews\/0\/d\/table_1x1/g )
            {
                $thisForm->submit();
            }
        }
        # my $circActivty = $driver->execute_script("
        
        
        # var doms = document.getElementsByTagName('form');
        
        # for(var i=0;i<doms.length;i++)
        # {
            # var thisaction = doms[i].getAttribute('action');
            
            # if(thisaction.match(/\\/managerep\\/startviews\\/0\\/d\\/table_1x1/g))
            # {
            # doms.[i].submit();
                # //doms[i].getElementsByTagName('input')[0].click();
                # // getAttribute('class');
            # }
        # }
        
        # ");
        sleep 3;
        $driver->switch_to_frame();
        $driver->capture_screenshot("/mnt/evergreen/tmp/bnl/circactivi.png", {'full' => 1});

        # $log->addLine("circ forms: " . Dumper($circActivty));
        
    }
   
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

sub checkColumnLabelRow
{
    my %columnLabels = %{@_[0]};
    my $query = "select id from $stagingTablePrefix where id = -1";
    my @res = @{$dbHandler->query($query)};
    my @vars;
    if($#res > -1)
    {
        $query = "update $stagingTablePrefix set ";
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
        $query = "insert into $stagingTablePrefix (";
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
    $dbHandler->update("update $stagingTablePrefix set changed=0 where id = -1");
}

sub getFriendlyColumnOverrides
{
    my ($dbCol, $friendlyName) = @_;
    # $log->addLine("Checking $dbCol");
    # $log->addLine("Found it to be: ".$friendlyColOverride{$dbCol}) if $friendlyColOverride{$dbCol};
    my $ret = $friendlyColOverride{$dbCol} || $friendlyName || $dbCol;
    return $ret;
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

sub createStagingTable
{
    my @headers = @{$_[0]};
    my @cols = ();
    my @exists = @{$dbHandler->query("SELECT table_name FROM information_schema.tables WHERE table_schema = '$databaseName' AND table_name = '$stagingTable'")};
    if(!$exists[0])
    {
        print "doesn't exist\n";
        my $query = "CREATE TABLE $stagingTablePrefix (
        id int not null auto_increment,
        changed boolean default true,
        ";
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
