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

# Logic is handled in crontab - just run dude
unlink $pidFile;

setupDB();
updateOldData() if @ARGV[3];
exit if @ARGV[3];


our $pidfile = "/tmp/datatrac_parse.pl.pid";

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

$log->truncFile("");
my $writePid = new Loghandler($pidfile);
$writePid->truncFile("running");
undef $writePid;

while(1)
{

    my @files;
    @files = @{dirtrav(\@files, $dirRoot)};

    foreach(@files)
    {
        my $file = $_;
        my $path;
        my %translates = %{getTranslationCodes()};
        my @sp = split('/',$file);
       
        $path=substr($file,0,( (length(@sp[$#sp]))*-1) );
                
        checkFileReady($file);
        my $csv = Text::CSV->new ( )
            or die "Cannot use CSV: ".Text::CSV->error_diag ();
        open my $fh, "<:encoding(utf8)", $file or die "$file: $!";
# For reference, these are the live columns
# 'pickuploc','deliveryloc','item', 'pickuploc_code','pickupdate', 'deliverydate'))
# We are going to have to hard code the expected data per column because the column headers contain duplicates
        my $rownum = 0;
        my $success = 0;
        my $queryByHand = '';
        my %colmap = (
        0 => 'item',
        1 => 'pickupdate',
        2 => 'pickuploc',
        3 => 'pickupdriver',
        4 => 'pickuploc_code',
        5 => 'deliverydate',
        6 => 'deliveryloc',
        7 => 'deliverydriver',
        8 => 'deliveryloc_code'        
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
        $queryInserts .= "elapsedtime,elapsed_not_counted)\nVALUES \n";
        $queryByHand .= "elapsedtime,elapsed_not_counted)\nVALUES \n";
        
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
                my $ignoredDays;
                my $valid = 1;
                my $pickuploc;
                my $deliveryloc;
                
                my $thisLineInsert = '';
                my $thisLineInsertByHand = '';
                my @thisLineVals = ();
                
                foreach(@order)
                {
                    my $colpos = $_;
                    # print "reading $colpos\n";
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
                    
                    # do not import lines where the institution is mangled. It needs to be at least 20 characters and not more than 23
                    $valid = 0                                                                            if( ($colmap{$colpos} eq 'item') && ((length(@rowarray[$colpos]) < 20) || (length(@rowarray[$colpos]) > 23)) );
                    $log->addLine("Found invalid item column on line $rownum data = ".@rowarray[$colpos]) if( ($colmap{$colpos} eq 'item') && ((length(@rowarray[$colpos]) < 20) || (length(@rowarray[$colpos]) > 23)) );
                    
                    # gather up the special vars
                    $pickuploc = @rowarray[$colpos] if($colmap{$colpos} eq 'pickuploc_code');
                    $deliveryloc = @rowarray[$colpos] if($colmap{$colpos} eq 'deliveryloc_code');
                }
                
                ($elapsedDays,  $ignoredDays) = figureElapseDeliveryTime($startDate, $endDate, $deliveryloc);
                
                # do not import lines where the start and end institutions are equal
                $valid = 0 if($pickuploc eq $deliveryloc);
                $log->addLine("Found equal institutions line $rownum $pickuploc = $deliveryloc") if($pickuploc eq $deliveryloc);
                
                
                # print "Valid = $valid and days = $elapsedDays\n";
                if($valid && $elapsedDays)
                {
                    
                    # Translate and convert the string version of the library name from our "normalized" version
                    my $l = 0;
                    foreach(@order)
                    {
                        my $colpos = $_;
                        if($colmap{$colpos} eq 'pickuploc')
                        {
                            $log->addLine("Changing ".@thisLineVals[$l]." into ".$translates{$pickuploc}) if (@thisLineVals[$l] ne $translates{$pickuploc});
                            @thisLineVals[$l] = $translates{$pickuploc} if($translates{$pickuploc});
                        }
                        elsif($colmap{$colpos} eq 'deliveryloc')
                        {
                            $log->addLine("Changing ".@thisLineVals[$l]." into ".$translates{$deliveryloc}) if (@thisLineVals[$l] ne $translates{$deliveryloc});
                            @thisLineVals[$l] = $translates{$deliveryloc} if($translates{$deliveryloc});
                        }
                        $l++;
                    }
                    
                    $thisLineInsert .= '?,?';
                    $thisLineInsertByHand.="'$elapsedDays','$ignoredDays'";
                    push (@thisLineVals, $elapsedDays);
                    push (@thisLineVals, $ignoredDays);
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

        $log->addLine($queryInserts);
        $log->addLine($queryByHand);
        $log->addLine(Dumper(\@queryValues));
        
        close $fh;
        $log->addLine("Importing $success / $rownum");
        
        $dbHandler->updateWithParameters($queryInserts,\@queryValues);
        
        # Clean out duplicate barcodes
        my $queryClean = "DELETE from dtdata where
        number in(
        select thenumber from 
        (
            select min(number) as thenumber,item from dtdata
            WHERE
            item IN
            (
            select item FROM
            (
            select item,count(*) from dtdata group by 1 having count(*)>1
            ) as dups
            )
            group by 2
        ) as dupclear
        )
        ";
        $dbHandler->update($queryClean);
        # delete the file so we don't read it again
        unlink $file;
    }
   sleep 5;
}

sub getTranslationCodes
{
    my %ret = ();
    my $query = '
select n.title,fdflcc.field_library_courier_code_value from field_data_field_library_courier_code fdflcc,
node n
where
fdflcc.entity_id=n.nid
    ';
    
    my @results = @{$dbHandler->query($query)};
    
    foreach(@results)
    {
        my @row = @{$_};
        $ret{@row[1]} = @row[0];
    }
    
    return \%ret;
}

sub figureElapseDeliveryTime
{
    my $startDate = shift;
    my $endDate = shift;
    my $destCode = shift;
    return 0 if(!$startDate || !$endDate || !$destCode);
    
    $destCode = lc $destCode;
    my $dateWalk = $startDate->clone();
    my $daysToSubtract = 0;
    
    my %dowTranslate = (
            'Monday'    => 1,
            'Tuesday'   => 2,
            'Wednesday' => 3,
            'Thursday'  => 4,
            'Friday'    => 5,
            'Saturday'  => 6,
            'Sunday'    => 7
            );
    
    # Figure out which of the days of the week this destination library DOES NOT receive courier
    my $query = '
            SELECT (select GROUP_CONCAT(distinct field_weekday_value) from field_data_field_weekday where entity_id=node.nid group by entity_id )
            FROM 
            node node
            WHERE (( (node.status = \'1\') AND (node.type IN  (\'courier_weekly_delivery\')) ))
            and
            node.nid in(
            select entity_id from field_data_field_library_courier_code fdflcc
            where trim(lower(field_library_courier_code_value)) = 
            trim(\''.$destCode.'\')
            -- trim(lower(\' IA-NE-600\'))
            );
        ';
    my @results = @{$dbHandler->query($query)};

    my %skipWeekDays = ();
    my %skipHolidays = ();
    foreach(@results)
    {
        foreach(@{$_})
        {
            my @sp = split(',',$_);
            foreach(@sp)
            {
                $skipWeekDays{ $dowTranslate{$_} } = 1;
            }
        }
    }
    # print "skipweekdays = ".Dumper(\%skipWeekDays)."\n";
    
    # Collect possible holidays during this period
    $query = '
           SELECT CAST( field_data_field_the_closed_date.field_the_closed_date_value AS DATE) AS field_data_field_the_closed_date_field_the_closed_date_value
            FROM 
            node node
            LEFT JOIN field_data_field_the_closed_date field_data_field_the_closed_date ON node.nid = field_data_field_the_closed_date.entity_id AND field_data_field_the_closed_date.entity_type = \'node\'
            WHERE (( (node.status = \'1\') AND (node.type IN  (\'library_closed_dates\')) ))
            and
            CAST( field_data_field_the_closed_date.field_the_closed_date_value AS DATE) between CAST( \''.$startDate.'\' AS DATE) and CAST( \''.$endDate.'\' AS DATE);
        ';
    @results = @{$dbHandler->query($query)};
    
    foreach(@results)
    {
        foreach(@{$_})
        {
            $skipHolidays{$_} = 1;
        }
    }
    
    while($dateWalk < $endDate)
    {
        # ignore weekends        
        if($dateWalk->day_of_week() =~ m/[67]/)
        {
            $daysToSubtract++;
        }
        # ignore days that the destination library does not recieve courier
        elsif($skipWeekDays{$dateWalk->day_of_week()})
        {
            $daysToSubtract++;
        }
        # ignore days that the whole delivery system is shut down
        elsif($skipHolidays{$dateWalk->strftime( '%Y-%m-%d' )})
        {
            $daysToSubtract++;
        }
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
        
    # Now we need to catch a scenario where we calculated 0 days but the pickup and delivery dates are not equal
    # print "elapsed = $elapsedDays\n$startDate\n$endDate\n" if( $elapsedDays==0 && ( $startDate != $endDate ) );
    $daysToSubtract-- if( $elapsedDays==0 && ( $startDate != $endDate ) );
    $elapsedDays = 1 if( $elapsedDays==0 && ( $startDate != $endDate ) );
    
    
    # print "$elapsedDays\n";

    return ($elapsedDays, $daysToSubtract);
    
}

sub updateOldData
{
    my $elapsedDays;
    my $ignoredDays;
    my $startDate;
    my $endDate;
    
    my $query = "SELECT number,deliveryloc_code,pickupdate,deliverydate from dtdata";
    my @results = @{$dbHandler->query($query)};
    my $total = $#results;
    my $i = 0;
    foreach(@results)
    {
        my @line = @{$_};
        my $valid = 1;
        
        @line[2] =~ s/(\d*)[\/\\\-](\d*)[\/\\\-](\d*)\s.*/$3-$1-$2/;
        @line[3] =~ s/(\d*)[\/\\\-](\d*)[\/\\\-](\d*)\s.*/$3-$1-$2/;
        my ($y,$m,$d) = @line[2] =~ /^([0-9]{4})\-([0-9]{1,2})\-([0-9]{1,2})\z/;
        if($y && $m && $d)
        {
            $startDate = DateTime->new( year => $y, month => $m, day => $d );
        }
        else
        {
            $log->addLine("Line @line[2] contained an invalid date - skipping");
            $valid = 0;
        }
        my ($y,$m,$d) = @line[3] =~ /^([0-9]{4})\-([0-9]{1,2})\-([0-9]{1,2})\z/;
        if($y && $m && $d)
        {
            $endDate = DateTime->new( year => $y, month => $m, day => $d );
        }
        else
        {
            $log->addLine("Line @line[3] contained an invalid date - skipping");
            $valid = 0;
        }
        
        if($valid)
        {
            ($elapsedDays,  $ignoredDays) = figureElapseDeliveryTime($startDate, $endDate, @line[1]);
            $query = "UPDATE dtdata SET elapsedtime=?,elapsed_not_counted=? where number=?";
            my @arr = ($elapsedDays, $ignoredDays, @line[0]);            
            $dbHandler->updateWithParameters($query,\@arr);
        }
        print "$i / $total\n" if ($i % 100 == 0 );
        $i++;
    }
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
