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


    $mco_last_from_id = 0;
    if (isset($_COOKIE['label-from'])) {
      $mco_last_from_id = $_COOKIE['label-from'];
    }

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

      $html = $html . "<option ";

      $institutionID = $institution["id"];
      $name = $institution["locName"];
      $permittedTo = $institution["permittedTo"];
      $interSort = $institution["interSort"];
      if (!$institution["is_stop"]) {
        $name .= " (Delivers to " . $institution["address1"];
      }
      else {
        $name .= " (" . $institution["state"] . ": " . $institution['locCode'];
      }

      // Uncomment this if MCDAC wants to see OCLC symbols in there
      if ($institution["oclcSymbol"]) {
        $name .= " OCLC: " . $institution["oclcSymbol"] . ")";
      }
      else {
        $name .= ")";
      }
      $state = $institution["state"];

      // Set our FROM in our dropdown based off our cookie value - check to see if the mco_last_from_id cookie equals this node id
      if ($list_label == "FROM" && $mco_last_from_id == $institutionID) {
        $html = $html . " selected ";
      }

      $html = $html . "data-permitted-to='$permittedTo' ";
      $html = $html . "data-intersort='$interSort' ";

      $jsonInstitution = Json::encode($institution);

      $html = $html . "value='$jsonInstitution' class='$state'>$name</option>\n";
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
