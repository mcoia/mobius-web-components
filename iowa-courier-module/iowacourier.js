jQuery(document).ready(function()
{
    // jQuery("body").append("<input id='test-gmap' type='button' value='click' style='display:block' />" +
    // "<div id='gmap-testing' style='width:80%;height:500px'></div>");
    
    jQuery("#test-gmap").click(function(){
        IOWACourierLibraryConvertToMilitary("6:30am");
        return;
        var mapProp= {
          center:new google.maps.LatLng(51.508742,-0.120850),
          zoom:5,
        };
        var map = new google.maps.Map(document.getElementById("gmap-testing"),mapProp);
        
        var directionsService = new google.maps.DirectionsService();
        var directionsDisplay = new google.maps.DirectionsRenderer();
        directionsDisplay.setMap(map);
        
        var one = 
        {
                location: "Boulder, CO",
                stopover: true,
            };
        var two = 
        {
                location: "Ontario, CA, CA",
                stopover: true,
            };
        var twaypoints = 
        [
            one,two
            
        ];
        
        var request = {
            origin: 'Columbia, MO',
            destination: 'Des Moines, IA',
            travelMode: 'DRIVING',
            waypoints: twaypoints,
          };
        

        directionsService.route(request, function(result, status) {
            if (status == 'OK') {
              directionsDisplay.setDirections(result);
            }
        });
              
    });
});


function IOWACourierLibraryConvertToMilitary(val)
{
    var am = val.replace(/[\s\.\d\:\-]/gi, '').substring(0,2);
    var addNumber = 0;
    var hour = parseInt(val.match(/^([^:]*):.*/)[1]);
    var minute = val.match(/^[^:]*:(\d*).*/)[1];
    var ret = '';
    if(am.toLowerCase().startsWith("pm") && hour < 12)
    {
        addNumber = 12;
    }
    if(am.toLowerCase().startsWith("am") && hour == 12)
    {
        ret = 0;
    }
    else
    {
        ret = parseInt(hour) + parseInt(addNumber);
    }
    // Convert back to string
    ret = "" + ret;
    // 0 pad the hour for better sorting
    ret.length == 1 ? ret = "0" + ret : ret = ret;
    ret = "" + ret + "" + minute;
    return ret;
}

function IOWACourierRouteClick(element)
{
    var libid = jQuery(element).parent().attr("libid");
    var allStops = [];
    var thisRoute = element.firstChild.data;
    var sortedRoute = [];
    var includedCount = 0;
    var clickedLibraryName = IOWACourierGetProperty(libid,'route');
    clickedLibraryName += " - " + IOWACourierGetProperty(libid,'day');
    jQuery(".library-hidden-data").each(function(data){
        var addToRoute = 0;
        var thisSet = {};
        jQuery(this).children("span").each(function(data2){
            var label = jQuery(this).attr("title");
            var metaname = jQuery(this).attr("metaname");
            var tdata = jQuery(this).html();
            thisSet[metaname] = {};
            thisSet[metaname]["title"] = label;
            thisSet[metaname]["data"] = tdata;
            if(metaname == 'route' && tdata == thisRoute)
            {
                addToRoute = 1;
            }
        });
        if(addToRoute)
        {
            allStops.push(thisSet);
            sortedRoute.push(includedCount);
            includedCount++;
        }
    });
    if(sortedRoute.length > 0)
    {
        var libList = "<table class='iowacourier-map-lib-table'><thead><tr><th>Stop</th><th>Library</th><th>Estimated Time</th></tr></thead><tbody>";
        var twaypoints = [];

        // Sort by time
        sortedRoute.sort(function(a, b)
        {
            return parseInt(IOWACourierLibraryConvertToMilitary(allStops[a]['stat_courier_pick_up_schedule']['data'])) - parseInt(IOWACourierLibraryConvertToMilitary(allStops[b]['stat_courier_pick_up_schedule']['data']));
        });
        var torigin = '';
        var tdest = '';

        for(var i=0;i < sortedRoute.length; i++)
        {
            libList += IOWACourierAddWaypointHTML(i,sortedRoute[i],allStops);
            if(i == 0) //origin
            {
                torigin = allStops[sortedRoute[i]]['physical_address']['data'] + ', ' + allStops[sortedRoute[i]]['city']['data']  + ' ' + allStops[sortedRoute[i]]['state']['data'] + ' ' + allStops[sortedRoute[i]]['zip']['data'];
            }
            else if(i != (sortedRoute.length - 1) )
            {
                var thisStop = 
                {
                    location: allStops[sortedRoute[i]]['physical_address']['data'] + ', ' + allStops[sortedRoute[i]]['city']['data']  + ' ' + allStops[sortedRoute[i]]['state']['data'] + ' ' + allStops[sortedRoute[i]]['zip']['data'],
                    stopover: true,
                };
                twaypoints.push(thisStop);
            }
            else  //destination
            {
                tdest = allStops[sortedRoute[i]]['physical_address']['data'] + ', ' + allStops[sortedRoute[i]]['city']['data']  + ' ' + allStops[sortedRoute[i]]['state']['data'] + ' ' + allStops[sortedRoute[i]]['zip']['data'];
            }
        }

        libList+="</tbody></table>";

        jQuery("body").append("<div class='card-pane'><div class='card-title'>Route "+clickedLibraryName+"</div>"+
        "<div class='card-pane-inner'><div id='iowacourier-map-display-map' class='iowacourier-map-display-map'></div><div class='iowacourier-map-display-table'>" + libList +
        "</div></div><div class='card-pane-close'><a href='#'>[close]</a></div>"+
        "</div>");
        
        jQuery(".card-pane-close").click(function(){
            jQuery(".card-pane").remove();
        });
        var mapProp = {
          center:new google.maps.LatLng(41.5868,-93.6250),
          zoom:8,
        };
        var map = new google.maps.Map(document.getElementById("iowacourier-map-display-map"),mapProp);
        
        var directionsService = new google.maps.DirectionsService();
        var directionsDisplay = new google.maps.DirectionsRenderer();
        directionsDisplay.setMap(map);
        
        var request = {
            origin: torigin,
            destination: tdest,
            travelMode: 'DRIVING',
            waypoints: twaypoints,
          };

        directionsService.route(request, function(result, status) {
            if (status == 'OK') {
              directionsDisplay.setDirections(result);
            }
        });
    }
}

function IOWACourierAddWaypointHTML(i,pos,allStops)
{
    
    var stopNum = i;
    stopNum++;
    var rowClass = 'odd';
    i % 2 == 0 ? rowClass="even" : rowClass="";
    var ret = '<tr class="'+rowClass+'">';
    ret+="<td class='iowacourier-waypoint-stop-cell'>"+IOWACourierConvertNumbertoLetter(stopNum)+"</td><td class='iowacourier-waypoint-library-cell'><div class='iowacourier-waypoint-library-cell-name'>";
    ret+=allStops[pos]['library_name']['data'];
    ret+="</div><div class='iowacourier-waypoint-library-cell-address'>";
    ret+="("+allStops[pos]['physical_address']['data']+")";
    ret+="</div></div></td>";
    ret+="<td><div class='iowacourier-waypoint-time-cell-data'>"+allStops[pos]['stat_courier_pick_up_schedule']['data']+"</div></td>";
    ret+="</tr>";
    return ret;
    
}

function IOWACourierConvertNumbertoLetter(num)
{
    var alphabet = ' abcdefghijklmnopqrstuvwxyz'.split('');
    var pos = parseInt(num);
    var ret = '';
    var loops = 1;
    while(pos > 26)
    {
        loops++;
        pos = pos - 26;
    }
    loops == 1 ? ret = alphabet[pos] : ret = alphabet[1] + "" + alphabet[loops];
    return ret.toUpperCase();
}

function IOWACourierGetProperty(libid, property)
{
    var ret = '';
    jQuery("#iowacourier-metadata-"+libid+" > span").each(function(data){
        var metaname = jQuery(this).attr("metaname");
        if(metaname == property)
        {
            ret = jQuery(this).html();
        }
    });
    return ret;
}

    function IOWACourierLibraryClick(element)
    {
        var libid = jQuery(element).parent().attr("libid");
        var thisLibrary = {};
        var allFields = [];
        var htmlCard = "";
        jQuery("#iowacourier-metadata-"+libid+" > span").each(function(data){
            var label = jQuery(this).attr("title");
            var metaname = jQuery(this).attr("metaname");
            var tdata = jQuery(this).html();
            thisLibrary[metaname] = {};
            thisLibrary[metaname]["title"] = label;
            thisLibrary[metaname]["data"] = tdata;
            allFields.push(metaname);
        });
        
        var titleDiv = "<div class='card-title'>"+thisLibrary[displayTitleField]["data"]+"</div>";
        allFields = IOWACourierRemoveValueFromArray(displayTitleField,allFields);
        
        for(groupName in displayGroupingOrder)
        {  
            htmlCard += "<div class='group-card-wrapper'><div class='group-card-wrapper-title'>" + displayGroupingOrder[groupName] + "</div>";
            
            for(var i = 0; i < displayGrouping[displayGroupingOrder[groupName]].length; i++)
            {   
                if(thisLibrary[displayGrouping[displayGroupingOrder[groupName]][i]]["data"].length > 0)
                {
                    htmlCard += IOWACourierAddPair(thisLibrary[displayGrouping[displayGroupingOrder[groupName]][i]]["title"],thisLibrary[displayGrouping[displayGroupingOrder[groupName]][i]]["data"]);
                    allFields = IOWACourierRemoveValueFromArray(displayGrouping[displayGroupingOrder[groupName]][i],allFields);
                }
            }
            
            htmlCard += "</div>";
        }
        
        if(allFields.length > 0) /* Display the rest */
        {
            htmlCard += "<div class='group-card-wrapper'><div class='group-card-wrapper-title'>MISC Info</div>";
            var thisSort = [];
            for(var i = 0; i < allFields.length; i++)
            {
                thisSort.push(thisLibrary[allFields[i]]["title"]);
            }
            thisSort.sort();
            
            for(var i = 0; i < thisSort.length; i++)
            {
                for(metaname in thisLibrary)
                {
                    if( (thisLibrary[metaname]["title"] == thisSort[i]) && (thisLibrary[metaname]["data"].length > 0) )
                    {
                        htmlCard += IOWACourierAddPair(thisLibrary[metaname]["title"],thisLibrary[metaname]["data"]);
                    }
                }
            }
            htmlCard += "</div>";
        }   
        
        jQuery("body").append("<div class='card-pane'>"+titleDiv+"<div class='card-pane-inner'>" + htmlCard + "</div>" +
        "<div class='card-pane-close'><a href='#'>[close]</a></div>"+
        "</div>");
        
        jQuery(".card-pane-close").click(function(){
                jQuery(".card-pane").remove();
        });
    }
    
    function IOWACourierAddPair(title,data)
    {
        var ret = "<div class='card-wrapper'>\n";
        if(data.toLowerCase().startsWith("http"))
        {
            data = "<a href='"+data+"'>"+data+"</a>";
        }
        else if( (data.match(/\./g) !== null) &&(data.match(/@/g) !== null) )
        {
            data = "<a href='mailto:"+data+"'>"+data+"</a>";
        }
        ret += "<div class='card-wrapper-label'>" + title + "</div>";
        ret += "<div class='card-wrapper-data'>" + data + "</div>";
        ret += "</div>\n";
        return ret;
    }
    
    function IOWACourierRemoveValueFromArray(val,arr)
    {
        for(var i=0;i<arr.length;i++)
        {
            if(arr[i] == val)
            {
                arr.splice(i, 1);
                break;
            }
        }
        return arr;
    }