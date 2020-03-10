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
            if(jQuery("#daterange").val().length > 0)
            {
                if(jQuery("#daterange").val().match(/\d{2}\/\d{4}\s\-\s\d{2}\/\d{4}/).length > 0)
                {
                    jQuery("#bnl_submit_button").removeClass('bnl_submit_not_allowed');
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
            jQuery.get("borrowing_n_lending_get?get_branches=1", function(ob)
            {
                branch_obj = ob;
            }).done(function()
            {
                jQuery(bnl_panel_dom).removeClass('loader');
                jQuery(bnl_panel_dom).html(saveHTML);
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
                        jQuery('#'+type+'_'+dropdown_vals['branch']['chooser']).chosen();
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
                        jQuery('#'+type+'_'+dropdown_vals['cluster']['chooser']).chosen();
                        jQuery('#'+type+'_'+dropdown_vals['system']['chooser']).chosen();
                    }
                }
                bnl_init_date();
                jQuery('#bnl_submit_container').click(function(){
                     bnl_generate_branch_table('#bnl_branch_div', '#bnl_cluster_div', dropdown_vals);
                });
            });
        }

        function bnl_generate_branch_table(branch_dom, cluster_dome, dropdown_vals)
        {
            var branch_table_html = "";
            var cluster_table_html = "";
            var startDate = bnlGetCookie('bnl_start_date');
            var endDate = bnlGetCookie('bnl_end_date');
            if(startDate && endDate)
            {
                jQuery(branch_dom).html(' ');
                jQuery(branch_dom).addClass('loader');
                jQuery(cluster_dome).html(' ');
                jQuery(cluster_dome).addClass('loader');
                startDate = moment(startDate, 'MM/DD/YYYY').format('YYYY-MM');
                endDate = moment(endDate, 'MM/DD/YYYY').format('YYYY-MM');
                var qstring = getMultiSelectOptionsForQueryString(dropdown_vals);
                console.log("Gathering from borrowing_n_lending_get?startdate="+startDate+"&enddate="+endDate+qstring);
                jQuery.get("borrowing_n_lending_get?startdate="+startDate+"&enddate="+endDate, function(ob)
                {
                    if(ob['amount_branch'])
                    {
                        var used = 
                        {
                            owning: [],
                            borrowing: []
                        }
                        branch_table_html = "<table id = 'bnl_branch_table'><thead><tr><th>Owning Library</th><th>Borrowing Library</th><th>Amount</th></tr></thead><tbody>";
                        for (var borrow_id in ob['amount_branch'])
                        {
                            for (var owning_id in ob['amount_branch'][borrow_id])
                            {
                                branch_table_html += "<tr>";
                                branch_table_html += "<td class='bnl_branch_table_owning_lib'>"+branch_obj['branch'][owning_id]+"</td>\n";
                                branch_table_html += "<td class='bnl_branch_table_borrowing_lib'>"+branch_obj['branch'][borrow_id]+"</td>\n";
                                branch_table_html += "<td class='bnl_branch_table_borrowing_lib'>"+ob['amount_branch'][borrow_id][owning_id]+"</td>\n";
                                branch_table_html += "</tr>";
                            }
                        }
                        branch_table_html += "</tbody></table>";
                    }
                    if(ob['amount_cluster'])
                    {
                        cluster_table_html = "<table id = 'bnl_cluster_table'><thead><tr><th>Owning Cluster</th><th>Borrowing Cluster</th><th>Amount</th></tr></thead><tbody>";
                        for (var borrow_id in ob['amount_cluster'])
                        {
                            for (var owning_id in ob['amount_cluster'][borrow_id])
                            {
                                cluster_table_html += "<tr>";
                                cluster_table_html += "<td class='bnl_branch_table_owning_lib'>"+branch_obj['cluster'][owning_id]['name']+"</td>\n";
                                cluster_table_html += "<td class='bnl_branch_table_borrowing_lib'>"+branch_obj['cluster'][borrow_id]['name']+"</td>\n";
                                cluster_table_html += "<td class='bnl_branch_table_borrowing_lib'>"+ob['amount_cluster'][borrow_id][owning_id]+"</td>\n";
                                cluster_table_html += "</tr>";
                            }
                        }
                        cluster_table_html += "</tbody></table>";
                    }

                }).done(function(){
                    console.log("Finished loading branch_table");
                    jQuery(branch_dom).removeClass('loader');
                    jQuery(branch_dom).html("<h1>Branch to Branch</h1>"+branch_table_html);
                    jQuery("#bnl_branch_table").DataTable( {
                           paging: true,
                           lengthMenu: [  25, 50, 100, 1000  ]
                       } );
                    jQuery(cluster_dome).removeClass('loader');
                    jQuery(cluster_dome).html("<h1>Cluster to Cluster</h1>"+cluster_table_html);
                    jQuery("#bnl_cluster_table").DataTable( {
                           paging: true,
                           lengthMenu: [ 25, 50, 100, 1000 ]
                       } );
                    });
            }
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
            var tarray = ["owning","borrowing"];
            var ret = 
            {
                owning: [],
                borrowing: [],
            };
            for(var i in tarray)
            {
                var type = tarray[i];
                for(var drop_type in dropdown_vals)
                {
                    var qstring = drop_type + "_" + type;
                    var dom = "#"+type+"_"+dropdown_vals[drop_type]['chooser'];
                    if(jQuery(dom).val() && jQuery(dom).val().length > 0)
                    {
                        var a = jQuery(dom).val();
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
                    else // no selection means all
                    {
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



    }
});

