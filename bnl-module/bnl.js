jQuery(document).ready(function()
{
    if(jQuery("#mobius_bnl_page_is_loaded").length > 0)
    {
        var branch_obj;
        var dropdown_vals = 
        {
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
            if(jQuery("#daterange").val().length > 0)
            {
                if(jQuery("#daterange").val().length > 0 && jQuery("#daterange").val().match(/\d{2}\/\d{4}\s\-\s\d{2}\/\d{4}/) !== null)
                {
                    jQuery("#bnl_submit_button").removeClass('bnl_submit_not_allowed');
                    jQuery('#bnl_submit_button').click(function(){
                        bnl_generate_data('#bnl_branch_div', '#bnl_cluster_div', '#bnl_owning_summary_div', '#bnl_borrowing_summary_div' ,dropdown_vals);
                    });
                }
                else
                {
                    jQuery('#bnl_submit_button').unbind("click");
                }
            }
        }
        function bnlGetCookie(cname) {
            var name = cname + "=";
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
            var finalc = cname + "="
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
                
                // fill in the date ranges available in the data
                jQuery.get("borrowing_n_lending_get?get_data_date_range=1", function(data)
                {
                    jQuery("#data_date_start").html(data['date_start']);
                    jQuery("#data_date_end").html(data['date_end']);
                });

                var tarray = ['owning','borrowing'];
                if(branch_obj['branch'] && branch_obj['branch_order'])
                {
                    for(var i in tarray)
                    {
                        var type = tarray[i];
                        var selectHTML = '<select multiple id="'+type+'_'+dropdown_vals['branch']['chooser']+'" data-placeholder="'+dropdown_vals['branch']['placeholder']+'(s)...">';
                        for (var branch_pos in branch_obj['branch_order'])
                        {
                            selectHTML += '<option value="'+branch_obj['branch_order'][branch_pos]+'">'+branch_obj['branch'][branch_obj['branch_order'][branch_pos]]+'</option>\n';
                        }
                        selectHTML += '</select>';
                        jQuery(dropdown_vals['branch']['dom']+"_"+type).html(selectHTML);
                        jQuery('#'+type+'_'+dropdown_vals['branch']['chooser']).chosen().change(
                        function(data)
                        {
                            disable_other_dropdowns(data.currentTarget.id,dropdown_vals);
                        });
                    }
                }
                if(branch_obj['cluster'])
                {
                    for(var i in tarray)
                    {
                        var type = tarray[i];
                        var selectHTML_cluster = '<select multiple id="'+type+'_'+dropdown_vals['cluster']['chooser']+'" data-placeholder="'+dropdown_vals['cluster']['placeholder']+'(s)...">';
                        var selectHTML_system = '<select multiple id="'+type+'_'+dropdown_vals['system']['chooser']+'" data-placeholder="'+dropdown_vals['system']['placeholder']+'(s)...">';
                        for (var cluster in branch_obj['cluster'])
                        {
                            if(branch_obj['cluster'][cluster]['type'] == 'sierra')
                            {
                                selectHTML_cluster += '<option value="'+cluster+'">'+branch_obj['cluster'][cluster]['name']+'</option>\n';
                            }
                            else
                            {
                                selectHTML_system += '<option value="'+cluster+'">'+branch_obj['cluster'][cluster]['name']+'</option>\n';
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
                        });
                        jQuery('#'+type+'_'+dropdown_vals['system']['chooser']).chosen().change(
                        function(data)
                        {
                            disable_other_dropdowns(data.currentTarget.id,dropdown_vals);
                        });
                    }
                }
                bnl_init_date();
                checkGetable();
            });
            jQuery("#firsttimebutton").click(function(){ bnl_firsttimeinstructions();});
            jQuery("#instructions_show_hide_a").click(function(){ bnl_show_hide();});
        }

        function bnl_generate_data(branch_dom, cluster_dom, owning_dom, borrowing_dom, dropdown_vals)
        {
            var includeZeros = jQuery("#show_zeros").is(':checked');
            var startDate = bnlGetCookie('bnl_start_date');
            var endDate = bnlGetCookie('bnl_end_date');
            if(startDate && endDate)
            {
                startDate = moment(startDate, 'MM/DD/YYYY').format('YYYY-MM');
                endDate = moment(endDate, 'MM/DD/YYYY').format('YYYY-MM');
                bnl_generate_date_summary_tables(owning_dom, borrowing_dom, dropdown_vals, startDate, endDate)
                bnl_generate_branch_and_cluster_tables(branch_dom, cluster_dom, dropdown_vals, includeZeros, startDate, endDate);
            }
        }

        function bnl_generate_date_summary_tables(owning_dom, borrowing_dom, dropdown_vals, startDate, endDate)
        {
            var owning_table_html = "";
            var borrowing_table_html = "";
            jQuery(owning_dom).html(' ');
            jQuery(owning_dom).addClass('loader');
            jQuery(borrowing_dom).html(' ');
            jQuery(borrowing_dom).addClass('loader');
            var types =
                {
                    lent: {
                            dom: owning_dom,
                            table_dom: 'bnl_owning_summary_table',
                            th_lib_head: 'Owning Library',
                            th_total_head: 'Lent Total',
                            table_h1: 'Owning Summary',
                            total: 0,
                            html: ''
                        },
                    borrow: {
                            dom: borrowing_dom,
                            table_dom: 'bnl_borrowing_summary_table',
                            th_lib_head: 'Borrowing Library',
                            th_total_head: 'Borrow Total',
                            table_h1: 'Borrowing Summary',
                            total: 0,
                            html: ''
                        }
                }

            var qstring = getMultiSelectOptionsForQueryString(dropdown_vals);
            console.log("Gathering from borrowing_n_lending_get?datesummary=1&startdate="+startDate+"&enddate="+endDate+qstring);
            jQuery.get("borrowing_n_lending_get?datesummary=1&startdate="+startDate+"&enddate="+endDate+qstring, function(data)
            {
                for(var type in types)
                {
                    if(data[type])
                    {
                        types[type]['html'] = "<table id = '"+types[type]['table_dom']+"'><thead><tr><th>"+types[type]['th_lib_head']+"</th><th>Month</th><th>"+types[type]['th_total_head']+"</th></tr></thead><tbody>";
                        for (var date in data[type])
                        {
                            for (var lib in data[type][date])
                            {
                                types[type]['html'] = addHTMLRow(type, branch_obj['branch'][lib], date, data[type][date][lib], types[type]['html']);
                                types[type]['total']+=data[type][date][lib];
                            }
                        }
                        types[type]['html'] += "</tbody></table>";
                    }
                }
            }).done(function(){
                console.log("Finished loading branch_table");
                for(var type in types)
                {
                    jQuery(types[type]['dom']).removeClass('loader');
                    var thishtml = 
                        "<h1>"+types[type]['table_h1']+"</h1>"+
                        bnl_create_csv_download_link(types[type]['table_h1'],types[type]['table_dom'])+
                        types[type]['html'] +
                        "<h2>Total: "+types[type]['total']+"</h2>";
                    jQuery(types[type]['dom']).html(thishtml);
                    bnl_wire("#"+types[type]['table_dom']);
                }
            });
        }

        function bnl_generate_branch_and_cluster_tables(branch_dom, cluster_dom, dropdown_vals, includeZeros, startDate, endDate)
        {
            var branch_table_html = "";
            var cluster_table_html = "";
            jQuery(branch_dom).html(' ');
            jQuery(branch_dom).addClass('loader');
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
                    branch_table_html = "<table id = 'bnl_branch_table'><thead><tr><th>Owning Library</th><th>Borrowing Library</th><th>Amount</th></tr></thead><tbody>";
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
                    cluster_table_html = "<table id = 'bnl_cluster_table'><thead><tr><th>Owning Cluster</th><th>Borrowing Cluster</th><th>Amount</th></tr></thead><tbody>";
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
                jQuery(branch_dom).removeClass('loader');
                jQuery(branch_dom).html(
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
                    var qstring = drop_type + "_" + type;
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

        function bnl_init_date()
        {
            jQuery("#daterange").daterangepicker({
                opens: 'left',
                maxDate: moment(),
                autoApply: true,
                ranges: {
                   'Last Month': [moment().subtract(1, 'month').startOf('month'), moment().subtract(1, 'month').endOf('month')],
                   'Two Months Ago': [moment().subtract(2, 'month').startOf('month'), moment().subtract(2, 'month').endOf('month')],
                   'Three Months Ago': [moment().subtract(3, 'month').startOf('month'), moment().subtract(3, 'month').endOf('month')],
                   'Four Months Ago': [moment().subtract(4, 'month').startOf('month'), moment().subtract(4, 'month').endOf('month')]
                }
              }, function(start, end, label) {
                    console.log("A new date selection was made: " + start.format('YYYY-MM-DD') + ' to ' + end.format('YYYY-MM-DD'));
                    bnlSetCookie('bnl_start_date',start.format('MM/DD/YYYY'),100);
                    bnlSetCookie('bnl_end_date',end.format('MM/DD/YYYY'),100);
                    checkGetable();
                  });

            jQuery("#daterange").on('apply.daterangepicker', function(ev, picker) {
            jQuery(this).val(picker.startDate.format('MM/YYYY') + ' - ' + picker.endDate.format('MM/YYYY'));
              });

            jQuery("#daterange").on('cancel.daterangepicker', function(ev, picker) {
                  jQuery(this).val('');
              });
            var startDate = bnlGetCookie('bnl_start_date');
            var endDate = bnlGetCookie('bnl_end_date');
            if(startDate && endDate)
            {
                jQuery("#daterange").data('daterangepicker').setStartDate(startDate);
                jQuery("#daterange").data('daterangepicker').setEndDate(endDate);
                jQuery("#daterange").val(moment(startDate, 'MM/DD/YYYY').format('MM/YYYY') + " - " + moment(endDate, 'MM/DD/YYYY').format('MM/YYYY'));
            }
        }
        
        function bnl_create_csv_download_link(title, bnl_table_dom)
        {
            var ret = "<div class = 'bnl_csv_download_link' table_dom = '"+bnl_table_dom+"' title = '"+title+"'>" +
            "<div class = 'bnl-download-icon glyphicon glyphicon-download'></div>"+
            "Download Spreadsheet</div>";
            return ret;
        }

        function bnl_wire(dom)
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
                        // Get header
                        jQuery(bnl_table_dom).find('tr > th').each(function(){
                            filestream += jQuery(this).html()+",";
                        });
                        filestream = filestream.substring(0, filestream.length - 1);
                        filestream += '\n';
                        
                        var table = new jQuery.fn.dataTable.Api( bnl_table_dom );
                        var data = table.data().toArray();
                         
                        data.forEach(function(row, i) {
                              row.forEach(function(column, j) {
                                filestream += column + ",";
                              });
                            filestream = filestream.substring(0, filestream.length - 1);
                            filestream += '\n';
                        });
                        // jQuery(bnl_table_dom).find('tr').each(function(){
                            // jQuery(this).find('td').each(function(){
                                // filestream += jQuery(this).html()+",";
                            // });
                            // filestream = filestream.substring(0, filestream.length - 1);
                            // filestream += '\n';
                        // });
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
            jQuery(dom).DataTable( {
                paging: true,
                lengthMenu: [ 25, 50, 100, 1000 ]
            } );
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
                var tdom = type+"_"+dropdown_vals[drop_type]['chooser'];
                if(empty)
                {
                    jQuery(tdom + "_chosen > input").prop("disabled","false");
                    jQuery(tdom + "_chosen > ul").css("display","");
                    jQuery(tdom + "_chosen").css("background-color","");
                    jQuery(tdom + "_chosen").css("height","");
                }
                else
                {
                    if(tdom != dom)
                    {
                        jQuery(tdom + "_chosen > input").prop("disabled","true");
                        jQuery(tdom + "_chosen > ul").css("display","none");
                        jQuery(tdom + "_chosen").css("background-color","grey");
                        jQuery(tdom + "_chosen").css("height","20px");
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

    }
});

