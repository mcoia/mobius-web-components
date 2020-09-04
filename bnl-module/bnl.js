jQuery(document).ready(function()
{
    if(jQuery("#mobius_bnl_page_is_loaded").length > 0)
    {
        var branch_obj;
        var dropdown_vals = 
        {
            branch_basic: {
                dom: '#bnl_basic_filter_branch',
                chooser: 'basic_branch_multi_select',
                placeholder: 'Choose Library'
            },
            branch: {
                dom: '#bnl_filter_branch',
                chooser: 'branch_multi_select',
                placeholder: 'Choose Library'
            },
            cluster: {
                dom: '#bnl_filter_cluster',
                chooser: 'cluster_multi_select',
                placeholder: 'Choose Cluster'
            },
            system: {
                dom: '#bnl_filter_system',
                chooser: 'system_multi_select',
                placeholder: 'Choose System'
            },
        }

        bnl_get_seed_data('#bnl_filter_select_master_container',dropdown_vals);

        function checkGetable()
        {
            jQuery("#bnl_submit_button").addClass('bnl_submit_not_allowed');
            jQuery('#bnl_submit_button').unbind("click");
            var good_dates = 0;
            var good_libs = 0;
            if(jQuery("#filter_switcher_word").html() != 'Advanced') // advanced filters do not require any library input
            {
                good_libs = 1;
            }
            else // Basic filter requires input
            {
                var dom = "#owning_"+dropdown_vals['branch_basic']['chooser'];
                if(jQuery(dom).val() && jQuery(dom).val().length > 0)
                {
                    good_libs = 1;
                }
            }
            if( (jQuery("#date_from").val().length > 0) && (jQuery("#date_to").val().length > 0) )
            {
                if(jQuery("#date_from").val().length > 0 && jQuery("#date_from").val().match(/\d{2}\/\d{4}/) !== null)
                {
                    if(jQuery("#date_from").val().length > 0 && jQuery("#date_from").val().match(/\d{2}\/\d{4}/) !== null)
                    {
                        good_dates = 1;
                    }
                }
            }
            if(good_dates && good_libs)
            {
                jQuery("#bnl_submit_button").removeClass('bnl_submit_not_allowed');
                jQuery('#bnl_submit_button').click(function(){
                    bnl_generate_data(
                        '#bnl_lib_to_lib_div',
                        '#bnl_my_lending_div',
                        '#bnl_my_borrowing_div',
                        '#bnl_my_lending_percentage_div',
                        '#bnl_my_borrowing_percentage_div',
                        dropdown_vals
                    );
                });
            }
            else
            {
                jQuery('#bnl_submit_button').unbind("click");
            }
        }

        function bnlGetCookie(cname) {
            var name = "bnl_" + cname + "=";
            var ca = document.cookie.split(';');
            for(var i=0; i<ca.length; i++) {
                var c = ca[i];
                while (c.charAt(0)==' ') c = c.substring(1);
                if (c.indexOf(name) == 0) return c.substring(name.length,c.length).replace(/v0v/g,';').replace(/v1v/g,'&');
            }
            return 0;
        }

        function bnlSetCookie(cname, cvalue, exdays) {
            cvalue = cvalue.replace(/;/g,'v0v').replace(/&/g,'v1v');
            var d = new Date();
            d.setTime(d.getTime() + (exdays*24*60*60*1000));
            var expires = "expires="+d.toUTCString();
            var finalc = "bnl_" + cname + "="
            + cvalue
            + "; " + expires
            + "; path=/";
            //+ cvalue
            document.cookie = finalc;
        }

        function bnl_get_seed_data(bnl_panel_dom, dropdown_vals)
        {
            var saveHTML = jQuery(bnl_panel_dom).html();
            jQuery(bnl_panel_dom).html(' ');
            jQuery(bnl_panel_dom).addClass('loader');
            // Figure out all of the branches/clusters in the database
            jQuery.get("borrowing_n_lending_get?get_branches=1", function(ob)
            {
                branch_obj = ob;
            }).done(function()
            {
                jQuery(bnl_panel_dom).removeClass('loader');
                jQuery(bnl_panel_dom).html(saveHTML);
                jQuery("#filter_switcher_button").click(function(){ filter_show_hide(); } ); //wire up the clickable basic/advanced filter trigger
                
                // fill in the date ranges available in the data
                jQuery.get("borrowing_n_lending_get?get_data_date_range=1", function(data)
                {
                    bnl_init_date(data);
                });

                var tarray = ['owning','borrowing'];
                if(branch_obj['branch'] && branch_obj['branch_order'])
                {
                    for(var i in tarray)
                    {
                        var type = tarray[i];
                        // var selectHTML = '<select multiple id="'+type+'_'+dropdown_vals['branch']['chooser']+'" data-placeholder="'+dropdown_vals['branch']['placeholder']+'(s)...">';
                        var selectHTML = '<select multiple id="select_id_string" data-placeholder="select_placeholder">';
                        for (var branch_pos in branch_obj['branch_order'])
                        {
                            selectHTML += '<option value="'+branch_obj['branch_order'][branch_pos]+'">'+branch_obj['branch'][branch_obj['branch_order'][branch_pos]]+'</option>\n';
                        }
                        selectHTML += '</select>';
                        
                        if(type == 'owning') // Take care of the simple filter dropdown menu
                        {
                            var basicHTML = selectHTML;
                            basicHTML = basicHTML.replace(/multiple\sid="select_id_string"/gi,'multiple id="'+type+'_'+dropdown_vals['branch_basic']['chooser']+'"');
                            basicHTML = basicHTML.replace(/data-placeholder="select_placeholder"/gi,'data-placeholder="'+dropdown_vals['branch_basic']['placeholder']+'..."');
                            jQuery(dropdown_vals['branch_basic']['dom']+"_"+type).html(basicHTML);
                            jQuery('#'+type+'_'+dropdown_vals['branch_basic']['chooser']).chosen({max_selected_options: 1}).change(function(){checkGetable();});
                        }
                        selectHTML = selectHTML.replace(/multiple\sid="select_id_string"/gi,'multiple id="'+type+'_'+dropdown_vals['branch']['chooser']+'"');
                        selectHTML = selectHTML.replace(/data-placeholder="select_placeholder"/gi,'data-placeholder="'+dropdown_vals['branch']['placeholder']+'(s)..."');
                        jQuery(dropdown_vals['branch']['dom']+"_"+type).html(selectHTML);
                        jQuery('#'+type+'_'+dropdown_vals['branch']['chooser']).chosen().change(
                        function(data)
                        {
                            disable_other_dropdowns(data.currentTarget.id,dropdown_vals);
                            checkGetable();
                        });
                    }
                    // jQuery("#bnl_my_lending_div").html("<table id='testing_table'><thead><tr><th>testing</th><th>testing2</th></tr></thead><tbody><tr><td>hello</td><td>hello2</td></tr></tbody></table>");
                    // jQuery("#testing_table").dataTable();
                }
                if(branch_obj['cluster'])
                {
                    for(var i in tarray)
                    {
                        var type = tarray[i];
                        var selectHTML_cluster = '<select multiple id="'+type+'_'+dropdown_vals['cluster']['chooser']+'" data-placeholder="'+dropdown_vals['cluster']['placeholder']+'(s)...">';
                        var selectHTML_system = '<select multiple id="'+type+'_'+dropdown_vals['system']['chooser']+'" data-placeholder="'+dropdown_vals['system']['placeholder']+'(s)...">';
                        var clusterSort = [];
                        for (var cluster in branch_obj['cluster'])
                        {
                            var t = {'name': branch_obj['cluster'][cluster]['name'], 'id': cluster };
                            clusterSort.push(t);
                        }
                        clusterSort.sort(function(a,b)
                        {
                            return a['name'].toLowerCase() > b['name'].toLowerCase();
                        });

                        for (var cluster in clusterSort)
                        {
                            if(branch_obj['cluster'][clusterSort[cluster]['id']]['type'] == 'sierra')
                            {
                                selectHTML_cluster += '<option value="'+clusterSort[cluster]['id']+'">'+clusterSort[cluster]['name']+'</option>\n';
                            }
                            else
                            {
                                selectHTML_system += '<option value="'+clusterSort[cluster]['id']+'">'+clusterSort[cluster]['name']+'</option>\n';
                            }
                        }
                        selectHTML_cluster += '</select>';
                        selectHTML_system += '</select>';
                        jQuery(dropdown_vals['cluster']['dom']+"_"+type).html(selectHTML_cluster);
                        jQuery(dropdown_vals['system']['dom']+"_"+type).html(selectHTML_system);
                        jQuery('#'+type+'_'+dropdown_vals['cluster']['chooser']).chosen().change(
                        function(data)
                        {
                            disable_other_dropdowns(data.currentTarget.id,dropdown_vals);
                            checkGetable();
                        });
                        jQuery('#'+type+'_'+dropdown_vals['system']['chooser']).chosen().change(
                        function(data)
                        {
                            disable_other_dropdowns(data.currentTarget.id,dropdown_vals);
                            checkGetable();
                        });
                    }
                }
                // Make a new entry for branch_to_system for later use
                branch_obj['branch_to_system'] = {};
                for(var branch in branch_obj['branch_to_cluster'])
                {
                    for(var cluster_id in branch_obj['branch_to_cluster'][branch])
                    {
                        if(branch_obj['cluster'][cluster_id]['type'] == 'innreach')
                        {
                            branch_obj['branch_to_system'][branch] = cluster_id;
                        }
                    }
                }
                checkGetable();
            });
            jQuery("#firsttimebutton").click(function(){ bnl_firsttimeinstructions();});
            jQuery("#instructions_show_hide_a").click(function(){ bnl_show_hide();});
        }

        function bnl_generate_data(lib_to_lib_dom, my_lending_dom, my_borrowing_dom, percent_lending_dom, percent_borrowing_dom, dropdown_vals)
        {
            var includeZeros = jQuery("#show_zeros").is(':checked');
            var startDate = bnlGetCookie('#date_from');
            var endDate = bnlGetCookie('#date_to');
            if(startDate && endDate)
            {
                startDate = moment(startDate, 'MM/YYYY').format('YYYY-MM');
                endDate = moment(endDate, 'MM/YYYY').format('YYYY-MM');
                bnl_generate_tables(
                    lib_to_lib_dom,
                    my_lending_dom,
                    my_borrowing_dom,
                    dropdown_vals,
                    startDate,
                    endDate
                );
                bnl_generate_tables_percent(
                    percent_lending_dom,
                    percent_borrowing_dom,
                    dropdown_vals,
                    startDate,
                    endDate
                );
            }
        }

        function bnl_generate_tables(lib_to_lib_dom, my_lending_dom, my_borrowing_dom, dropdown_vals, startDate, endDate)
        {
            jQuery(my_lending_dom).html(' ');
            jQuery(my_lending_dom).addClass('loader');
            jQuery(my_borrowing_dom).html(' ');
            jQuery(my_borrowing_dom).addClass('loader');
            jQuery(lib_to_lib_dom).html(' ');
            jQuery(lib_to_lib_dom).addClass('loader');
            var types =
                {
                    lent: {
                            dom: my_lending_dom,
                            table_dom: 'bnl_my_lending_table',
                            th_plib_head: 'Lending Library',
                            th_slib_head: 'Borrowing Library',
                            th_total_head: 'Lent Total',
                            table_h1: 'Lending Summary',
                            pdirection: 'across',
                            sdirection: 'down',
                            total: 0,
                            html: ''
                        },
                    borrow: {
                            dom: my_borrowing_dom,
                            table_dom: 'bnl_borrowing_summary_table',
                            th_plib_head: 'Borrowing Library',
                            th_slib_head: 'Lending Library',
                            th_total_head: 'Borrow Total',
                            table_h1: 'Borrowing Summary',
                            pdirection: 'down',
                            sdirection: 'across',
                            total: 0,
                            html: ''
                        }
                }

            var lib_to_lib = 
            {
                month_order: [],
                months: {},
                dom: lib_to_lib_dom
            };
            var qstring = getMultiSelectOptionsForQueryString(dropdown_vals);
            console.log("Gathering from borrowing_n_lending_get?startdate="+startDate+"&enddate="+endDate+qstring);
            jQuery.get("borrowing_n_lending_get?startdate="+startDate+"&enddate="+endDate+qstring, function(data)
            {
                for(var type in types)
                {
                    if(data[type])
                    {
                        // Setup the branch_sort to make only one trip through!
                        branch_obj['branch_sort'] = {};
                        for(var l in branch_obj['branch_order'])
                        {
                            branch_obj['branch_sort'][branch_obj['branch_order'][l]] = l;
                        }

                        // Figure out the full set of month column slots
                        var months = bnl_dedupe_array(data[type]);
                        months.reverse();
                        // record into the lib_to_lib array
                        for(var m_pos in months)
                        {
                            var m = months[m_pos];
                            if(!lib_to_lib['months'][m])
                            {
                                lib_to_lib['months'][m] = 
                                {
                                    down: [],
                                    across: [],
                                    html: ''
                                };
                            }
                            if(!lib_to_lib['month_order'].includes(m))
                            {
                                lib_to_lib['month_order'].push(m);
                            }
                        }
                        // Figure out the full set of systems column slots
                        var systems = bnl_dedupe_array(branch_obj['branch_to_system'], 1);
                        // Figure out the full set of primary library branches
                        var plibs = bnl_dedupe_array(data[type], 1, 1);
                        // figure out the complete list of secondary libs for each plib (cutting through all months)
                        var slibs = {};
                        for(var plib_pos in plibs)
                        {
                            var plib = plibs[plib_pos];
                            for(var month_pos in months)
                            {
                                var month = months[month_pos];
                                var l_dedupe = {};
                                for(var slib in data[type][month][plib])
                                {
                                    l_dedupe[slib] = 1;
                                }
                            }
                            slibs[plib] = []
                            for(var slib in l_dedupe)
                            {
                                slibs[plib].push(slib);
                            }
                            slibs[plib] = bnlSortArrayIntoBranchOrder(slibs[plib]);
                        }
                        if(months.length > 0 && systems.length > 0)
                        {
                            // initialize a variable to hold the totals
                            var monthGrandTotals = [];
                            for(var month in months)
                            {
                                monthGrandTotals.push(0);
                            }
                            types[type]['html'] = "<table id = '"+types[type]['table_dom']+"'><thead><tr><th>"+types[type]['th_plib_head']+"</th><th>Consortium</th><th>"+types[type]['th_slib_head']+"</th><th>"+types[type]['th_total_head']+"</th>";
                            for(var month in months)
                            {
                                types[type]['html'] += "<th>" + moment(months[month],'YYYY-MM-DD').format('MM/YYYY') + "</th>";
                            }
                            types[type]['html'] += "</tr></thead><tbody>";
                            
                            for(var plib_pos in plibs)
                            {
                                var plib = plibs[plib_pos];
                                for(var system_pos in systems)
                                {
                                    var system = systems[system_pos];
                                    var monthTotalSystem = [];
                                    var systemShow = 0;
                                    for(var month in months)
                                    {
                                        monthTotalSystem.push(0);
                                    }
                                    for(var slib_pos in slibs[plib])
                                    {
                                        var slib = slibs[plib][slib_pos];
                                        if(slib != plib) // surpress self-circs
                                        {
                                            if( branch_obj['branch_to_system'][slib] == system )// matching in order and that we are in the right system
                                            {
                                                var monthTotals = [];
                                                var branchShow = 0;
                                                for(var month_pos in months)
                                                {
                                                    var month = months[month_pos];
                                                    if( (data[type][month]) && (data[type][month][plib]) && (data[type][month][plib][slib]) )
                                                    {
                                                        monthTotals.push(data[type][month][plib][slib]);
                                                        monthTotalSystem[month_pos] += data[type][month][plib][slib];
                                                        monthGrandTotals[month_pos] += data[type][month][plib][slib];
                                                        branchShow = 1;
                                                        systemShow = 1;
                                                        if(!lib_to_lib['months'][month][ types[type]['pdirection'] ].includes(plib))
                                                        {
                                                            lib_to_lib['months'][month][ types[type]['pdirection'] ].push(plib);
                                                        }
                                                        if(!lib_to_lib['months'][month][ types[type]['sdirection'] ].includes(slib))
                                                        {
                                                            lib_to_lib['months'][month][ types[type]['sdirection'] ].push(slib);
                                                        }
                                                    }
                                                    else
                                                    {
                                                        monthTotals.push(0);
                                                    }
                                                }
                                                if(branchShow)
                                                {
                                                    types[type]['html'] = addHTMLRow_my_tables(type, branch_obj['branch'][plib], branch_obj['cluster'][system]['name'], branch_obj['branch'][slib], monthTotals, months, types[type]['html']);
                                                }
                                            }
                                        }
                                    }
                                    if(systemShow)
                                    {
                                        types[type]['html'] = addHTMLRow_my_tables(type, branch_obj['branch'][plib], branch_obj['cluster'][system]['name'],"<span class='sort'>Z</span>Sub Total:", monthTotalSystem, months, types[type]['html']);
                                    }
                                }
                            }
                            types[type]['html'] = addHTMLRow_my_tables(type, "<span class='sort'>Z</span>All", "<span class='sort'>Z</span>All","Grand Total:", monthGrandTotals, months, types[type]['html']);
                            for(var montht in monthGrandTotals)
                            {
                                types[type]['total']+=monthGrandTotals[montht];
                            }
                        }
                        types[type]['html'] += "</tbody></table>";
                    }
                }
                // Finished building the "my" tables, Now onto the "Lib to lib" table(s) - one for each month in range
                lib_to_lib['month_order'].reverse();
                
                for(var month_pos in lib_to_lib['month_order'])
                {
                    var month = lib_to_lib['month_order'][month_pos];
                    var colTotals = [0]; // First element is the grand total column
                    lib_to_lib['months'][month]['across'] = bnlSortArrayIntoBranchOrder(lib_to_lib['months'][month]['across']);
                    lib_to_lib['months'][month]['down'] = bnlSortArrayIntoBranchOrder(lib_to_lib['months'][month]['down']);
                    lib_to_lib['months'][month]['table_dom'] = "lib_to_lib_" + month;
                    lib_to_lib['months'][month]['table_h1'] = "Details - " + moment(month,'YYYY-MM-DD').format('MM/YYYY');
                    lib_to_lib['months'][month]['html'] = "<table id='" + lib_to_lib['months'][month]['table_dom'] + "' class='lib_to_lib_data_table'><thead><th>Borrowing Library</th><th>Total</th>";
                    for(var slib_pos in lib_to_lib['months'][month]['across'])
                    {
                        var slib = lib_to_lib['months'][month]['across'][slib_pos];
                        lib_to_lib['months'][month]['html'] += "<th>" + branch_obj['branch'][slib] + "</th>";
                        colTotals.push(0);
                    }
                    lib_to_lib['months'][month]['html'] += "</thead><tbody>";
                    
                    for(var plib_pos in lib_to_lib['months'][month]['down'])
                    {
                        var plib = lib_to_lib['months'][month]['down'][plib_pos];
                        var total = 0;
                        var colHTML = "";
                        var colPos = 1;
                        for(var slib_pos in lib_to_lib['months'][month]['across'])
                        {
                            var slib = lib_to_lib['months'][month]['across'][slib_pos];
                            var amount = 0;
                            // Only running through the borrow data, This is essentially a borrow diagram
                            if(data['borrow'] && data['borrow'][month] && data['borrow'][month][plib] && data['borrow'][month][plib][slib])
                            {
                                amount += data['borrow'][month][plib][slib];
                                total += amount;
                            }
                            colHTML+="<td>" + amount + "</td>";
                            colTotals[colPos] += amount;
                            colPos++;
                            amount = undefined;
                        }
                        colTotals[0] += total;
                        lib_to_lib['months'][month]['html'] += "<tr><td>" + branch_obj['branch'][plib] + "</td><td>" + total + "</td>" + colHTML +"</tr>";
                    }
                    lib_to_lib['months'][month]['html'] += "<tr><td>Totals</td>";
                    for(var t_pos in colTotals)
                    {
                        lib_to_lib['months'][month]['html'] += "<td>" + colTotals[t_pos] + "</td>";
                    }
                    lib_to_lib['months'][month]['html'] += "</tr></tbody></table>";
                }
            }).done(function(){
                console.log("Finished loading branch_table");
                for(var type in types)
                {
                    jQuery(types[type]['dom']).removeClass('loader');
                    var thishtml = 
                        "<h1>"+types[type]['table_h1']+"</h1>"+
                        types[type]['html'] +
                        bnl_create_csv_download_link(types[type]['table_h1'],types[type]['table_dom'])+
                        "<h2>Total: "+types[type]['total']+"</h2>";
                    jQuery(types[type]['dom']).html(thishtml);
                    bnl_wire("#"+types[type]['table_dom'],[[1,'asc'],[0,'asc'],[2,'asc']], 6); // column limit for screen realestate issues
                }
                jQuery(lib_to_lib['dom']).removeClass('loader');
                
                for(var month_pos in lib_to_lib['month_order'])
                {
                    var month = lib_to_lib['month_order'][month_pos];
                    var thishtml = 
                        "<h1>" + lib_to_lib['months'][month]['table_h1'] + "</h1>"+
                        lib_to_lib['months'][month]['html']+
                        bnl_create_csv_download_link(lib_to_lib['months'][month]['table_h1'],lib_to_lib['months'][month]['table_dom'] );
                    jQuery(lib_to_lib['dom']).append(thishtml);
                    bnl_wire("#"+lib_to_lib['months'][month]['table_dom'],[[0,'asc']], 8); // column limit for screen realestate issues
                }
            });
        }

        function bnl_generate_tables_percent(percent_lending_dom, percent_borrowing_dom, dropdown_vals, startDate, endDate)
        {
            jQuery(percent_lending_dom).html(' ');
            jQuery(percent_lending_dom).addClass('loader');
            jQuery(percent_borrowing_dom).html(' ');
            jQuery(percent_borrowing_dom).addClass('loader');
            var types =
                {
                    lent: {
                            dom: percent_lending_dom,
                            table_dom: 'bnl_my_lending_percentage_table',
                            th_total_head: 'Lent Total',
                            table_h1: 'Lending Percentage Summary',
                            dest_th: 'Lent to System',
                            total_system_th: 'Total System Lends',
                            html: ''
                        },
                    borrow: {
                            dom: percent_borrowing_dom,
                            table_dom: 'bnl_my_lending_borrowing_table',
                            th_total_head: 'Borrow Total',
                            table_h1: 'Borrowing Percentage Summary',
                            dest_th: 'Borrowed from System',
                            total_system_th: 'Total System Borrows',
                            html: ''
                        }
                }
            var qstring = getMultiSelectOptionsForQueryString(dropdown_vals);
            console.log("Gathering from borrowing_n_lending_get?percentage=1&startdate="+startDate+"&enddate="+endDate+qstring);
            jQuery.get("borrowing_n_lending_get?percentage=1&startdate="+startDate+"&enddate="+endDate+qstring, function(data)
            {
                for(var type in types)
                {
                    if(data[type])
                    {
                        types[type]['html'] = "<table id = '"+types[type]['table_dom']+"'><thead><tr><th>Month</th><th>Library</th><th>System</th><th>"+types[type]['dest_th']+"</th><th>"+types[type]['total_system_th']+"</th><th>Contribution Percentage</th></thead>";
                        types[type]['html'] += "<tbody>";
                        for(var month in data[type])
                        {
                            for(var branch in data[type][month])
                            {
                                for(var system in data[type][month][branch])
                                {
                                    if(branch_obj['cluster'][system])
                                    {
                                        types[type]['html'] = addHTMLRow_percentage_tables(type, moment(month,'YYYY-MM-DD').format('MM/YYYY'), branch_obj['branch'][branch], branch_obj['cluster'][system]['name'], data[type][month][branch][system][0], data[type][month][branch][system][1], data[type][month][branch][system][2] + "%", types[type]['html']);
                                    }
                                    else
                                    {
                                        console.log("error: " + branch_obj['cluster'][system] + "not found in cluster array");
                                    }
                                }
                            }
                        }
                        types[type]['html'] += "</tbody></table>";
                    }
                }
            }).done(function(){
                console.log("Finished loading percentage table data");
                for(var type in types)
                {
                    jQuery(types[type]['dom']).removeClass('loader');
                    var thishtml = 
                        "<h1>"+types[type]['table_h1']+"</h1>"+
                        types[type]['html']+
                        bnl_create_csv_download_link(types[type]['table_h1'],types[type]['table_dom']);
                    jQuery(types[type]['dom']).html(thishtml);
                    bnl_wire("#"+types[type]['table_dom'],[[0,'asc'],[1,'asc'],[2,'asc']]);
                }
            });   
        }

        function bnl_dedupe_array(a_array, inner = 0, lib_branch_order = 0)
        {
            var dedupe = {};
            var ret = [];
            for (var d in a_array)
            {
                var v = [d];
                if(inner)
                {
                    if(typeof(a_array[d]) == 'object') // only going one more level and that's enough please
                    {
                        v = [];
                        for (var c in a_array[d])
                        {
                            v.push(c);
                        }
                    }
                    else
                    {                        
                        v = [a_array[d]];
                    }
                }
                for(var l in v)
                {
                    if(!dedupe[v[l]])
                    {
                        dedupe[v[l]] = 1;
                    }
                }
            }
            for(var d in dedupe)
            {
                ret.push(d);
            }
            ret.sort();
            if(lib_branch_order)
            {
                ret = bnlSortArrayIntoBranchOrder(ret);
            }
            return ret;
        }
        
        function bnlSortArrayIntoBranchOrder(tarray)
        {
            tarray.sort(function(a,b)
            {
                return parseInt(branch_obj['branch_sort'][a]) > parseInt(branch_obj['branch_sort'][b]);
            });
            return tarray;
        }

        function addHTMLRow_my_tables(type, primaryBranchName, systemName, secondaryBranchName, monthTotalArray, monthArray, HTML)
        {
            var total = 0;
            var monthHTML = "";
            for(var month in monthArray)
            {
                total+=monthTotalArray[month];
                monthHTML += "<td class='bnl_branch_table_"+type+"_single_month_total'>"+monthTotalArray[month]+"</td>\n";
            }
            HTML += "<tr>";
            HTML += "<td class='bnl_branch_table_"+type+"_owning_lib'>"+primaryBranchName+"</td>\n";
            HTML += "<td class='bnl_branch_table_"+type+"_system'>"+systemName+"</td>\n";
            HTML += "<td class='bnl_branch_table_"+type+"_borrowing_lib'>"+secondaryBranchName+"</td>\n";
            HTML += "<td class='bnl_branch_table_"+type+"_months_total'>"+total+"</td>\n";
            HTML += monthHTML;
            HTML += "</tr>";
            return HTML;
        }

        function addHTMLRow_percentage_tables(type, month, branchName, systemName, quantity, total, percentage, HTML)
        {
            HTML += "<tr>\n";
            HTML += "<td class='bnl_percentage_table_"+type+"_mont'>"+month+"</td>\n";
            HTML += "<td class='bnl_percentage_table_"+type+"_lib'>"+branchName+"</td>\n";
            HTML += "<td class='bnl_percentage_table_"+type+"_system'>"+systemName+"</td>\n";
            HTML += "<td class='bnl_percentage_table_"+type+"_quantity'>"+quantity+"</td>\n";
            HTML += "<td class='bnl_percentage_table_"+type+"_total'>"+total+"</td>\n";
            HTML += "<td class='bnl_percentage_table_"+type+"_percentage'>"+percentage+"</td>\n";
            HTML += "</tr>\n";
            return HTML;
        }
        
        function addHTMLRow(type, owningBranchName, borrowingBranchName, amount, HTML)
        {
            HTML += "<tr>";
            HTML += "<td class='bnl_branch_table_"+type+"_owning_lib'>"+owningBranchName+"</td>\n";
            HTML += "<td class='bnl_branch_table_borrowing_lib'>"+borrowingBranchName+"</td>\n";
            HTML += "<td class='bnl_branch_table_borrowing_lib'>"+amount+"</td>\n";
            HTML += "</tr>";
            return HTML;
        }

        function getMultiSelectOptionsForQueryString(dropdown_vals)
        {
            var tarray = ["owning","borrowing"];
            var ret = '';
            for(var i in tarray)
            {
                var type = tarray[i];
                for(var drop_type in dropdown_vals)
                {
                    var collect = 0;
                    var q_drop_type = drop_type;
                    if(jQuery("#filter_switcher_word").html() == 'Advanced' && drop_type == 'branch_basic')  // basic filter (only one)
                    {
                        collect = 1;
                        q_drop_type = 'branch';
                    }
                    else if(jQuery("#filter_switcher_word").html() != 'Advanced' && drop_type != 'branch_basic') // advanced filters
                    {
                        collect = 1;
                    }
                    if(collect)
                    {
                        var qstring = q_drop_type + "_" + type;
                        var dom = "#"+type+"_"+dropdown_vals[drop_type]['chooser'];
                        if(jQuery(dom).val() && jQuery(dom).val().length > 0)
                        {
                            ret += '&'+qstring+'=';
                            var a = jQuery(dom).val();
                            for(var j in a)
                            {
                                ret += a[j] + ',';
                            }
                            ret = ret.substring(0, ret.length - 1);
                        }
                    }
                }
            }
            return ret;
        }
        
        function getMultiSelectOptions(dropdown_vals)
        {
            // This function creates an array of all of the libraries that are included in the users selection
            // Handling the non-selections as ALL
            var tarray = ["owning","borrowing"];
            var ret = 
            {
                owning: [],
                borrowing: [],
            };
            for(var i in tarray)
            {
                var type = tarray[i];
                var somethingSpecified = 0;
                for(var drop_type in dropdown_vals)
                {
                    var qstring = drop_type + "_" + type;
                    var dom = "#"+type+"_"+dropdown_vals[drop_type]['chooser'];
                    if(jQuery(dom).val() && jQuery(dom).val().length > 0)
                    {
                        var a = jQuery(dom).val();
                        somethingSpecified = 1;
                        switch (drop_type)
                        {
                            case 'branch':
                                for(var j in a)
                                {
                                    ret[type].push(a[j]);
                                }
                            break;
                            default:
                                var associative = {};
                                for(var k in a)
                                {
                                    associative[a[k]] = 1;
                                }
                                for(var branch in branch_obj['branch_to_cluster'])
                                {
                                    for(var cluster_id in branch_obj['branch_to_cluster'][branch])
                                    {
                                        if(associative[cluster_id])
                                        {
                                            ret[type].push(branch);
                                        }
                                    }
                                }
                        }
                    }
                }
                if(!somethingSpecified) // All branches are included when no clusters, no systems, no branches are selected
                {
                    for(var branch in branch_obj['branch'])
                    {
                        ret[type].push(branch);
                    }
                }
            }
            return ret;
        }

        function bnl_init_date(data)
        {
            jQuery(".date_dropdown").each(function(){
                var parent_dom = jQuery(this).parent('.date_dropdown_wrapper');
                var display_date = jQuery(this).attr('pop');
                var tid = jQuery(this).attr('id');
                var oldest_date = moment(data['date_start'],'MM/YYYY');
                var oldest_months_back = oldest_date.diff(moment(),'months');
                var newest_date = moment(data['date_end'],'MM/YYYY');
                var newest_months_back = newest_date.diff(moment(),'months');
                bnlSetCookie( "" + jQuery(this).attr('pop'), "" + newest_date.format('MM/YYYY'), 100 );
                jQuery(this).MonthPicker(
                {
                    'MonthFormat': 'mm/yy',
                    'OnBeforeMenuClose': function(event){event.preventDefault();},
                    'Button': false,
                    'Position': {'of': parent_dom},
                    'AltField': display_date,
                    'MinMonth': oldest_months_back,
                    'MaxMonth': newest_months_back,
                    'SelectedMonth': newest_months_back,
                    OnAfterChooseMonth: function( selectedDate ){
                        console.log(jQuery(this).attr('id'));
                        console.log(jQuery(jQuery(this).attr('pop')).val());
                        bnl_check_date_selection(jQuery(this).attr('pop'));
                        }
                });
            });
            checkGetable();
        }

        function bnl_check_date_selection(changed_dom)
        {
            var changed_value = moment(jQuery(changed_dom).val(), 'MM/YYYY');
            console.log("Changed val: " + changed_value);
            var opposite = '';
            if(changed_dom.length > 0 && changed_dom.match(/from/) !== null)
            {
                opposite = moment(jQuery('#date_to').val(), 'MM/YYYY');
                if(opposite < changed_value)
                {
                    jQuery('#date_to').val(jQuery(changed_dom).val());
                    bnlSetCookie( '#date_to', jQuery(changed_dom).val(), 100 );
                }
            }
            else
            {
                opposite = moment(jQuery('#date_from').val(), 'MM/YYYY');
                if(opposite > changed_value)
                {
                    jQuery('#date_from').val(jQuery(changed_dom).val());
                    bnlSetCookie( '#date_from', jQuery(changed_dom).val(), 100 );
                }
            }
            bnlSetCookie( changed_dom, jQuery(changed_dom).val(), 100 );
            checkGetable();
        }

        function bnl_create_csv_download_link(title, bnl_table_dom)
        {
            var ret = "<div class = 'bnl_csv_download_link' table_dom = '"+bnl_table_dom+"' title = '"+title+"'>" +
            "<div class = 'bnl-download-icon glyphicon glyphicon-download'></div>"+
            "Download Spreadsheet</div>";
            return ret;
        }

        function bnl_wire(dom, order, maxCols = -1)
        {
            jQuery(".bnl_csv_download_link").each(function(){
                jQuery(this).unbind("click");
                jQuery(this).click(
                function()
                {
                    var bnl_table_dom  = "#" + jQuery(this).attr('table_dom');
                    var title = jQuery(this).attr('title');
                    if(jQuery(bnl_table_dom).length > 0)
                    {
                        var filestream = '';
                        var table = new jQuery.fn.dataTable.Api( bnl_table_dom );

                        // Get header (this will include hidden columns)
                        table.columns().every(function()
                        {
                            filestream += jQuery(this.header()).html() + ",";
                        });

                        filestream = filestream.substring(0, filestream.length - 1);
                        filestream += '\n';
                        var data = table.data().toArray();
                         
                        data.forEach(function(row, i)
                        {
                            row.forEach(function(column, j)
                            {
                                while(column.match(/['"]sort/))
                                {
                                    // Scrub out any HTML wrappers in the data
                                    column = column.replace(/^(.*?)(<.*?sort[^>]*?>[^<]*<[^>]*?>)(.*)/,'$1 $3').trim();
                                }
                                filestream += column + ",";
                            });
                            filestream = filestream.substring(0, filestream.length - 1);
                            filestream += '\n';
                        });
                        var e = document.createElement('a');
                        e.setAttribute('href','data:text/csv;charset=utf-8,' + encodeURIComponent(filestream));
                        e.setAttribute('download', title+".csv");
                        e.style.display = 'none';
                        document.body.appendChild(e);
                        e.click();
                        document.body.removeChild(e);
                    }
                    else
                    {
                        alert("Sorry, nothing to download");
                    }
                });
            });
            var thisTable = jQuery(dom).DataTable( {
                paging: true,
                lengthMenu: [ 25, 50, 100, 1000 ],
                'order': order
            } );
            if(maxCols > -1)
            {
                var hideThese = [];
                var data = thisTable.data().toArray();
                data.forEach(function(row, i)
                {
                    var cpos = 0;
                    if(i < 1)  // Only care about the columns
                    {
                        row.forEach(function(column, j)
                        {
                            if(cpos >= maxCols)
                            {
                                hideThese.push(cpos);
                            }
                            cpos++;
                        });
                    }
                });
                if(hideThese.length > 0)
                {
                    for(var i in hideThese)
                    {
                        thisTable.column(hideThese[i]).visible(false, false);
                    }
                    var warningMessage = "<div class='table_warning'>WARNING: " + hideThese.length + " Column(s) hidden from view. Download the CSV to see all data</div>";
                    jQuery(warningMessage).insertAfter(dom);
                    thisTable.columns.adjust().draw(false);
                }
            }
        }
        
        function disable_other_dropdowns(dom, dropdown_vals)
        {
            var empty = 1;
            dom = "#" + dom;
            var type = dom.match(/^([^_]*)_(.*)/);
            if(!type[1])
            {
                return;
            }
            type = type[1];
            jQuery(dom + " option:selected").each(function(){
                empty = 0;
            });
            
            for(var drop_type in dropdown_vals)
            {
                if(drop_type != 'branch_basic') // leave the basic search dropdown alone please
                {
                    var tdom = type+"_"+dropdown_vals[drop_type]['chooser'];
                    if(empty)
                    {
                        jQuery(tdom + "_chosen > input").prop("disabled","false");
                        jQuery(tdom + "_chosen > ul").css("display","");
                        jQuery(tdom + "_chosen").css("background-color","");
                        jQuery(tdom + "_chosen").css("height","");
                        jQuery(tdom + "_chosen").parent().children(".dropdown_menu_overlay").remove();
                    }
                    else
                    {
                        if(tdom != dom)
                        {
                            jQuery(tdom + "_chosen > input").prop("disabled","true");
                            jQuery(tdom + "_chosen > ul").css("display","none");
                            jQuery(tdom + "_chosen").css("background-color","grey");
                            jQuery(tdom + "_chosen").css("height","0px");
                            jQuery(tdom + "_chosen").parent().prepend("<div class='dropdown_menu_overlay'></div>");
                        }
                    }
                }
            }
        }
        
        function bnl_firsttimeinstructions()        
        {
            jQuery(".bnl_instructions").css("display","");
            jQuery(".bnl_instructions").show();
        }
        
        function bnl_show_hide()
        {
            if(jQuery(".bnl_instructions").css("display") == 'none')
            {
                jQuery(".bnl_instructions").show();
            }
            else
            {
                jQuery(".bnl_instructions").hide();
            }
        }

        function filter_show_hide()
        {
            if(jQuery("#filter_switcher_word").html() == 'Advanced')
            {
                jQuery(".bnl_basic_filter_container").addClass("hide");
                jQuery(".bnl_advanced_filter_container").removeClass("hide");
                jQuery("#filter_switcher_word").html("Basic");
            }
            else
            {
                jQuery(".bnl_advanced_filter_container").addClass("hide");
                jQuery(".bnl_basic_filter_container").removeClass("hide");
                jQuery("#filter_switcher_word").html("Advanced");
            }
            checkGetable();
        }

        function bnl_generate_branch_and_cluster_tables(lib_to_lib_dom, cluster_dom, dropdown_vals, includeZeros, startDate, endDate) // preserved just in case we want to put the cluster table back in
        {
            var branch_table_html = "";
            var cluster_table_html = "";
            jQuery(lib_to_lib_dom).html(' ');
            jQuery(lib_to_lib_dom).addClass('loader');
            jQuery(cluster_dom).html(' ');
            jQuery(cluster_dom).addClass('loader');
            
            var qstring = getMultiSelectOptionsForQueryString(dropdown_vals);
            console.log("Gathering from borrowing_n_lending_get?startdate="+startDate+"&enddate="+endDate+qstring);
            jQuery.get("borrowing_n_lending_get?startdate="+startDate+"&enddate="+endDate+qstring, function(data)
            {
                var selections = getMultiSelectOptions(dropdown_vals);
                if(data['amount_branch'])
                {
                    var used = 
                    {
                        owning: {},
                        borrowing: {}
                    }
                    branch_table_html = "<table id = 'bnl_branch_table'><thead><tr><th>Lending Library</th><th>Borrowing Library</th><th>Amount</th></tr></thead><tbody>";
                    for (var borrow_id in data['amount_branch'])
                    {
                        used['borrowing'][borrow_id] = 1;
                        for (var owning_id in data['amount_branch'][borrow_id])
                        {
                            used['owning'][owning_id] = 1;
                            branch_table_html = addHTMLRow('branch', branch_obj['branch'][owning_id], branch_obj['branch'][borrow_id], data['amount_branch'][borrow_id][owning_id], branch_table_html);
                        }
                        if(includeZeros)
                        {
                            for (var id_pos in selections['owning'])
                            {
                                if(!used['owning'][selections['owning'][id_pos]])
                                {
                                    // Need to introduce a "0" amount for non-present
                                    branch_table_html = addHTMLRow('branch', branch_obj['branch'][selections['owning'][id_pos]], branch_obj['branch'][borrow_id], '0', branch_table_html);
                                }
                            }
                        }
                    }
                    if(includeZeros)
                    {
                        for (var id_pos in selections['borrowing'])
                        {
                            if(!used['borrowing'][selections['borrowing'][id_pos]])
                            {
                                for(var id_pos_owning in selections['owning'])
                                {   
                                    // Need to introduce a "0" amount for non-present
                                    branch_table_html = addHTMLRow('branch', branch_obj['branch'][selections['owning'][id_pos_owning]], branch_obj['branch'][selections['borrowing'][id_pos]], '0', branch_table_html);
                                }
                            }
                        }
                    }
                    branch_table_html += "</tbody></table>";
                }
                if(data['amount_cluster'])
                {
                    cluster_table_html = "<table id = 'bnl_cluster_table'><thead><tr><th>Lending Cluster</th><th>Borrowing Cluster</th><th>Amount</th></tr></thead><tbody>";
                    for (var borrow_id in data['amount_cluster'])
                    {
                        for (var owning_id in data['amount_cluster'][borrow_id])
                        {
                            cluster_table_html = addHTMLRow('cluster', branch_obj['cluster'][owning_id]['name'], branch_obj['cluster'][borrow_id]['name'], data['amount_cluster'][borrow_id][owning_id], cluster_table_html);
                        }
                    }
                    cluster_table_html += "</tbody></table>";
                }

            }).done(function(){
                console.log("Finished loading branch_table");
                jQuery(lib_to_lib_dom).removeClass('loader');
                jQuery(lib_to_lib_dom).html(
                    "<h1>Library to Library</h1>"+
                    bnl_create_csv_download_link("Branch to Branch","bnl_branch_table")+
                    branch_table_html
                );
                bnl_wire("#bnl_branch_table");
                
                jQuery(cluster_dom).removeClass('loader');
                jQuery(cluster_dom).html(
                    "<h1>Cluster to Cluster</h1>"+
                    bnl_create_csv_download_link("Cluster to Cluster","bnl_cluster_table")+
                    cluster_table_html
                );
                bnl_wire("#bnl_cluster_table");
            });
        }
    }
    
});

