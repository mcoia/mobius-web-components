jQuery(document).ready(function()
{
    if(jQuery("#mobius_bnl_page_is_loaded").length > 0)
    {
        var branch_obj;
        bnl_get_seed_data('#bnl_filter_select_master_container', '#bnl_filter_branch');



        function bnl_get_seed_data(bnl_panel_dom, branch_select_dom, cluster_select_dom, region_select_dom)
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
                var branch_select = '';
                if(branch_obj['branch'] && branch_obj['branch_order'])
                {
                    owning_branch_select = '<select multiple id="owning_branch_multi_select" data-placeholder="Choose Branch(s)...">';
                    borrowing_branch_select = '<select multiple id="borrowing_branch_multi_select" data-placeholder="Choose Branch(s)...">';
                    for (var branch_pos in branch_obj['branch_order'])
                    {
                        owning_branch_select += '<option value="'+branch_obj['branch_order'][branch_pos]+'">'+branch_obj['branch'][branch_obj['branch_order'][branch_pos]]+'</option>\n';
                        borrowing_branch_select += '<option value="'+branch_obj['branch_order'][branch_pos]+'">'+branch_obj['branch'][branch_obj['branch_order'][branch_pos]]+'</option>\n';
                    }
                    owning_branch_select += '</select>';
                    borrowing_branch_select += '</select>';
                    jQuery(branch_select_dom+"_owning").html(owning_branch_select);
                    jQuery(branch_select_dom+"_borrowing").html(borrowing_branch_select);
                    jQuery('#owning_branch_multi_select').chosen();
                    jQuery('#borrowing_branch_multi_select').chosen();
                }
            });
        }


        function bnl_generate_branch_table(branch_dom,cluster_dome)
        {
            var branch_table_html = "";
            var cluster_table_html = "";
            jQuery(branch_dom).html(' ');
            jQuery(branch_dom).addClass('loader');
            jQuery(cluster_dome).html(' ');
            jQuery(cluster_dome).addClass('loader');
            jQuery.get("borrowing_n_lending_get?dateto=2020-03&datefrom=2020-01", function(ob)
            {
                if(ob['amount_branch'])
                {
                    branch_table_html = "<table id = 'bnl_branch_table'><thead><tr><th>Owning Library</th><th>Borrowing Library</th><th>Amount</th></tr></thead><tbody>";
                    for (var borrow_id in ob['amount_branch'])
                    {
                        for (var owning_id in ob['amount_branch'][borrow_id])
                        {
                            branch_table_html += "<tr>";
                            branch_table_html += "<td class='bnl_branch_table_owning_lib'>"+ob['branch'][owning_id]+"</td>\n";
                            branch_table_html += "<td class='bnl_branch_table_borrowing_lib'>"+ob['branch'][borrow_id]+"</td>\n";
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
                            cluster_table_html += "<td class='bnl_branch_table_owning_lib'>"+ob['cluster'][owning_id]+"</td>\n";
                            cluster_table_html += "<td class='bnl_branch_table_borrowing_lib'>"+ob['cluster'][borrow_id]+"</td>\n";
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
        
        
        jQuery('#bnl_submit_button').click(function(){
             bnl_generate_branch_table('#bnl_branch_div','#bnl_cluster_div');
        });



    }
});

