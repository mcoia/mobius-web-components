#!/usr/bin/perl

package iiiServer;

use pQuery;
use Try::Tiny;
use Data::Dumper;

our $screenShotStep = 0;


sub new
{
    my $class = shift;
    my $self = 
    {
        name => shift,
        dbHandler => shift,
        prefix => shift,
        driver => shift,
        screenshotDIR => shift,
        monthsBack => shift,
        blindDate => shift,
        log => shift,
        webURL => '',
        webLogin => '',
        webPass => '',
        pgURL => '',
        pgPort => '',
        pgDB => '',
        pgUser => '',
        pgPass => '',
        clusterID => -1,
        error => 0,
        postgresConnector => undef
    };
    if($self->{name} && $self->{dbHandler} && $self->{prefix} && $self->{driver} && $self->{log})
    {
        # $self->{log}->addLine("Before: ".Dumper($self));
        $self = getClusterVars($self); 
        $self->{log}->addLine("after: ".Dumper($self));
    }
    else
    {
        $self->{error} = 1;
    }
    bless $self, $class;
    return $self;
}

sub collectReportData
{
    my ($self) = shift;
    my $dbDate = shift;
print "collectReportData parent\n";
# Setup collection Variables
    my @borrowingLibs = ();
    my %borrowingMap = ();
    
    my $owning = $self->{driver}->execute_script("
        var doms = document.getElementsByTagName('table');
        var stop = 0;
        if( (doms.length - 1) > -1)
        {
            return doms[doms.length - 1].innerHTML;
        }
        ");
    $self->{log}->addLine("Got this: $owning");
    my $rowNum = 0;
    pQuery("tr",$owning)->each(sub {
        if($rowNum > 0) ## Skipping the title row
        {
            my $i = shift;
            my $row = $_;
            my $colNum = 0;
            my $owningLib = '';
            pQuery("td",$row)->each(sub {
                shift;
                if($rowNum == 1) # Header row - need to collect the borrowing headers
                {
                    push @borrowingLibs, pQuery($_)->text();
                }
                else
                {
                    if($colNum == 0) # Owning Library
                    {
                        $owningLib = pQuery($_)->text();
                    }
                    else
                    {
                        if(!$borrowingMap{$owningLib})
                        {   
                            my %newmap = ();
                            $borrowingMap{$owningLib} = \%newmap;
                        }
                        my %thisMap = %{$borrowingMap{$owningLib}};
                        $thisMap{@borrowingLibs[$colNum]} = pQuery($_)->text();
                        $borrowingMap{$owningLib} = \%thisMap;
                    }
                }
                $colNum++;
            });
           
        }
        $rowNum++;
    });

    # Spidered the table - now saving it to storage
    my $randomHash = $self->generateRandomString(12);
    print "Random hash = $randomHash\n";
    my @vals = ();
    my $query = "INSERT INTO 
    $self->{prefix}"."_bnl_stage
    (working_hash,owning_lib,borrowing_lib,quantity,borrow_date)
    values
    ";
    while ((my $key, my $value ) = each(%borrowingMap))
    {
        my %innermap = %{$value};
        while ((my $insideKey, my $insideValue ) = each(%innermap))
        {
            $query .= "(?,?,?,?,?),\n";
            push @vals, ($randomHash, $key, $insideKey, $insideValue, $dbDate);
        }
    }
    $query = substr($query,0,-2);
    $self->{log}->addLine($query);
    # $self->{log}->addLine(Dumper(\@vals));
    $self->{dbHandler}->updateWithParameters($query,\@vals);
    undef $borrowingMap;
    undef $query;
    undef @vals;
    return $randomHash;
}

sub getClusterVars
{
    my ($self) = @_[0];

    my $query = "select 
    id,
    report_base_url,
    report_username,
    report_pass,
    postgres_url,
    postgres_db,
    postgres_port,
    postgres_username,
    postgres_password
    from
    ".$self->{prefix}.
    "_cluster
    where
    name = '".$self->{name}."'";

    my @results = @{$self->{dbHandler}->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $self->{log}->addLine("Cluster vals: ".Dumper(\@row));
        $self->{clusterID} = @row[0];
        $self->{webURL} = @row[1];
        $self->{webLogin} = @row[2];
        $self->{webPass} = @row[3];
        $self->{pgURL} = @row[4];
        $self->{pgDB} = @row[5];
        $self->{pgPort} = @row[6];
        $self->{pgUser} = @row[7];
        $self->{pgPass} = @row[8];
    }

    $self->{error} = 1 if($#results == -1);

    return $self;
}

sub figureWhichDates
{
    my ($self) = shift;
    my $monthsBack = shift || $self->{monthsBack} || 5;    
    print "going back $monthsBack\n";
    $monthsBack++;
    my %alreadyScraped = ();
    
    my @months = qw( onebase Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
    my @ret = ();
    my @dbVals = ();
    
    if(!$blindDate)
    {
        my $query = "
        select
        distinct
        concat(extract(year from borrow_date),'-',extract(month from borrow_date) )
        from
        $self->{prefix}"."_bnl bnl,
        $self->{prefix}"."_cluster cluster
        where
        cluster.id=bnl.owning_cluster and
        cluster.name ='".$cluster."'
        order by 1
        ";

        $self->{log}->addLine($query);
        my @results = @{$self->{dbHandler}->query($query)};
        foreach(@results)
        {
            my @row = @{$_};
            $alreadyScraped{ @row[0] } = 1;
        }
    }
    my $loops = 1;
    while($loops < $monthsBack)
    {
        my $query = "
        select
        concat(
        extract(year from date_sub(now(),interval $loops month)),
        '-',
        extract(month from date_sub(now(), interval $loops month))        
        ),
        right(extract(year from date_sub(now(), interval $loops month)),2),
        extract(month from date_sub(now(), interval $loops month)),
        cast( 
        
        concat
        (
            extract(year from date_sub(now(), interval $loops month)),
            '-',
            extract(month from date_sub(now(), interval $loops month)),
            '-01'
        )
        as date
        )
        ";
        $self->{log}->addLine($query);
        my @results = @{$self->{dbHandler}->query($query)};
        foreach(@results)
        {
            my @row = @{$_};
            push @ret, "" . @months[@row[2]] . " " . @row[1] if !$alreadyScraped{ @row[0] };
            push @dbVals, @row[3] if !$alreadyScraped{ @row[0] };
        }
        $loops++;
    }

    @ret = ([@ret],[@dbVals]);
    return \@ret;
}

sub switchToFrame
{
print "switchToFrame\n";
    my ($self) = @_[0];
    my @pageVals = @{@_[1]};
    my $frameNum = 0;
    my $hasWhatIneed = 0;
    my $tries = 0;
    my $error = 0;
    while(!$hasWhatIneed)
    {
        try
        {
            $self->{driver}->switch_to_frame($frameNum); # This can throw an error if the frame doesn't exist
            my $body = $self->{driver}->execute_script("return document.getElementsByTagName('html')[0].innerHTML");            
            $body =~ s/[\r\n]//g;
            my $notThere = 0;
            foreach(@pageVals)
            {
                $notThere = 1 if (!($body =~ m/$_/) );
            }
            if(!$notThere)
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
        $self->{driver}->switch_to_frame();
        $tries++;
        $error = 1 if $tries > 10;
        $hasWhatIneed = 1 if $tries > 10;
    }
    if(!$error)
    {
        # print "About to switch to a real frame: $frameNum\n";
        try
        {
            $self->{driver}->switch_to_frame($frameNum);
        }
        catch
        {
            takeScreenShot($self,"error_switching_frame");
        };
    }
    return $error;
}

sub takeScreenShot
{
    my ($self) = shift;
    my $action = shift;
    $screenShotStep++;
    $self->{driver}->capture_screenshot("$screenshotDIR/".$self->{name}."_".$screenShotStep."_".$action.".png", {'full' => 1});
}


sub generateRandomString
{
    my ($self) = shift;
	my $length = @_[0];
	my $i=0;
	my $ret="";
	my @letters = ('a','b','c','d','e','f','g','h','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z');
	my $letterl = $#letters;
	my @sym = ('@','#','$');
	my $syml = $#sym;
	my @nums = (1,2,3,4,5,6,7,8,9,0);
	my $nums = $#nums;
	my @all = ([@letters],[@sym],[@nums]);
	while($i<$length)
	{
		#print "first rand: ".$#all."\n";
		my $r = int(rand($#all+1));
		#print "Random array: $r\n";
		my @t = @{@all[$r]};
		#print "rand: ".$#t."\n";
		my $int = int(rand($#t + 1));
		#print "Random value: $int = ".@{$all[$r]}[$int]."\n";
		$ret.= @{$all[$r]}[$int];
		$i++;
	}
	
	return $ret;
}

sub trim
{
    my ($self) = shift;
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

sub DESTROY
{
    my ($self) = @_[0];
    ## call destructor
    undef $self->{postgresConnector};
}


1;