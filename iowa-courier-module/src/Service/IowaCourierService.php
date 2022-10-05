<?php

namespace Drupal\iowacourier\Service;

use Drupal\Component\Serialization\Json;

class IowaCourierService {

  public function __construct() {
  }

  public function mobius_iowacourier_getColumns() {
    $ret = [];
    $database = \Drupal::database();
    $query = $database->query("SELECT * FROM iowa_courier_staging where id = -1");
    $rows = $query->fetchAll();
    foreach (JSON::decode(JSON::encode($rows), TRUE) as $r) {
      foreach ($r as $key => $value) {
        $ret[$key] = $value ? $value : $key;
      }
    }
    return $ret;
  }

  public function mobius_iowacourier_generateHTMLTable() {
    $colMap = $this->mobius_iowacourier_getColumns();
    $ret = "<table id='iowa_courier_display_table'><thead><tr>";
    $colOrder = "";

    # Hard coded display columns. The rest are javascript displayed
    $displayOrder = [
      "library_name",
      "county",
      "city",
      "hub",
      "hub_city",
      "day",
      "route",
      "stat_courier_pick_up_schedule",
      "delivery_code",
    ];

    $militaryColumns = [
      "stat_courier_pick_up_schedule",
    ];
    $militaryColumnsNOAMPM = [
      // "monday_hours",
      // "tuesday_hours",
      // "wednesday_hours",
      // "thursday_hours",
      // "friday_hours",
      // "saturday_hours",
      // "sunday_hours"
    ];

    $javascriptColumns = [
      "library_name" => "IOWACourierLibraryClick",
      "route" => "IOWACourierRouteClick",
    ];

    $javascriptRemoveColumns = [
      "contact_card",
      "id",
      "hours",
      "num",
      "nid",
      "changed",
      "size_code",
      "knackid",
    ];

    $javascriptUIDetails = [
      "groups" =>
        [
          "Library Info" => [
            "mailing_address",
            "physical_location_street_address",
            "library_telephone_number",
            "library_email_address",
            "fax_number",
            "web_address_url",
            "monday_hours",
            "tuesday_hours",
            "wednesday_hours",
            "thursday_hours",
            "friday_hours",
            "saturday_hours",
            "sunday_hours",
          ],
          "Courier Info" => [
            "silo_code",
            "delivery_code",
            "physical_address",
            "hub",
            "route",
            "hub_city",
            "day",
            "stat_courier_pick_up_schedule",
            "number_of_bags",
          ],
          "Contacts" => [
            "directoradministrator",
            "director_email_address",
            "assistant_director",
            "assistant_director_email_address",
            "ill_contact",
            "ill_email_address",
            "ill_phone_number",
            "ill_fax_number",
            "childrens_services_librarian",
            "childrens_services_email_address",
            "teen_services_librarian",
            "teen_services_librarian_email",
          ],
        ],
      "group_order" => ["Library Info", "Courier Info", "Contacts"],
      "title_field" => "library_name",
    ];

    foreach ($displayOrder as $col) {
      $ret .= "<th>" . $colMap[$col] . "</th>";
      $colOrder .= $col . ",";
    }
    foreach ($colMap as $key => $value) {
      if (!in_array($key, $displayOrder)) {
        $colOrder .= $key . ",";
      }
    }
    $colOrder = substr($colOrder, 0, -1);

    $ret .= "</tr></thead><tbody>";
    $metadata = [];

    $database = \Drupal::database();
    $query = $database->query("SELECT $colOrder FROM iowa_courier_staging where id > -1 and library_name is not null and route is not null");
    $rows = $query->fetchAll();

    foreach (json_decode(json_encode($rows), TRUE) as $libraryRow) {
      $ret .= "<tr>";

      $metadata[$libraryRow["id"]] = [];
      foreach ($libraryRow as $key => $value) {
        $finalValue = in_array($key, $militaryColumns) ? $this->mobius_iowacourier_figureMilitary($value, 0) : $value;
        $finalValue = in_array($key, $militaryColumnsNOAMPM) ? $this->mobius_iowacourier_figureMilitary($finalValue, 1) : $finalValue;

        if (in_array($key, $displayOrder)) {
          $ret .= "<td libid='" . $libraryRow["id"] . "'>";
          $ending = "";
          if (isset($javascriptColumns[$key])) {
            $ret .= "<a class='" . $javascriptColumns[$key] . "' onclick ='" . $javascriptColumns[$key] . "(this)' href='#' >";
            $ending = "</a>";
          }
          $ret .= "$finalValue$ending</td>";
        }
        $metadata[$libraryRow["id"]][$key] = $finalValue;
      }
      $ret .= "</tr>";
    }
    $ret .= "</tbody></table>
    <div style='display: none'>";
    foreach ($metadata as $key => $value) {
      $ret .= "<div class = 'library-hidden-data' id='iowacourier-metadata-$key'>\n";
      foreach ($value as $int => $intval) {
        if (!(in_array($int, $javascriptRemoveColumns))) {
          $ret .= "<span metaname = '$int' title ='" . $this->mobius_iowacourier_escape($colMap[$int]) . "'>$intval</span>\n";
        }
      }
      $ret .= "</div>\n";
    }
    $ret .= "</div><script type='text/javascript'>
<!--//--><![CDATA[//><!--
    var displayGrouping = JSON.parse('{ ";
    foreach ($javascriptUIDetails["groups"] as $groupName => $list) {
      $ret .= "\"$groupName\" : [";
      foreach ($list as $item) {
        $ret .= "\"$item\",";
      }
      $ret = substr($ret, 0, -1);
      $ret .= "],";
    }
    $ret = substr($ret, 0, -1);
    $ret .= "}');
    var displayGroupingOrder = JSON.parse('[ ";
    foreach ($javascriptUIDetails["group_order"] as $groupName) {
      $ret .= "\"$groupName\",";
    }
    $ret = substr($ret, 0, -1);
    $ret .= "]');
    var displayTitleField = '" . $javascriptUIDetails["title_field"] . "';
//    --><!]]>
    </script>";
    return $ret;
  }

  public function mobius_iowacourier_escape($val) {
    return str_replace("'", "", $val);
  }

  public function mobius_iowacourier_figureMilitary($val, $removeAMPM) {
    $val = trim($val);
    if (strlen($val) < 3) {
      return $val;
    }

    $each = [$val];
    if ((strpos($val, ' ') !== FALSE)) // There could be a time "range" expressed with a space
    {
      $each[0] = explode(' ', $val);
    }
    $ret = "";
    foreach ($each as $inter => $frag) {
      if (is_array($frag)) {
        foreach ($frag as $int => $low) {
          if (strpos($low, '-') !== FALSE) {
            $pair = explode('-', $low);
            $ret .= $this->mobius_iowacourier_convertFromMilitary($pair[0], $removeAMPM);
            $ret .= "-" . $this->mobius_iowacourier_convertFromMilitary($pair[1], $removeAMPM);
          }
          else {
            $ret .= $this->mobius_iowacourier_convertFromMilitary($low, $removeAMPM);
          }
          $ret .= " , ";
        }
        $ret = substr($ret, 0, -3);
      }
      else {
        $pair = explode('-', $frag);
        foreach ($pair as $key => $value) {
          $ret .= "-" . $this->mobius_iowacourier_convertFromMilitary($value, $removeAMPM);
        }
        $ret = substr($ret, 1);
      }
    }


    return $ret;
  }

  public function mobius_iowacourier_convertFromMilitary($val, $removeAMPM) {
    $val = trim($val);
    // Strip non numerics
    $val = preg_replace('/[^\d]/', '', $val);
    $am = "am";
    if ($val >= 1200) {
      $am = "pm";
    }
    if ($val >= 1300) {
      $val -= 1200;
    }

    $minute = substr($val, -2, 2);
    $hour = preg_replace('/(\d+?)\d\d$/', '$1', $val);
    if (substr($hour, 0, 1) == "0") {
      $hour = substr($hour, 1);
    }

    $ret = $hour . ':' . $minute;
    if (!$removeAMPM) {
      $ret .= $am;
    }
    return $ret;
  }


}
