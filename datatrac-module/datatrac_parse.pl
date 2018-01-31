#!/usr/bin/perl


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

our $dirRoot = @ARGV[0];
our $dbHandler;
if(!$dirRoot)
{
    print "Please specify a directory root \n";
    exit;
}
our $log = @ARGV[1];
if(!$log)
{
    print "Please specify a logfile \n";
    exit;
}
my $drupalconfig = @ARGV[2];
if(!$log)
{
    print "Please specify a drupal config logfile \n";
    exit;
}
 
$log = new Loghandler($log);

$drupalconfig = new Loghandler($drupalconfig);

setupDB();

$log->truncFile("");

our $pidfile = "/tmp/datatrac_parse.pl.pid";

if (-e $pidfile)
{
    #Check the processes and see if there is a copy running:
    my $thisScriptName = $0;
    my $numberOfNonMeProcesses = scalar grep /$thisScriptName/, (split /\n/, `ps -aef`);
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

my $writePid = new Loghandler($pidfile);
$writePid->addLine("running");
undef $writePid;

# while(1)
# {

    my @files;
    @files = @{dirtrav(\@files, $dirRoot)};

    foreach(@files)
    {
        my $file = $_;
        my $path;
       
        my @sp = split('/',$file);
       
        $path=substr($file,0,( (length(@sp[$#sp]))*-1) );
                
        checkFileReady($file);
        my $csv = Text::CSV->new ( )
            or die "Cannot use CSV: ".Text::CSV->error_diag ();
        open my $fh, "<:encoding(utf8)", $file or die "$file: $!";
# For reference, these are the live columns
# 'pickuploc','deliveryloc','item', 'pickuproute','pickupdate', 'deliverydate'))
# We are going to have to hard code the expected data per column because the column headers contain duplicates
        my $rownum = 0;
        my $success = 0;
        my $queryByHand = '';
        my %colmap = (
        0 => 'item',
        1 => 'pickupdate',
        2 => 'pickuploc',
        3 => 'pickupdriver',
        4 => 'pickuproute',
        5 => 'deliverydate',
        6 => 'deliveryloc',
        7 => 'deliverydriver',
        8 => 'deliveryroute'        
        );
        my %spliters = ('pickupdate'=>1,'deliverydate'=>1);
        
        my $queryInserts = "INSERT INTO dtdata(";
        $queryByHand = "INSERT INTO dtdata(";
        my @order = ();
        my $sanitycheckcolumnnums = 1;
        my @queryValues = ();
        while ( (my $key, my $value) = each(%colmap) )
        {
            $queryInserts .= $value.",";
            $queryByHand .= $value.",";
            push @order, $key;
            $sanitycheckcolumnnums++
        }
        $queryInserts .= "elapsedtime)\nVALUES (\n";
        $queryByHand .= "elapsedtime)\nVALUES (\n";
        
        while ( my $row = $csv->getline( $fh ) )
        {
            # if($rownum < 2)
            # {
            # $log->addLine(Dumper($row));
            my @rowarray = @{$row};
            # $log->addLine(Dumper(\@rowarray));
            if(scalar @rowarray != $sanitycheckcolumnnums )
            {
                $log->addLine("Error parsing line $rownum\nIncorrect number of columns: ". scalar @rowarray);
            }
            else
            {
                my $startDate;
                my $endDate;
                my $elapsedDays;
                my $valid = 1;
                my $pickuploc;
                my $deliveryloc;
                
                my $thisLineInsert = '';
                my $thisLineInsertByHand = '';
                my @thisLineVals = ();
                
                foreach(@order)
                {
                    my $colpos = $_;
                    $thisLineInsert .= '?,';
                    # Trim whitespace off the data
                    @rowarray[$colpos] =~ s/^[\s\t]*(.*)/$1/;
                    @rowarray[$colpos] =~ s/(.*)[\s\t]*$/$1/;
                    # print @rowarray[$colpos]."\n";
                    # The date and time come in together, gotta split em
                    # the data needs to be convereted to db style
                     
                    if( $spliters{$colmap{$colpos}} )
                    {
                        @rowarray[$colpos] =~ s/(\d*)[\/\\\-](\d*)[\/\\\-](\d*)\s.*/$3-$1-$2/;
                        # print @rowarray[$colpos]."\n";
                        # Do some date magic
                        my ($y,$m,$d) = @rowarray[$colpos] =~ /^([0-9]{4})\-([0-9]{1,2})\-([0-9]{1,2})\z/;
                        if($y && $m && $d)
                        {
                            # print "$y $m $d\n";
                            $startDate = DateTime->new( year => $y, month => $m, day => $d ) if($colmap{$colpos} eq 'pickupdate');
                            $endDate =   DateTime->new( year => $y, month => $m, day => $d ) if($colmap{$colpos} eq 'deliverydate');
                            # print "startdate = $startDate\n";
                            # print "endDate = $endDate\n";
                            if($startDate && $endDate)
                            {
                                # $startDate = DateTime->new( year => 2018, month => 01, day => 01 );
                                # $endDate =   DateTime->new( year => 2018, month => 01, day => 15 );
                                
                            }
                        }
                        else
                        {
                            $log->addLine("Line $rownum contained an invalid date - skipping");
                            $valid = 0;
                        }
                    }
                    $thisLineInsertByHand.="'".@rowarray[$colpos]."',";
                    push (@thisLineVals, @rowarray[$colpos]);
                    # $log->addLine(Dumper(\@thisLineVals));
                    
                    # do not import lines where the institution is mangled. It needs to be at least 22 characters and not more than 23
                    $valid = 0 if( ($colmap{$colpos} eq 'item') && (length(@rowarray[$colpos]) < 22) || (length(@rowarray[$colpos]) > 23) );
                    $log->addLine("Found invalid item column on line $rownum data = ".@rowarray[$colpos]) if( ($colmap{$colpos} eq 'item') && ((length(@rowarray[$colpos]) < 22) || (length(@rowarray[$colpos]) > 23)) );
                    
                    # gather up the special vars
                    $pickuploc = @rowarray[$colpos] if($colmap{$colpos} eq 'pickuploc');
                    $deliveryloc = @rowarray[$colpos] if($colmap{$colpos} eq 'deliveryloc');
                }
                
                $elapsedDays = figureElapseDeliveryTime($startDate, $endDate);
                
                # do not import lines where the start and end institutions are equal
                $valid = 0 if($pickuploc eq $deliveryloc);
                $log->addLine("Found equal institutions line $rownum $pickuploc = $deliveryloc") if($pickuploc eq $deliveryloc);
                

                if($valid && $elapsedDays)
                {
                    $thisLineInsert .= '?';
                    $thisLineInsertByHand.="'$elapsedDays'";
                    push (@thisLineVals, $elapsedDays);
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
        # }
         
        }
        
        $queryInserts = substr($queryInserts,0,-2).")" if $success;
        $queryByHand = substr($queryByHand,0,-2).")" if $success;
        
        # Handle the case when there is only one row inserted
        if($success == 1)
        {
            $queryInserts =~ s/VALUES \(/VALUES /;            
            $queryInserts = substr($queryInserts,0,-1);
        }

        $log->addLine($queryInserts);
        $log->addLine($queryByHand);
        $log->addLine(Dumper(\@queryValues));
        
        close $fh;
        $log->addLine("Importing $success / $rownum");
        
        # $dbHandler->updateWithParameters($queryInserts,\@queryValues);

        # exit;
    }
   sleep 5;
# }

sub figureElapseDeliveryTime
{
    my $startDate = shift;
    my $endDate = shift;
    my $destCode = shift;
    my $dateWalk = $startDate->clone();
    my $daysToSubtract = 0;

    while($dateWalk < $endDate)
    {
        # ignore weekends
        $daysToSubtract++ if($dateWalk->day_of_week() =~ m/[67]/);
        
        ## TODO: include library closed dates from database
        
        
        $dateWalk = $dateWalk->add( days => 1 );
    }

    # print "days to subtract = $daysToSubtract\n";

    # print "startdate = $startDate\n";
    # print "endDate = $endDate\n";
    my $difference = $endDate - $startDate;                                
    #my $format = DateTime::Format::Duration->new(pattern => '%m %e %H %M %S');
    my $format = DateTime::Format::Duration->new(pattern => '%e');
    my $duration =  $format->format_duration($difference);
    my $elapsedDays = $duration - $daysToSubtract;
    # print "$elapsedDays\n";
    
# SELECT node.title AS node_title, node.nid AS nid, node.changed AS node_changed, node.created AS node_created, 'node' AS field_data_field_library_courier_code_node_entity_type, (select GROUP_CONCAT(distinct field_weekday_value) from field_data_field_weekday where entity_id=node.nid group by entity_id )
# FROM 
# node node
# WHERE (( (node.status = '1') AND (node.type IN  ('courier_weekly_delivery')) ))
#
#


    return $elapsedDays;
    
}

sub updateOldData
{
    
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
        my $line = $_;
        
        # Trim whitespace off the data
        $line =~ s/^[\s\t]*(.*)/$1/;
        $line =~ s/(.*)[\s\t]*$/$1/;
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
    $dbHandler = new DBhandler($answers{'database'},$answers{'host'},$answers{'username'},$answers{'password'},$answers{'port'}||"3306","mysql");
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

sub DESTROY
{
    print "I'm dying, deleting PID file $pidFile\n";
    unlink $pidFile;
}

exit;
