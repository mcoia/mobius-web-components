#!/usr/bin/perl

package sierraCluster;


use Try::Tiny;
use Data::Dumper;


# for later
# Query to get branch codes translated to ID's
# select svb.code_num,svl.code,svbn.name,svbn.branch_id 
# -- select svbn.name,count(*)
# from
# -- select * from
# sierra_view.location svl,
# sierra_view.branch svb,
# sierra_view.branch_name svbn
# where
# svbn.branch_id=svb.id and
# svb.code_num=svl.branch_code_num

# limit 100


our $log;
our $driver;
our $screenshotDIR;
our $screenShotStep = 0;
our $randomHash;

sub new
{
    my $class = shift;
    my $self = 
    {
        name => shift,
        dbHandler => shift,
        prefix => shift,
        webURL => '',
        webLogin => '',
        webPass => '',
        pgURL => '',
        pgPort => '',
        pgDB => '',
        pgUser => '',
        pgPass => '',
        clusterID => -1,
        error => 0
    };
    $driver = shift;
    $screenshotDIR = shift;
    $log = shift;
    if($self->{name} && $self->{dbHandler} && $self->{prefix} && $driver && $log)
    {
        getClusterVars($self) 
    }
    else
    {
        $self->{error} = 1;
    }
    bless $self, $class;
    return $self;
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
        $log->addLine("Cluster vals: ".Dumper(\@row));
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
}


sub scrape
{
    my ($self) = shift;
    my $monthsBack = shift || 5;
    my @dateScrapes = @{figureWhichDates($self)};

    
    if(!$self->{error})
    {
        $log->addLine("Getting " . $self->{webURL});
        $driver->get($self->{webURL});
        sleep 3; # initial page load takes time.
        takeScreenShot($self,'pageload');
        my $continue = handleLandingPage($self);
        $continue = handleLoginPage($self) if $continue;
        if(@dateScrapes[0])
        {
            $continue = handleCircStatOwningHome($self) if $continue;
            my @pageVals = @{@dateScrapes[0]};
            my @dbvals = @{@dateScrapes[1]};
            my $pos = 0;
            foreach(@pageVals)
            {
                $continue = handleReportSelection($self,$_) if $continue;
                print "Pulling ". @dbvals[$pos] ."\n";
                collectReportData($self, @dbvals[$pos]) if $continue;
                $pos++;
                $continue = handleCircStatOwningHome($self,1) if $continue;
            }
        }
    }
   
}


sub collectReportData
{
    my ($self) = shift;
    my $dbDate = shift;
print "collectReportData\n";
    my @frameSearchElements = ('HOME LIBRARY TOTAL CIRCULATION');
        
    if(!switchToFrame($self,\@frameSearchElements))
    {
        # Setup collection Variables
        my @borrowingLibs = ();
        my %borrowingMap = ();
        
        my @table = $driver->find_elements('//table');
        
        my $table = @table[0] if @table;
        
        my @rows = $table->children('//tr');
        
        my $rowNum = 0;        
        foreach(@rows)
        {
            print "Parsing row $rowNum\n";
            if($rowNum > 0) ## Skipping the title row
            {
                my $row = $_;
                my $rowText = $row->get_text();
                $log->addLine("READING: $rowText");
                my @cells = $driver->find_child_elements($row,'./td');
                my $colNum = 0;
                my $owningLib = '';
                foreach(@cells)
                {
                    if($rowNum == 1) # Header row - need to collect the borrowing headers
                    {
                        push @borrowingLibs, $_->get_text();
                    }
                    else
                    {
                        if($colNum == 0) # Owning Library
                        {
                            $owningLib = $_->get_text();
                        }
                        else
                        {
                            if(!$borrowingMap{$owningLib})
                            {   
                                my %newmap = ();
                                $borrowingMap{$owningLib} = \%newmap;
                            }
                            my %thisMap = %{$borrowingMap{$owningLib}};
                            $thisMap{@borrowingLibs[$colNum]} = $_->get_text();
                            $borrowingMap{$owningLib} = \%thisMap;
                        }
                    }
                    $colNum++;
                }
            }
            $rowNum++;
            last if $rowNum > 10;
        }
        
        # Spidered the table - now saving it to storage
        $randomHash = generateRandomString($self,12);
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
        $log->addLine($query);
        # $log->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);
        undef $borrowingMap;
        undef $query;
        undef @vals;
        
        # now we need to create a branch for any potiential new branches/institutions
        
        my $query = "INSERT INTO $self->{prefix}"."_branch
        (cluster,institution,shortname)
        SELECT DISTINCT cluster.id,concat('unknown_',trim(bnl_stage.owning_lib)),trim(bnl_stage.owning_lib)
        FROM
        $self->{prefix}"."_bnl_stage bnl_stage,
        $self->{prefix}"."_cluster cluster
        WHERE
        bnl_stage.working_hash = ? and
        cluster.name = ? and
        concat(cluster.id,'-',trim(bnl_stage.owning_lib)) not in(
            select
            concat(cluster,'-',shortname)
            from
            $self->{prefix}"."_branch
        )";
        my @vals = ($randomHash,$self->{name});
        $log->addLine($query);
        $log->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);
        
        
        # Now with borrowing lib        
        $query = "INSERT INTO $self->{prefix}"."_branch
        (cluster,institution,shortname)
        SELECT DISTINCT cluster.id,concat('unknown_',trim(bnl_stage.borrowing_lib)),trim(bnl_stage.borrowing_lib)
        FROM
        $self->{prefix}"."_bnl_stage bnl_stage,
        $self->{prefix}"."_cluster cluster
        WHERE
        bnl_stage.working_hash = ? and
        cluster.name = ? and
        concat(cluster.id,'-',trim(bnl_stage.borrowing_lib)) not in(
            select
            concat(cluster,'-',shortname)
            from
            $self->{prefix}"."_branch
        )";
        @vals = ($randomHash,$self->{name});
        $log->addLine($query);
        $log->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);
        
        # Now that the branches exist and have an ID number, we can migrate from the staging table into production
        ## Delete any conflicting rows
        $query = "
        DELETE 
        bnl_conflict
        FROM
        $self->{prefix}"."_bnl bnl_conflict,
        (
        SELECT
        CONCAT(
        cluster.id,'-',
        owning_branch_table.id,'-',
        cluster.id,'-',
        borrowing_branch_table.id,'-',
        bnl_stage.borrow_date
        ) as \"together\"
        FROM
        $self->{prefix}"."_bnl_stage bnl_stage,
        $self->{prefix}"."_branch owning_branch_table,
        $self->{prefix}"."_branch borrowing_branch_table,
        $self->{prefix}"."_cluster cluster
        WHERE
        bnl_stage.working_hash = ? and
        cluster.name = ? and
        owning_branch_table.shortname = bnl_stage.owning_lib and
        owning_branch_table.cluster = cluster.id and
        borrowing_branch_table.shortname = bnl_stage.borrowing_lib and
        borrowing_branch_table.cluster = cluster.id
        ) as thejoiner
        WHERE
        CONCAT(
        bnl_conflict.owning_cluster,'-',
        bnl_conflict.owning_branch,'-',
        bnl_conflict.borrowing_cluster,'-',
        bnl_conflict.borrowing_branch, '-',
        borrow_date
        ) 
        =  thejoiner.together
        ";
        $log->addLine($query);
        $log->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);
        
        
        ## Make the final insert
        $query = "
        INSERT INTO $self->{prefix}"."_bnl
        (owning_cluster,owning_branch,borrowing_cluster,borrowing_branch,quantity,borrow_date)
        SELECT 
        DISTINCT
        cluster.id,
        owning_branch_table.id,
        cluster.id,
        borrowing_branch_table.id,
        bnl_stage.quantity,
        bnl_stage.borrow_date
        FROM
        $self->{prefix}"."_bnl_stage bnl_stage,
        $self->{prefix}"."_branch owning_branch_table,
        $self->{prefix}"."_branch borrowing_branch_table,
        $self->{prefix}"."_cluster cluster
        WHERE
        bnl_stage.working_hash = ? and
        cluster.name = ? and
        owning_branch_table.shortname = bnl_stage.owning_lib and
        owning_branch_table.cluster = cluster.id and
        borrowing_branch_table.shortname = bnl_stage.borrowing_lib and
        borrowing_branch_table.cluster = cluster.id
        ";
        $log->addLine($query);
        $log->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);

        ## And clear out our staging table
        $query = "
        DELETE FROM $self->{prefix}"."_bnl_stage
        WHERE
        working_hash = ?
        ";
        $log->addLine($query);
        @vals = ($randomHash);
        $log->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);
    }
    else
    {
        return 0;
    }
}

sub handleReportSelection
{
    my ($self) = @_[0];
    my $selection = @_[1];
print "handleReportSelection\n";
    my @frameSearchElements = ('TOTAL circulation', 'Choose a STARTING and ENDING month');
        
    if(!switchToFrame($self,\@frameSearchElements))
    {   
        my $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('td');
            var stop = 0;
            for(var i=0;i<doms.length;i++)
            {
                if(!stop)
                {
                    var thisaction = doms[i].innerHTML;

                    if(thisaction.match(/".$selection."/gi))
                    {
                        doms[i].getElementsByTagName('input')[0].click();
                        stop = 1;
                    }
                }
            }
            if(!stop)
            {
                return 'didnt find the button';
            }

            ");
        sleep 1;
        $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('form');
            for(var i=0;i<doms.length;i++)
            {
                doms[i].submit();
            }
        ");
        sleep 1;
        $driver->switch_to_frame();
        my $finished = handleReportSelection_processing_waiting($self);
        takeScreenShot($self,'handleReportSelection');
        return $finished;
    }
    else
    {
        return 0;
    }
}

sub handleReportSelection_processing_waiting
{
    my ($self) = @_[0];
    my $count = @_[1] || 0 ;
print "handleReportSelection_processing_waiting\n";
    my @frameSearchElements = ('This statistical report is calculating');
    my $error = switchToFrame($self,\@frameSearchElements);
    print "switch to frame = $error\n";
    if(!$error) ## will only exist while server is processing the request
    {
        if($count < 10) # only going to try this 10 times
        {
            my $owning = $driver->execute_script("
                var doms = document.getElementsByTagName('form');
                for(var i=0;i<doms.length;i++)
                {
                    doms[i].submit();
                }
            ");
            sleep 1;
            $driver->switch_to_frame();
            $count++;
            my $worked = handleReportSelection_processing_waiting($self,$count);
            return $worked;
        }
        else
        {
            return 0;
        }
    }
    else
    {
        return 1;
    }
}


sub handleLandingPage
{
    my ($self) = @_[0];
    print "handleLandingPage\n";
    my @frameSearchElements = ('Circ Activity', '<b>CIRCULATION<\/b>');
        
    if(!switchToFrame($self,\@frameSearchElements))
    {
        my @forms = $driver->find_elements('//form');
        foreach(@forms)
        {
            $thisForm = $_;
            if($thisForm->get_attribute("action") =~ /\/managerep\/startviews\/0\/d\/table_1x1/g )
            {
                $thisForm->submit();
            }
        }
        
        sleep 1;
        $driver->switch_to_frame();
        takeScreenShot($self,'handleLandingPage');
        return 1;
    }
    else
    {
        return 0;
    }
}

sub handleCircStatOwningHome
{
    my ($self) = shift;
    my $clickAllActivityFirst = shift|| 0;
print "handleCircStatOwningHome\n";

    my @frameSearchElements = ('Owning\/Home', 'htcircrep\/owning\/\/o\|\|\|\|\|\/');

    if($clickAllActivityFirst)
    {
        if(!switchToFrame($self,\@frameSearchElements))
        {   
            my $owning = $driver->execute_script("
                var doms = document.getElementsByTagName('a');
                var stop = 0;
                for(var i=0;i<doms.length;i++)
                {
                    if(!stop)
                    {
                        var thisaction = doms[i].getAttribute('href');

                        if(thisaction.match(/htcircrep\\/activity\\/\\/a0\\|y1\\|s\\|1\\|\\|/g))
                        {
                            doms[i].click();
                            stop = 1;
                        }
                    }
                }
                if(!stop)
                {
                    return 'didnt find the button';
                }

                ");
                sleep 1;
                $driver->switch_to_frame();
                takeScreenShot($self,'handleCircStatOwningHome_clickAllActivityFirst');
        }
    }

    
    if(!switchToFrame($self,\@frameSearchElements))
    {   
        my $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('a');
            var stop = 0;
            for(var i=0;i<doms.length;i++)
            {
                if(!stop)
                {
                    var thisaction = doms[i].getAttribute('onClick');

                    if(thisaction.match(/htcircrep\\/owning\\/\\/o\\|\\|\\|\\|\\|\\//g))
                    {
                        doms[i].click();
                        stop = 1;
                    }
                }
            }
            if(!stop)
            {
                return 'didnt find the button';
            }

            ");
        sleep 1;
        $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('form');
            for(var i=0;i<doms.length;i++)
            {
                doms[i].submit();
            }
        ");
        sleep 1;
        $driver->switch_to_frame();
        takeScreenShot($self,'handleCircStatOwningHome');
        return 1;
    }
    else
    {
        return 0;
    }
}

sub handleLoginPage
{
print "handleLoginPage\n";
    my ($self) = @_[0];
    my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
    $body =~ s/[\r\n]//g;
    # $log->addLine("Body of the HTML: " . Dumper($body));
    if( ($body =~ m/<td>Initials<\/td>/) && ($body =~ m/<td>Password<\/td>/)  )
    {
        my @forms = $driver->find_elements('//form');
        foreach(@forms)
        {
            $thisForm = $_;
            if($thisForm->get_attribute("action") =~ /\/htcircrep\/\/\-1\/\/VALIDATE/g )
            {
                my $circActivty = $driver->execute_script("
                var doms = document.getElementsByTagName('input');
                for(var i=0;i<doms.length;i++)
                {
                    var thisaction = doms[i].getAttribute('name');

                    if(thisaction.match(/NAME/g))
                    {
                        doms[i].value = '".$self->{webLogin}."';
                    }
                    if(thisaction.match(/CODE/g))
                    {
                        doms[i].value = '".$self->{webPass}."';
                    }
                }

                ");                
                $thisForm->submit();
                sleep 1;                
                takeScreenShot($self,'handleLoginPage');
            }
        }
    }
    else
    {
        print "no login page found";
    }
    return 1;  # always return true even when it doesn't prompt to login
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
            $driver->switch_to_frame($frameNum); # This can throw an error if the frame doesn't exist
            my $body = $driver->execute_script("return document.getElementsByTagName('html')[0].innerHTML");            
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
        $driver->switch_to_frame();
        $tries++;
        $error = 1 if $tries > 10;
        $hasWhatIneed = 1 if $tries > 10;
    }
    if(!$error)
    {
        # print "About to switch to a real frame: $frameNum\n";
        try
        {
            $driver->switch_to_frame($frameNum);
        }
        catch
        {
            takeScreenShot($self,"error_switching_frame");
        };
    }
    return $error;
}


#### saving this JS code incase we need to deal with the page via JS instead of webcomponent
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


sub takeScreenShot
{
    my ($self) = shift;
    my $action = shift;
    $screenShotStep++;
    $driver->capture_screenshot("$screenshotDIR/".$self->{name}."_".$screenShotStep."_".$action.".png", {'full' => 1});
}


sub figureWhichDates
{
    my ($self) = shift;
    my $monthsBack = shift || 5;
    my %alreadyScraped = ();
    
    my @months = qw( onebase Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
    my @ret = ();
    my @dbVals = ();
    
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

    $log->addLine($query);
    my @results = @{$self->{dbHandler}->query($query)};
    foreach(@results)
    {
        my @row = @{$_};
        $alreadyScraped{ @row[0] } = 1;
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
        $log->addLine($query);
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


sub DESTROY
{
    my ($self) = @_[0];

}


1;