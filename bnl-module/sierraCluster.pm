#!/usr/bin/perl

package sierraCluster;

use pQuery;
use Try::Tiny;
use Data::Dumper;


use parent iiiServer;


sub scrape
{
    my ($self) = shift;
    my $monthsBack = shift || 5;

    my @dateScrapes = @{$self->figureWhichDates()};
    
    if(!$self->{error})
    {
        $self->{log}->addLine("Getting " . $self->{webURL});
        $self->{driver}->get($self->{webURL});
        sleep 3; # initial page load takes time.
        $self->takeScreenShot('pageload');
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
        
    if(!$self->switchToFrame(\@frameSearchElements))
    {
        my $randomHash = $self->SUPER::collectReportData($dbDate);
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
        $self->{log}->addLine($query);
        $self->{log}->addLine(Dumper(\@vals));
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
        $self->{log}->addLine($query);
        $self->{log}->addLine(Dumper(\@vals));
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
        $self->{log}->addLine($query);
        $self->{log}->addLine(Dumper(\@vals));
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
        $self->{log}->addLine($query);
        $self->{log}->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);

        ## And clear out our staging table
        $query = "
        DELETE FROM $self->{prefix}"."_bnl_stage
        WHERE
        working_hash = ?
        ";
        $self->{log}->addLine($query);
        @vals = ($randomHash);
        $self->{log}->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);

        ## Attempt to correct any unknown branches
        translateShortCodes($self);
    }
    else
    {
        return 0;
    }
}

sub translateShortCodes
{
    my ($self) = shift;
    
    my $worked = 1;
    
    # make sure we even need to bother
    my $query = "
    select * from
    $self->{prefix}"."_branch
    where
    institution like 'unknown_%' limit 1";
    $self->{log}->addLine($query);
    my @results = @{$self->{dbHandler}->query($query)};
    $worked  = 0 if($#results < 0);
    if( (!$self->{postgresConnector}) && $worked )
    {
        try
        {
            $self->{log}->addLine("Making new DB connection to pg");
            $self->{postgresConnector} = new DBhandler($self->{pgDB},$self->{pgURL},$self->{pgUser},$self->{pgPass},$self->{pgPort},"pg");
            $worked = 1 if($self->{postgresConnector}->getQuote(""));
        }
        catch
        {
            ## Couldn't connect
        };
    }
    else
    {
        $worked = 1;
    }
    if($worked)
    {
        my $randomHash = $self->generateRandomString(12);
        my $query = 
        "
        select svb.code_num,svl.code,svbn.name,svbn.branch_id 
        from
        sierra_view.location svl,
        sierra_view.branch svb,
        sierra_view.branch_name svbn
        where
        svbn.branch_id=svb.id and
        svb.code_num=svl.branch_code_num
        ";
        
        $self->{log}->addLine("Connection to PG:\n$query");
        my @results = @{$self->{postgresConnector}->query($query)};

        ## re-using an already existing table to stage our results into.
        $query = "INSERT INTO 
        $self->{prefix}"."_bnl_stage
        (working_hash,owning_lib,borrowing_lib)
        values
        ";
        my @vals = ();
        foreach(@results)
        {
            my @row = @{$_};
            $query .= "( ?, ? , ? ),\n";
            push @vals, ($randomHash, $self->trim(@row[1]), $self->trim(@row[2]));
        }
        $query = substr($query,0,-2);
        $self->{log}->addLine($query);
        $self->{log}->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);
        
        $query = "
        UPDATE 
        $self->{prefix}"."_branch branch,
        $self->{prefix}"."_bnl_stage bnl_stage,
        $self->{prefix}"."_cluster cluster
        set
        branch.institution = bnl_stage.borrowing_lib
        WHERE
        cluster.id = branch.cluster and
        bnl_stage.owning_lib = branch.shortname and
        cluster.name = ? and
        bnl_stage.working_hash = ?";
        @vals = ($self->{name}, $randomHash);
        $self->{log}->addLine($query);
        $self->{log}->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);

        ## And clear out our staging table
        $query = "
        DELETE FROM $self->{prefix}"."_bnl_stage
        WHERE
        working_hash = ?
        ";
        $self->{log}->addLine($query);
        @vals = ($randomHash);
        $self->{log}->addLine(Dumper(\@vals));
        $self->{dbHandler}->updateWithParameters($query,\@vals);
        undef @vals;
    }
}

sub handleReportSelection
{
    my ($self) = @_[0];
    my $selection = @_[1];
print "handleReportSelection\n";
    my @frameSearchElements = ('TOTAL circulation', 'Choose a STARTING and ENDING month');
        
    if(!$self->switchToFrame(\@frameSearchElements))
    {   
        my $owning = $self->{driver}->execute_script("
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
        $owning = $self->{driver}->execute_script("
            var doms = document.getElementsByTagName('form');
            for(var i=0;i<doms.length;i++)
            {
                doms[i].submit();
            }
        ");
        sleep 1;
        $self->{driver}->switch_to_frame();
        my $finished = handleReportSelection_processing_waiting($self);
        $self->takeScreenShot('handleReportSelection');
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
    my $error = $self->switchToFrame(\@frameSearchElements);
    print "switch to frame = $error\n";
    if(!$error) ## will only exist while server is processing the request
    {
        if($count < 10) # only going to try this 10 times
        {
            my $owning = $self->{driver}->execute_script("
                var doms = document.getElementsByTagName('form');
                for(var i=0;i<doms.length;i++)
                {
                    doms[i].submit();
                }
            ");
            sleep 1;
            $self->{driver}->switch_to_frame();
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
        
    if(!$self->switchToFrame(\@frameSearchElements))
    {
        my @forms = $self->{driver}->find_elements('//form');
        foreach(@forms)
        {
            $thisForm = $_;
            if($thisForm->get_attribute("action") =~ /\/managerep\/startviews\/0\/d\/table_1x1/g )
            {
                $thisForm->submit();
            }
        }
        
        sleep 1;
        $self->{driver}->switch_to_frame();
        $self->takeScreenShot('handleLandingPage');
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
        if(!$self->switchToFrame(\@frameSearchElements))
        {   
            my $owning = $self->{driver}->execute_script("
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
                $self->{driver}->switch_to_frame();
                $self->takeScreenShot('handleCircStatOwningHome_clickAllActivityFirst');
        }
    }

    
    if(!$self->switchToFrame(\@frameSearchElements))
    {   
        my $owning = $self->{driver}->execute_script("
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
        $owning = $self->{driver}->execute_script("
            var doms = document.getElementsByTagName('form');
            for(var i=0;i<doms.length;i++)
            {
                doms[i].submit();
            }
        ");
        sleep 1;
        $self->{driver}->switch_to_frame();
        $self->takeScreenShot('handleCircStatOwningHome');
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
    my $body = $self->{driver}->execute_script("return document.getElementsByTagName('html')[0].innerHTML");
    $body =~ s/[\r\n]//g;
    # $self->{log}->addLine("Body of the HTML: " . Dumper($body));
    if( ($body =~ m/<td>Initials<\/td>/) && ($body =~ m/<td>Password<\/td>/)  )
    {
        my @forms = $self->{driver}->find_elements('//form');
        foreach(@forms)
        {
            $thisForm = $_;
            if($thisForm->get_attribute("action") =~ /\/htcircrep\/\/\-1\/\/VALIDATE/g )
            {
                my $circActivty = $self->{driver}->execute_script("
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
                $self->takeScreenShot('handleLoginPage');
            }
        }
    }
    else
    {
        print "no login page found";
    }
    return 1;  # always return true even when it doesn't prompt to login
}



1;