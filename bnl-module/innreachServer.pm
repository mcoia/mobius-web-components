#!/usr/bin/perl

package innreachServer;

use parent iiiServer;


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
        
        my $owning = $driver->execute_script("
            var doms = document.getElementsByTagName('table');
            var stop = 0;
            for(var i=0;i<doms.length;i++)
            {
                return doms[i].innerHTML;
            }
            ");
        $log->addLine("Got this: $owning");
        my $rowNum = 0;
        pQuery("tr",$owning)->each(sub {
            if($rowNum > 0) ## Skipping the title row
            {
                my $i = shift;
                my $row = $_;
                my $colNum = 0;
                my $owningLib = '';
                print "Parsing row $rowNum\n";
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
    $log->addLine($query);
    my @results = @{$self->{dbHandler}->query($query)};
    $worked  = 0 if($#results < 0);
    if( (!$self->{postgresConnector}) && $worked )
    {
        try
        {
            $log->addLine("Making new DB connection to pg");
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
        my $randomHash = generateRandomString($self,12);
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
        
        $log->addLine("Connection to PG:\n$query");
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
            push @vals, ($randomHash, trim(@row[1]), trim(@row[2]));
        }
        $query = substr($query,0,-2);
        $log->addLine($query);
        $log->addLine(Dumper(\@vals));
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
        undef @vals;
    }
}


1;