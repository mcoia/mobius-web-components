#!/usr/bin/perl

package sierraCluster;

use pQuery;
use Try::Tiny;
use Data::Dumper;


use parent iiiServer;


sub scrape
{
    my ($self) = shift;
    my @dateScrapes = @{$self->figureWhichDates()};
    if(!$self->{error} && @dateScrapes[0])
    {
        $self->{log}->addLine("Getting " . $self->{webURL});
        $self->{driver}->get($self->{webURL});
        sleep 3; # initial page load takes time.
        $self->takeScreenShot('pageload');
        my $continue = handleLandingPage($self);
        $continue = handleLoginPage($self) if $continue;
        $continue = handleCircStatOwningHome($self) if $continue;
        my @pageVals = @{@dateScrapes[0]};
        my @dbvals = @{@dateScrapes[1]};
        my $pos = 0;
        foreach(@pageVals)
        {
            print $self->{name}." pulling ". @dbvals[$pos] ."\n";
            $continue = handleReportSelection($self,$_) if $continue;
            collectReportData($self, @dbvals[$pos]) if $continue;
            $pos++;
            $continue = handleCircStatOwningHome($self,1) if $continue;
        }
    }
}

sub collectReportData
{
    my ($self) = shift;
    my $dbDate = shift;
    my @frameSearchElements = ('HOME LIBRARY TOTAL CIRCULATION');
        
    if(!$self->switchToFrame(\@frameSearchElements))
    {
        my $randomHash = $self->SUPER::collectReportData($dbDate);

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
    
    my $worked = 0;
    if( !$self->{postgresConnector})
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
    $count = 0;
    my @frameSearchElements = ('This statistical report is calculating');
    while($count < 10)
    {
        my $error = $self->switchToFrame(\@frameSearchElements);
        if(!$error) ## will only exist while server is processing the request
        {
            print "Having to wait for server to process: $count\n";
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
        }
        else
        {
            return 1;
        }
    }
    return 0;
}

sub handleLandingPage
{
    my ($self) = @_[0];
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