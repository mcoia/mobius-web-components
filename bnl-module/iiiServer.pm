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
        debug => shift,
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
        # $self->{log}->addLine("after: ".Dumper($self));
    }
    else
    {
        $self->{error} = 1;
    }
    $screenShotStep = 0;
    bless $self, $class;
    return $self;
}

sub collectReportData
{
    my ($self) = shift;
    my $dbDate = shift;
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
    $self->{log}->addLine("Got this: $owning") if $self->{debug};
    my $rowNum = 0;
    pQuery("tr",$owning)->each(sub {
        if($rowNum > 0) ## Skipping the title row  -- ad this to get a smaller sample of data  && $rowNum < 10
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
                    elsif ( length(@borrowingLibs[$colNum]) > 0  && (pQuery($_)->text() ne '0') )
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
    doUpdateQuery($self,$query,"INSERTING $self->{prefix}"."_bnl_stage",\@vals);
    
    # now we need to create a branch for any potiential new branches/institutions
    my $query = "INSERT INTO $self->{prefix}"."_branch
    (cluster,institution,shortname)
    SELECT DISTINCT cluster.id,trim(bnl_stage.owning_lib),trim(bnl_stage.owning_lib)
    FROM
    $self->{prefix}"."_bnl_stage bnl_stage,
    $self->{prefix}"."_cluster cluster
    WHERE
    bnl_stage.working_hash = ? and
    cluster.name = ? and
    LOWER(concat(cluster.id,'-',trim(bnl_stage.owning_lib))) not in(
        select
        LOWER(concat(cluster,'-',shortname))
        from
        $self->{prefix}"."_branch
    ) and
    length(trim(bnl_stage.owning_lib)) > 0 and
    lower(trim(bnl_stage.owning_lib)) not in (select lower(trim(name)) from  $self->{prefix}"."_ignore_name)
    ";
    $query .= "AND lower(trim(bnl_stage.owning_lib)) not in (select lower(trim(shortname)) from  $self->{prefix}"."_branch_shortname_agency_translate)" if (ref $self eq 'innreachServer');
    @vals = ($randomHash,$self->{name});
    doUpdateQuery($self,$query,"INSERTING owning $self->{prefix}"."_branch",\@vals);

    # Now with borrowing lib        
    $query = "INSERT INTO $self->{prefix}"."_branch
    (cluster,institution,shortname)
    SELECT DISTINCT cluster.id,trim(bnl_stage.borrowing_lib),trim(bnl_stage.borrowing_lib)
    FROM
    $self->{prefix}"."_bnl_stage bnl_stage,
    $self->{prefix}"."_cluster cluster
    WHERE
    bnl_stage.working_hash = ? and
    cluster.name = ? and
    LOWER(concat(cluster.id,'-',trim(bnl_stage.borrowing_lib))) not in(
        select
        LOWER(concat(cluster,'-',shortname))
        from
        $self->{prefix}"."_branch
    ) and
    length(trim(bnl_stage.borrowing_lib)) > 0 and
    lower(trim(bnl_stage.borrowing_lib)) not in (select lower(trim(name)) from  $self->{prefix}"."_ignore_name)
    ";
    $query .= "AND lower(trim(bnl_stage.borrowing_lib)) not in (select lower(trim(shortname)) from  $self->{prefix}"."_branch_shortname_agency_translate)" if (ref $self eq 'innreachServer');
    doUpdateQuery($self,$query,"INSERTING borrowing $self->{prefix}"."_branch",\@vals);
    
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
    LOWER(owning_branch_table.shortname) = LOWER(bnl_stage.owning_lib) and
    owning_branch_table.cluster = cluster.id and
    LOWER(borrowing_branch_table.shortname) = LOWER(bnl_stage.borrowing_lib) and
    borrowing_branch_table.cluster = cluster.id
    ) as thejoiner
    WHERE
    bnl_conflict.match_key = thejoiner.together
    ";
    doUpdateQuery($self,$query,"DELETE conflict $self->{prefix}"."_bnl",\@vals);

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
    LOWER(owning_branch_table.shortname) = LOWER(bnl_stage.owning_lib) and
    owning_branch_table.cluster = cluster.id and
    LOWER(borrowing_branch_table.shortname) = LOWER(bnl_stage.borrowing_lib) and
    borrowing_branch_table.cluster = cluster.id
    ";
    doUpdateQuery($self,$query,"INSERTING $self->{prefix}"."_bnl",\@vals);

    ## And clear out our staging table
    $query = "
    DELETE FROM $self->{prefix}"."_bnl_stage
    WHERE
    working_hash = ?
    OR
    insert_time < SUBDATE(now(), INTERVAL 1 week)
    ";
    @vals = ($randomHash);
    doUpdateQuery($self,$query,"Cleaning Staging $self->{prefix}"."_bnl_stage",\@vals);
    
    undef $borrowingMap;
    undef $query;
    undef @vals;
    return $randomHash;
}

sub normalizeNames
{
    my ($self) = shift;
    my @vals = ();

    my $query = "
    INSERT INTO ".$self->{prefix}."_normalize_branch_name
    (variation,normalized)
    SELECT DISTINCT
    mbnd.variation,mmbnbn.normalized
    FROM
    ".$self->{prefix}."_branch_name_dedupe mbnd,
    ".$self->{prefix}."_normalize_branch_name mmbnbn
    WHERE
    mmbnbn.normalized = mbnd.normalized AND
    lower(mbnd.variation) not in(SELECT lower(variation) FROM ".$self->{prefix}."_normalize_branch_name )
    ";
    doUpdateQuery($self,$query,"NORMALIZING INSERT INTO $self->{prefix}"."_branch_name_final",\@vals);

    $query = "
    INSERT INTO ".$self->{prefix}."_normalize_branch_name
    (variation,normalized)
    SELECT DISTINCT
    mbnd.variation,mbnd.normalized
    FROM
    ".$self->{prefix}."_branch_name_dedupe mbnd
    WHERE
    lower(mbnd.variation) not in(SELECT lower(variation) FROM ".$self->{prefix}."_normalize_branch_name )
    ";
    doUpdateQuery($self,$query,"NORMALIZING INSERT INTO $self->{prefix}"."_branch_name_final",\@vals);

    $query = "
     INSERT INTO ".$self->{prefix}."_normalize_branch_name
    (variation,normalized)
    SELECT
    mbb.institution, mbnbn.normalized
    FROM
    ".$self->{prefix}."_branch mbb,
    ".$self->{prefix}."_normalize_branch_name mbnbn
    WHERE
    ".$self->{prefix}."_normalize_library_name(mbnbn.variation) = ".$self->{prefix}."_normalize_library_name(mbb.institution) AND
    mbb.institution != mbnbn.normalized AND
    lower(mbnbn.variation) != lower(mbb.institution) AND
    lower(mbb.institution) not in(select lower(variation) from ".$self->{prefix}."_normalize_branch_name)
    group by 1,2
    ";
    doUpdateQuery($self,$query,"NORMALIZING INSERT INTO $self->{prefix}"."_branch_name_final",\@vals);

    $query = "
    INSERT INTO ".$self->{prefix}."_branch_name_final
    (name)
    SELECT DISTINCT
    nbn.normalized    
    FROM
    ".$self->{prefix}."_normalize_branch_name nbn,
    ".$self->{prefix}."_branch b
    WHERE
    lower(nbn.variation) = lower(b.institution) AND
    nbn.normalized not in(SELECT name FROM ".$self->{prefix}."_branch_name_final )
    ";
    doUpdateQuery($self,$query,"NORMALIZING INSERT INTO $self->{prefix}"."_branch_name_final",\@vals);

    $query = "
    INSERT INTO ".$self->{prefix}."_branch_name_final
    (name)
    SELECT DISTINCT
    b.institution
    FROM
    ".$self->{prefix}."_branch b
    WHERE
    lower(b.institution) not in (SELECT lower(variation) FROM ".$self->{prefix}."_normalize_branch_name) AND
    b.institution not in(SELECT name FROM ".$self->{prefix}."_branch_name_final )
    ";
    doUpdateQuery($self,$query,"NORMALIZING INSERT INTO $self->{prefix}"."_branch_name_final",\@vals);

    $query = "
    UPDATE 
    ".$self->{prefix}."_branch branch,
    ".$self->{prefix}."_branch_name_final bnf,
    ".$self->{prefix}."_normalize_branch_name nbn
    SET
    branch.final_branch = bnf.id
    WHERE
    lower(nbn.variation) = lower(branch.institution) AND
    bnf.name = nbn.normalized
    ";
    doUpdateQuery($self,$query,"UPDATING BRANCH TO FINAL ID through normalization $self->{prefix}"."_branch_name_final",\@vals);

    $query = "
    UPDATE 
    ".$self->{prefix}."_branch branch,
    ".$self->{prefix}."_branch_name_final bnf
    SET
    branch.final_branch = bnf.id
    WHERE
    branch.institution = bnf.name AND
    lower(branch.institution) NOT IN (SELECT lower(variation) FROM ".$self->{prefix}."_normalize_branch_name) AND
    (branch.final_branch != bnf.id OR branch.final_branch IS NULL)
    ";
    doUpdateQuery($self,$query,"UPDATING BRANCH TO FINAL ID without normalization $self->{prefix}"."_branch_name_final",\@vals);

    $query = "
    DELETE bnf FROM 
    ".$self->{prefix}."_branch_name_final bnf,
    ".$self->{prefix}."_normalize_branch_name nbn
    WHERE
    lower(bnf.name) = lower(nbn.variation)
    ";
    doUpdateQuery($self,$query,"DELETING FINAL BRANCHES THAT EXIST IN normalization $self->{prefix}"."_branch_name_final",\@vals);
}

sub cleanDuplicates
{
    my ($self) = shift;
    my @vals = ();

    ## Delete innreach duplicates
    my $query = "
    delete bnl FROM
    $self->{prefix}"."_bnl bnl,
    $self->{prefix}"."_branch owning_branch,
    $self->{prefix}"."_branch borrowing_branch,
    $self->{prefix}"."_cluster owning_cluster,
    $self->{prefix}"."_cluster borrowing_cluster,
    (
    select
    sierra.owning_id,sierra.borrowing_id,sierra.borrow_date,sierra.quantity
    from
    $self->{prefix}"."_bnl_final_branch_map sierra,
    $self->{prefix}"."_bnl_final_branch_map innreach
    where
    sierra.cluster_type = 'sierra' and
    innreach.cluster_type = 'innreach' and
    sierra.owning_id=innreach.owning_id and
    sierra.borrowing_id=innreach.borrowing_id AND
    sierra.borrow_date=innreach.borrow_date AND
    sierra.quantity=innreach.quantity
        ) as alll
    WHERE
    bnl.owning_branch = owning_branch.id and
    bnl.borrowing_branch = borrowing_branch.id AND
    bnl.owning_cluster = owning_cluster.id AND
    bnl.borrowing_cluster = borrowing_cluster.id AND
    alll.owning_id = owning_branch.final_branch and
    alll.borrowing_id = borrowing_branch.final_branch and
    owning_cluster.type = 'innreach' and
    borrowing_cluster.type = 'innreach' and
    bnl.borrow_date = alll.borrow_date and
    bnl.quantity = alll.quantity
    ";
    doUpdateQuery($self,$query,"DELETE duplicate INNREACH $self->{prefix}"."_bnl",\@vals);

    ## Delete sierra->sierra duplicates (because of agency)
    $query = "
    delete bnl1
    from
    $self->{prefix}"."_bnl bnl1,
    $self->{prefix}"."_bnl bnl2,
    $self->{prefix}"."_branch owning_branch1,
    $self->{prefix}"."_branch borrowing_branch1,
    $self->{prefix}"."_branch owning_branch2,
    $self->{prefix}"."_branch borrowing_branch2,
    $self->{prefix}"."_bnl_final_branch_map as group1,
    $self->{prefix}"."_bnl_final_branch_map as group2
    WHERE
    group1.cluster_type = 'sierra' and
    group2.cluster_type = 'sierra' and
    group1.owning_id=group2.owning_id and
    group1.borrowing_id=group2.borrowing_id AND
    group1.borrow_date=group2.borrow_date AND
    group1.quantity=group2.quantity AND
    bnl1.owning_branch = owning_branch1.id and
    bnl1.borrowing_branch = borrowing_branch1.id and
    bnl2.owning_branch = owning_branch2.id and
    bnl2.borrowing_branch = borrowing_branch2.id and
    bnl1.owning_branch != bnl2.owning_branch AND
    owning_branch1.final_branch = group1.owning_id and
    borrowing_branch1.final_branch = group1.borrowing_id and
    owning_branch2.final_branch = group2.owning_id and
    borrowing_branch2.final_branch = group2.borrowing_id and
    bnl1.borrow_date = bnl2.borrow_date AND
    bnl1.quantity = bnl2.quantity AND
    bnl1.owning_cluster != bnl2.owning_cluster AND
    owning_branch1.shortname in(select shortname from $self->{prefix}"."_branch_shortname_agency_translate)
    ";
    doUpdateQuery($self,$query,"DELETE duplicate sierra1->sierra2 duplicates (because of agency) $self->{prefix}"."_bnl",\@vals);

    ## Delete sierra->sierra duplicates (because of agency)
    $query = "
    delete bnl2
    from
    $self->{prefix}"."_bnl bnl1,
    $self->{prefix}"."_bnl bnl2,
    $self->{prefix}"."_branch owning_branch1,
    $self->{prefix}"."_branch borrowing_branch1,
    $self->{prefix}"."_branch owning_branch2,
    $self->{prefix}"."_branch borrowing_branch2,
    $self->{prefix}"."_bnl_final_branch_map as group1,
    $self->{prefix}"."_bnl_final_branch_map as group2
    WHERE
    group1.cluster_type = 'sierra' and
    group2.cluster_type = 'sierra' and
    group1.owning_id=group2.owning_id and
    group1.borrowing_id=group2.borrowing_id AND
    group1.borrow_date=group2.borrow_date AND
    group1.quantity=group2.quantity AND
    bnl1.owning_branch = owning_branch1.id and
    bnl1.borrowing_branch = borrowing_branch1.id and
    bnl2.owning_branch = owning_branch2.id and
    bnl2.borrowing_branch = borrowing_branch2.id and
    bnl1.owning_branch != bnl2.owning_branch AND
    owning_branch1.final_branch = group1.owning_id and
    borrowing_branch1.final_branch = group1.borrowing_id and
    owning_branch2.final_branch = group2.owning_id and
    borrowing_branch2.final_branch = group2.borrowing_id and
    bnl1.borrow_date = bnl2.borrow_date AND
    bnl1.quantity = bnl2.quantity AND
    bnl1.owning_cluster != bnl2.owning_cluster AND
    owning_branch2.shortname in(select shortname from $self->{prefix}"."_branch_shortname_agency_translate)

    ";
    doUpdateQuery($self,$query,"DELETE duplicate sierra2->sierra1 duplicates (because of agency) $self->{prefix}"."_bnl",\@vals);

}


sub doUpdateQuery
{
    my $self = shift;
    my $query = shift;
    my $stdout = shift;
    my $dbvars = shift;

    $self->{log}->addLine($query);
    $self->{log}->addLine(Dumper($dbvars)) if $self->{debug};
    print "$stdout\n";

    $self->{dbHandler}->updateWithParameters($query, $dbvars);
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
    my $monthsBack = $self->{monthsBack} || 5;
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
    # $self->{log}->addLine("screenshot self: ".Dumper($self));
    # print "ScreenShot: ".$self->{screenshotDIR}."/".$self->{name}."_".$screenShotStep."_".$action.".png\n";
    $self->{driver}->capture_screenshot($self->{screenshotDIR}."/".$self->{name}."_".$screenShotStep."_".$action.".png", {'full' => 1});
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