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
        postgresConnector => undef,
        specificMonth => shift
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

sub setSpecificDate
{
    my ($self) = shift;
    my $dbDate = shift;
    if($dbDate =~ m/\d{4}\-\d{1,2}\-\d{1,2}/)
    {
        $self->{specificMonth} = $dbDate;
    }
    else
    {
        $self->{specificMonth} = undef;
    }
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

    ## Create the matchkey on staging table
    $query = "
    UPDATE
    $self->{prefix}"."_bnl_stage bnl_stage,
    $self->{prefix}"."_branch owning_branch_table,
    $self->{prefix}"."_branch borrowing_branch_table,
    $self->{prefix}"."_cluster cluster
    SET
    bnl_stage.match_key = 
    CONCAT(
    cluster.id,'-',
    owning_branch_table.id,'-',
    cluster.id,'-',
    borrowing_branch_table.id,'-',
    bnl_stage.borrow_date
    )
    WHERE
    bnl_stage.working_hash = ? and
    cluster.name = ? and
    LOWER(owning_branch_table.shortname) = LOWER(bnl_stage.owning_lib) and
    owning_branch_table.cluster = cluster.id and
    LOWER(borrowing_branch_table.shortname) = LOWER(bnl_stage.borrowing_lib) and
    borrowing_branch_table.cluster = cluster.id
    ";
    doUpdateQuery($self,$query,"CREATE MATCHKEY ON $self->{prefix}"."_bnl_stage",\@vals);

    ## Delete any conflicting rows
    $query = "
    DELETE 
    bnl_conflict
    FROM
    $self->{prefix}"."_bnl bnl_conflict,    
    $self->{prefix}"."_bnl_stage bnl_stage
    WHERE
    bnl_stage.working_hash = ? and
    bnl_conflict.match_key = bnl_stage.match_key
    ";
    @vals = ($randomHash);
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
    @vals = ($randomHash,$self->{name});
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
    UPDATE ".
    $self->{prefix}."_branch branch,".
    $self->{prefix}."_shortname_override bso
    SET
    branch.institution = bso.institution
    WHERE
    branch.shortname = bso.shortname
    ";
    doUpdateQuery($self,$query,"APPLING SHORTNAME_OVERRIDE $self->{prefix}"."_branch",\@vals);

    $query = "
    INSERT INTO ".$self->{prefix}."_normalize_branch_name
    (variation,normalized)
    SELECT DISTINCT
    mbnd.variation,mmbnbn.normalized
    FROM
    ".$self->{prefix}."_branch_name_dedupe mbnd,
    ".$self->{prefix}."_normalize_branch_name mmbnbn
    WHERE
    mmbnbn.normalized = mbnd.normalized AND
    lower(mbnd.variation) not in(SELECT lower(variation) FROM ".$self->{prefix}."_normalize_branch_name ) AND
    lower(mbnd.variation) not in(SELECT lower(normalized) FROM ".$self->{prefix}."_normalize_branch_name )
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
    lower(mbnd.variation) not in(SELECT lower(variation) FROM ".$self->{prefix}."_normalize_branch_name ) AND
    lower(mbnd.variation) not in(SELECT lower(normalized) FROM ".$self->{prefix}."_normalize_branch_name )
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
    lower(mbb.institution) not in(select lower(variation) from ".$self->{prefix}."_normalize_branch_name) AND
    lower(mbb.institution) not in(SELECT lower(normalized) FROM ".$self->{prefix}."_normalize_branch_name )
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
    ".$self->{prefix}."_branch_name_final bnf,
    ".$self->{prefix}."_normalize_branch_name nbn
    SET
    branch.final_branch = bnf.id
    WHERE
    lower(nbn.variation) = lower(branch.institution_normal) AND
    bnf.name = nbn.normalized AND
    (branch.final_branch != bnf.id or branch.final_branch IS NULL)
    ";
    doUpdateQuery($self,$query,"UPDATING BRANCH TO FINAL ID through branch.institution_normal = variation normalization $self->{prefix}"."_branch_name_final",\@vals);

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
    lower(bnf.name) = lower(nbn.variation) AND
    bnf.id NOT IN(SELECT final_branch FROM ".$self->{prefix}."_branch)
    ";
    doUpdateQuery($self,$query,"DELETING FINAL BRANCHES THAT EXIST IN normalization $self->{prefix}"."_branch_name_final",\@vals);
    
    $query = "
    DELETE bnf FROM 
    ".$self->{prefix}."_branch_name_final bnf
    LEFT JOIN ".$self->{prefix}."_branch branch on (branch.final_branch = bnf.id)
    WHERE
    branch.id is null
    ";
    doUpdateQuery($self,$query,"DELETING FINAL BRANCHES THAT NO LONGER ARE REFERENCED IN BRANCH $self->{prefix}"."_branch_name_final",\@vals);
}

sub cleanDuplicates
{
    my ($self) = shift;
    my $dates = shift;
    my @dates = @{$dates} if $dates;
    
    my @vals = ();

    
    ## Delete 6/9 -> 6/9
    my $query = "
    DELETE bnl
    FROM
    $self->{prefix}"."_bnl bnl,
    $self->{prefix}"."_branch owning_branch,
    $self->{prefix}"."_branch borrowing_branch,
    $self->{prefix}"."_branch_shortname_agency_translate owning_sixcodes,
    $self->{prefix}"."_branch_shortname_agency_translate borrowing_sixcodes
    where
    owning_branch.id=bnl.owning_branch and
    borrowing_branch.id=bnl.borrowing_branch and
    owning_sixcodes.shortname=owning_branch.shortname and
    borrowing_sixcodes.shortname=borrowing_branch.shortname
    ";
    doUpdateQuery($self,$query,"DELETE 6/9 onto itself $self->{prefix}"."_bnl",\@vals);

    ## Delete 6/9 bnl data where cluster_a -> cluster_a (borrowing)
    my $query = "
    DELETE bnl
    FROM
    $self->{prefix}"."_bnl bnl,
    $self->{prefix}"."_branch owning_branch,
    $self->{prefix}"."_branch borrowing_branch,
    $self->{prefix}"."_agency_owning_cluster agency
    where
    bnl.owning_branch = owning_branch.id and
    bnl.borrowing_branch = borrowing_branch.id and
    agency.cid=bnl.borrowing_cluster and
    borrowing_branch.shortname=agency.shortname and
    owning_branch.shortname not in(SELECT shortname FROM $self->{prefix}"."_branch_shortname_agency_translate)
    ";
    doUpdateQuery($self,$query,"DELETE 6/9 onto itself (borrowing) $self->{prefix}"."_bnl",\@vals);

    ## Delete 6/9 bnl data where cluster_a -> cluster_a (owning)
    my $query = "
    DELETE bnl
    FROM
    $self->{prefix}"."_bnl bnl,
    $self->{prefix}"."_branch owning_branch,
    $self->{prefix}"."_branch borrowing_branch,
    $self->{prefix}"."_agency_owning_cluster agency
    where
    bnl.owning_branch = owning_branch.id and
    bnl.borrowing_branch = borrowing_branch.id and
    agency.cid=bnl.owning_cluster and
    owning_branch.shortname=agency.shortname and
    borrowing_branch.shortname not in(SELECT shortname FROM $self->{prefix}"."_branch_shortname_agency_translate)
    ";
    doUpdateQuery($self,$query,"DELETE 6/9 onto itself (owning) $self->{prefix}"."_bnl",\@vals);

     ## Delete entries that are already accounted for in the sierra entries
     my $queryTemplate = "
    DELETE bnl FROM
        $self->{prefix}"."_bnl bnl,
        (
            select DISTINCT * from
                (
                    select 
                    bnl_cluster1.id AS \"bnl_cluster1_id\",
                    owning_final_branch.id AS \"cluster1_owning_id\",
                    borrowing_final_branch.id \"cluster1_borrowing_id\",
                    owning_final_branch.name \"cluster1_owning_name\",
                    borrowing_final_branch.name \"cluster1_borrowing_name\",
                    cluster.name \"cluster1_cluster_name\",
                    bnl_cluster1.borrow_date as \"cluster1_borrow_date\",
                    bnl_cluster1.quantity AS \"cluster1_quantity\"
                    from
                    $self->{prefix}"."_bnl bnl_cluster1,
                    $self->{prefix}"."_branch owning_branch,
                    $self->{prefix}"."_branch borrowing_branch,
                    $self->{prefix}"."_cluster cluster,
                    $self->{prefix}"."_branch_name_final owning_final_branch,
                    $self->{prefix}"."_branch_name_final borrowing_final_branch
                    WHERE
                    bnl_cluster1.owning_branch=owning_branch.id AND
                    bnl_cluster1.borrowing_branch=borrowing_branch.id AND
                    owning_branch.final_branch=owning_final_branch.id AND
                    borrowing_branch.final_branch=borrowing_final_branch.id AND
                    cluster.id=bnl_cluster1.owning_cluster AND
                    bnl_cluster1.borrow_date = STR_TO_DATE(?, '%Y-%m-%d') AND
                    cluster.id = ?
                ) AS cluster1,
                (
                    SELECT
                    bnl_cluster2.id AS \"bnl_cluster2_id\",
                    owning_final_branch.id AS \"cluster2_owning_id\",
                    borrowing_final_branch.id \"cluster2_borrowing_id\",
                    owning_final_branch.name \"cluster2_owning_name\",
                    borrowing_final_branch.name \"cluster2_borrowing_name\",
                    cluster.name \"cluster2_cluster_name\",
                    bnl_cluster2.borrow_date as \"cluster2_borrow_date\",
                    bnl_cluster2.quantity as \"cluster2_quantity\"
                    FROM
                    $self->{prefix}"."_bnl bnl_cluster2,
                    $self->{prefix}"."_branch owning_branch,
                    $self->{prefix}"."_branch borrowing_branch,
                    $self->{prefix}"."_cluster cluster,
                    $self->{prefix}"."_branch_name_final owning_final_branch,
                    $self->{prefix}"."_branch_name_final borrowing_final_branch
                    WHERE
                    bnl_cluster2.owning_branch=owning_branch.id AND
                    bnl_cluster2.borrowing_branch=borrowing_branch.id AND
                    owning_branch.final_branch=owning_final_branch.id AND
                    borrowing_branch.final_branch=borrowing_final_branch.id AND
                    cluster.id=bnl_cluster2.owning_cluster AND
                    bnl_cluster2.borrow_date = STR_TO_DATE(?, '%Y-%m-%d') AND
                    cluster.id = ?
                ) AS cluster2,
                $self->{prefix}"."_branch_cluster branch_cluster
                WHERE
                cluster2.cluster2_borrow_date=cluster1.cluster1_borrow_date AND
                cluster2.cluster2_owning_id=cluster1.cluster1_owning_id AND
                cluster2.cluster2_borrowing_id=cluster1.cluster1_borrowing_id AND
                branch_cluster.fid=cluster1.cluster1_owning_id
       ) as alll
    WHERE
    alll.bnl_cluster2_id=bnl.id AND
    cid!=bnl.owning_cluster
     ";
    $query = "SELECT id,name FROM $self->{prefix}"."_cluster ORDER BY id";
    my @results = @{$self->{dbHandler}->query($query)};
    my @cids = ();
    my @cnames = ();
    foreach(@results)
    {
        my @row = @{$_};
        push @cids, @row[0];
        push @cnames, @row[1];
    }
    my $cluster1 = $self->{clusterID};
    my $name1 = $self->{name};

    ## Reducing the SQL load by snipering only the date ranges included in this execution
    foreach(@dates)
    {
        my $thisDate = $_;
        for my $i (0 .. $#cids)
        {
            if( @cids[$i] != $cluster1 )
            {
                my $cluster2 = @cids[$i];
                my $name2 = @cnames[$i];
                @vals = ();
                push(@vals, $thisDate);
                push(@vals, $cluster1);
                push(@vals, $thisDate);
                push(@vals, $cluster2);
                $query = $queryTemplate;
                doUpdateQuery($self,$query,"DELETE BNL duplicated between $name1 and $name2 $self->{prefix}"."_bnl",\@vals);

                # And now the other direction
                @vals[1] = $cluster2;
                @vals[3] = $cluster1;
                doUpdateQuery($self,$query,"DELETE BNL duplicated between $name2 and $name1 $self->{prefix}"."_bnl",\@vals);
            }
            undef $cluseter2;
            undef $name2;
        }
    }
    undef $cluster1;
    undef $name1;
    undef @vals;
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
    
    if(!$self->{blindDate})
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
        cluster.name ='".$self->{name}."'
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
    if(!$self->{specificMonth})
    {
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
    }
    else
    {
        my $query = "
            select
            concat(
            extract(year from str_to_date('".$self->{specificMonth}."','%Y-%m-%d')),
            '-',
            extract(month from str_to_date('".$self->{specificMonth}."','%Y-%m-%d'))        
            ),
            right(extract(year from str_to_date('".$self->{specificMonth}."','%Y-%m-%d')),2),
            extract(month from str_to_date('".$self->{specificMonth}."','%Y-%m-%d')),
            cast( 
            
            concat
            (
                extract(year from str_to_date('".$self->{specificMonth}."','%Y-%m-%d')),
                '-',
                extract(month from str_to_date('".$self->{specificMonth}."','%Y-%m-%d')),
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
    waitForPageLoad($self);
    while(!$hasWhatIneed)
    {
        try
        {
            $self->{driver}->switch_to_frame($frameNum); # This can throw an error if the frame doesn't exist
            # print "Frame: $frameNum is good\n";
            waitForPageLoad($self);
            my $body = $self->{driver}->execute_script("return document.getElementsByTagName('html')[0].innerHTML");            
            $body =~ s/[\r\n]//g;
            # $self->{log}->addLine("page HTML: $body") if $self->{debug};
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
            # print "died at frame $frameNum\n";
            $frameNum++;
        };
        
        # walk back up to the parent frame        
        $self->{driver}->switch_to_frame();
        waitForPageLoad($self);
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

sub waitForPageLoad
{
    my ($self) = shift;
    my $done = $self->{driver}->execute_script("return document.readyState === 'complete';");
    # print "Page done: $done\n";
    my $stop = 0;
    my $tries = 0;
    
    while(!$done && !$stop)
    {
        $done = $self->{driver}->execute_script("return document.readyState === 'complete';");
        print "Waiting for Page load check: $done\n";
        $tries++;
        $stop = 1 if $tries > 10;
        $tries++;
        sleep 1;
    }
    return $done;
}

sub takeScreenShot
{
    my ($self) = shift;
    my $action = shift;
    $screenShotStep++;
    waitForPageLoad($self);
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