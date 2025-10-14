<?php /** @noinspection PhpArrayShapeAttributeCanBeAddedInspection */

namespace Drupal\labelmaker\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Component\Serialization\Json;

class LabelMakerController extends ControllerBase {

  public function __construct() {
  }

  public function getInstitutionalListFromDatabase() {

    $database = \Drupal::database();
    $query = $database->query("SELECT * FROM label_maker_nodes ORDER BY locName");
    $rows = $query->fetchAllAssoc('id');
    return $rows;

  }

  // HTML Element, This is our select form element.
  private function buildSelectFormElement($list_name, $list_label, $select_multiple = "", $required = ''): string {


//    $mco_last_from_id = 0;
//    if (isset($_COOKIE['label-from'])) {
//      $mco_last_from_id = $_COOKIE['label-from'];
//    }

    $institutions = $this->getInstitutionalListFromDatabase();

    // begin the select list
    $html = "<p>$list_label Address: <em><small>(required)</small></em></p><select class='$required chosen-select form-control'";

    if ($select_multiple == "") {
      $html .= "name='$list_name' id='$list_name' data-placeholder='Select a FROM address' tabindex='1'>\n";
      $html .= "<option value></option>\n";
    }
    else {
      $html .= "$select_multiple name='$list_name" . "[]" . "' id='$list_name'
      data-placeholder='Click and/or start typing to choose one or more TO addresses' tabindex='2'>\n";
    }

    $InstitutionListEncodedJSON = Json::encode($institutions);
    $InstitutionListDecodedJSON = Json::decode($InstitutionListEncodedJSON, TRUE);

    /* Loop over our Institution list and build the <option> elements. */
    foreach ($InstitutionListDecodedJSON as $institution) {

      $thisOption = "<option ";

      $institutionID = $institution["id"];
      $name = $institution["locName"];
      $permittedTo = str_replace("'", "", $institution["permittedTo"]);
      $interSort = str_replace("'", "", $institution["interSort"]);
      $locCode = str_replace("'", "", $institution["locCode"]);
      $state = str_replace("'", "", $institution["state"]);
      $oclcSymbol = str_replace("'", "", $institution["oclcSymbol"]);

      // The dropdown name pattern is:
      // locName (state) (oclcSymbol)
      // But only if the state exists and the oclcSymbol exists, omit otherwise

      if($state && strcmp( trim($state), '') != 0) {
        $name .= " ($state)";
      }
      if($oclcSymbol && strcmp( trim($oclcSymbol), '') != 0) {
        $name .= " ($oclcSymbol)";
      }
      if($locCode && strcmp( trim($locCode), '') != 0) {
        $name .= " ($locCode)";
      }


      // Set our FROM in our dropdown based off our cookie value - check to see if the mco_last_from_id cookie equals this node id
      //      if ($list_label == "FROM" && $mco_last_from_id == $institutionID) {
//      if (strcmp($list_label, "FROM") == 0 && (int) $mco_last_from_id == (int) $institutionID) {
//        $html = $html . " selected ";
//      }

      $thisOption = $thisOption . "data-permitted-to='$permittedTo' ";
      $thisOption = $thisOption . "data-intersort='$interSort' ";
      $thisOption = $thisOption . "value='" . Json::encode($institution) . "' ";
      $thisOption = $thisOption . "class='$state'";
      $thisOption = $thisOption . ">$name</option>\n";

      $html = $html . $thisOption;
    }

    #end the select list
    $html = $html . "</select>";

    #return the select list
    return $html;

  }

  public function getTwigTemplate(): array {

    $labelMakerAbsolutePath = \Drupal::service('extension.list.module')
      ->getPath('labelmaker');

    $institutions = $this->getInstitutionalListFromDatabase();

    // this should get deleted...
    $FROMSelectFormElement = $this->buildSelectFormElement("jsonFrom", "FROM", "", "required");
    $TOSelectFormElement = $this->buildSelectFormElement("jsonTo", "TO", "multiple", "required");

    return [
      '#theme' => 'labelmaker',
      '#path' => $labelMakerAbsolutePath,
      '#institutions' => $institutions,
      '#FROMSelectFormElement' => $FROMSelectFormElement,
      '#TOSelectFormElement' => $TOSelectFormElement,
    ];

  }

}
