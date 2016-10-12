<?php
drupal_add_js('http://dev.jquery.com/view/trunk/plugins/validate/jquery.validate.js','external');
print '<script>
$(document).ready(function(){
  $("#labelForm").validate();
});
</script>
<script type="text/javascript" src="//ajax.googleapis.com/ajax/libs/jquery/1.11.0/jquery.min.js"></script>
<script type="text/javascript">
var $jq = jQuery.noConflict();
</script>';

//this function makes a select list for the form below. it is used twice, once for the FROM list and once for the TO list
function make_a_select_list ($list_name, $list_label, $select_multiple="", $institutions, $required='') {
  $mco_last_from_id = $_COOKIE['labelFrom'];
  
  
  
  //query the database label_maker_nodes 
  $query = "SELECT * FROM label_maker_nodes ORDER BY locName";
  $result = db_query($query);
  //$institutions = db_fetch_array($result);
  print_r($institutions);
  
  // begin the select list
  $list_code = "<p>$list_label Address:   <em><small>(required)</small></em></p><select style='width:50em;' class='$required chosen-select'";
  
  if ( $select_multiple == "" ) {
    $list_code .= "name='$list_name' id='$list_name' data-placeholder='Select a FROM address' tabindex='1'>\n";
    $list_code .= "<option value></option>\n";
  } else {
    $list_code .= "$select_multiple name='$list_name"."[]"."' id='$list_name' size='10' data-placeholder='Click and/or start typing to choose one or more TO addresses' tabindex='2'>\n";
  }
  
  // loop through all the institutions and add them to the list box
  while ($institution = db_fetch_array($result)) {
    //foreach($institutions as $institution) {
    
    $list_code = $list_code . "<option ";
    
    $institutionID = $institution["id"];
    $name = $institution["locName"];
    if (!$institution["is_stop"]) {
      $name .= " (Delivers to ".$institution["address1"];
    } else {
      $name .=" (" . $institution["state"] . ": " . $institution['locCode'];
    }
    // Uncomment this if MCDAC wants to see OCLC symbols in there
    if ($institution["oclcSymbol"]) {
      $name .=  " OCLC: " . $institution["oclcSymbol"] . ")";
    } else {
      $name .= ")";
    }
    $state = $institution["state"];
    
    // check to see if the mco_last_from_id cookie equals this node id
    if ( $list_label == "FROM" && $mco_last_from_id == $institutionID ) {
      $list_code = $list_code . "selected ";
    }
    
    $list_code = $list_code . "value='$institutionID' class='$state'>$name</option>\n";
  }
  
  #end the select list
  $list_code= $list_code . "</select>";
  
  #return the select list
  return($list_code);
  
}
//print the two select lists, FROM and TO
print '
<div class="messages">If this is your first time here, please <a href="#instructions">read the instructions</a>.</div>
<form id="labelForm" name="control_panel" method="post" action="/label_maker_3.php">';

print make_a_select_list("from_id", "FROM", "", $institutions,"required");
print make_a_select_list("to_id","TO","multiple", $institutions,"required");
print '
<br /><label for="quantity">Number of labels for each "To:" address:</label><br />
<input class="text" type="text" name="quantity" id="quantity" value="1" style="width:40px;" tabindex="3"/>
<p>If you would like to print a full page, enter "4". Selecting multiple "To:" addresses will then generate full pages of each location. <strong>Important!</strong> Only print 1 copy of the resulting file, and do not make photocopies of labels. The barcodes generated are unique in the system, and creating duplicate barcodes will cause problems. If you would like, for instance, 3 pages of the same label, enter "12". Want 4 pages? Enter "16". And so on.</p>
<input id="submit_label" name="submit" type="submit" value="Make Labels" onClick="pageTracker._trackEvent(\'Tools\',\'LabelMaker\', \'LabelMaker Submit\');" >
</form>';

//print until you reach the end of everything
print '
<h2><a name="instructions"></a>Instructions</h2>

<ol>
<li>Select your institution name in the first dropdown menu. The dropdown presents a search box to filter the results, and the form will remember your last selection.</li>
<li>Select as many destination names as you wish in the second box, the "To:" section. Clicking on the field will show a list of all available libraries. Begin typing the name of the library or it\'s short code to narrow the list. Once you locate the library, clicking the name will add it to the list of libraries you are making labels for. If you would like to remove a library, click the "X" to the right of it\'s name. (The list can also be driven purely by keyboard, but that exercise is left to the reader)</li>
<li>Enter the number of labels you would like to print for each location selected in the "To:" box.</li>
<li>When you are done with your selections, click the "Make Labels" button.</li>
</ol>

<h3>What happens when I click the "Make Labels" button?</h3>

<p>When you click the "Make Labels" button, a PDF will be generated based on your selection. The PDF will be directed to your browser.</p>

<p><a href="http://en.wikipedia.org/wiki/List_of_PDF_software">List of pdf software</a></p>

<h3>Label Size</h3>
<p>This application generates a 2x2 grid of labels on 11inx8.5in(landscape letter) paper.</p>

<div class="messages">If you encounter any difficulty in using this form, please <a href="mailto:help@mobiusconsortium.org?subject=Label%20maker%20issue">submit a helpdesk ticket</a>.</div>
<script type="text/javascript" src="/sites/all/libraries/chosen/chosen.jquery.js"></script>
<script type="text/javascript">
$jq(".chosen-select").chosen({search_contains: true});
</script>
';

?>

