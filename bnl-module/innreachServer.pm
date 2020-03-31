#!/usr/bin/perl

package innreachServer;

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
        my @pageVals = @{@dateScrapes[0]};
        my @dbvals = @{@dateScrapes[1]};
        my $pos = 0;
        foreach(@pageVals)
        {
            print $self->{name}." pulling ". @dbvals[$pos] ."\n";
            $continue = handleDateSelect($self, @dbvals[$pos]) if $continue;
            collectReportData($self, @dbvals[$pos]) if $continue;
            $pos++;
            $continue = handleLandingPage($self);
        }
        $self->SUPER::cleanDuplicates();
    }
}

sub collectReportData
{
    my ($self) = shift;
    my $dbDate = shift;
    my @frameSearchElements = ('Fulfillments Report');
        
    if(!$self->switchToFrame(\@frameSearchElements))
    {
        my $randomHash = $self->SUPER::collectReportData($dbDate);
        $self->SUPER::normalizeNames();
    }
    else
    {
        return 0;
    }
}


sub handleLandingPage
{
    my ($self) = @_[0];
    my @frameSearchElements = ('<hr>REPORTS');
        
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

                    if(thisaction.match(/olinkpatrep\\/report2\\/0\\/\\//g))
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
            return 1;
            ");
        sleep 5;

        $self->{driver}->switch_to_frame();
        $self->switchToFrame(\@frameSearchElements);
        
        $owning = $self->{driver}->execute_script("
            var doms = document.getElementsByTagName('a');
            var stop = 0;
            for(var i=0;i<doms.length;i++)
            {
                if(!stop)
                {
                    var thisaction = doms[i].getAttribute('onClick');

                    if(thisaction.match(/olinkpatrep\\/report2\\/0\\/user_spec\\//g))
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
            return 1;
            ");

        sleep 5;
        $self->{driver}->switch_to_frame();
        $self->takeScreenShot('handleLandingPage');
        return 1;
    }
    else
    {
        return 0;
    }
}

sub handleDateSelect
{
    my ($self) = shift;
    my $date = shift;
    my ($year, $month) = ($date =~ /(\d{4})\-(\d{2}).*/);
    # make them numbers instead of strings
    $year += 0;
    $month += 0;
    my @frameSearchElements = ('Please enter the Beginning and Ending');
        
    if(!$self->switchToFrame(\@frameSearchElements))
    {
        my $script = "
            var monthElements = [document.getElementById('bMonth'), document.getElementById('eMonth')];
            var yearElements = [document.getElementById('bYear'), document.getElementById('eYear')];
            var changed = 0;
            for(var i=0;i<monthElements.length;i++)
            {
                for(var j=0;j<monthElements[i].options.length;j++)
                {
                    if(monthElements[i].options[j].value == '$month')
                    {
                        monthElements[i].selectedIndex = j;
                        changed++;
                        break;
                    }
                }
            }
            for(var i=0;i<yearElements.length;i++)
            {
                for(var j=0;j<yearElements[i].options.length;j++)
                {
                    if(yearElements[i].options[j].value == '$year')
                    {
                        yearElements[i].selectedIndex = j;
                        changed++;
                        break;
                    }
                }
            }
            if(changed == 4)
            {
                document.getElementById('submit').click();
                return 1;
            }
            else
            {
                return 0;
            }
            ";
        $self->{log}->addLine("Script: $script");
        my $answer = $self->{driver}->execute_script($script);
        sleep 10;
        $self->{driver}->switch_to_frame();
        $self->takeScreenShot('handleDateSelect');
        return $answer;
    }
    else
    {
        return 0;
    }
}


1;