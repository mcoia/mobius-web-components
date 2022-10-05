<?php

/**
 * Builds Institution Objects based off posted json data;
 * Basically converts json to PHP Class objects
 */
class ShippingService {

  /**
   * This is where we ship From
   *
   * @var \Institution
   */
  public Institution $ShipFROM;

  /**
   * This is where we ship To
   *
   * @var array
   */
  public array $ShipTO;

  public function __construct($shipFromJson, $shipToJson) {

    // build our To & From Institutional objects
    $this->ShipFROM = $this->buildShipFROM($shipFromJson);
    $this->ShipTO = $this->buildShipTO($shipToJson);

  }

  /**
   * Builds a Ship From Institution Object based off POST json data
   *
   * @param $shipFromJsonData
   *
   * @return \Institution
   */
  private function buildShipFROM($shipFromJsonData): Institution {

    $json = json_decode($shipFromJsonData, TRUE);

    $institution = new Institution();
    $institution->id = $json["id"];
    $institution->is_stop = $json["is_stop"];
    $institution->statCode = $json["statCode"];
    $institution->locCode = $json["locCode"];
    $institution->oclcSymbol = $json["oclcSymbol"];
    $institution->locName = $json["locName"];
    $institution->address1 = $json["address1"];
    $institution->address2 = $json["address2"];
    $institution->city = $json["city"];
    $institution->state = $json["state"];
    $institution->zip = $json["zip"];
    $institution->sortCode = $json["sortCode"];
    $institution->interSort = $json["interSort"];
    $institution->permittedTo = $json["permittedTo"];

    return $institution;

  }

  /**
   * Builds an array of Ship To Institution PHP Objects based off POST To json
   * data from our label maker page. mobiusconsortium.org/labelmaker
   *
   * @param $institutionJSONArray
   *
   * @return array
   */
  private function buildShipTO($institutionJSONArray): array {

    $jsonArray = [];

    // loop over our json array & decode it
    foreach ($institutionJSONArray as $institution) {
      array_push($jsonArray, json_decode($institution, TRUE));
    }

    $phpInstitutionalObjectArray = [];

    // build the institutional object array
    foreach ($jsonArray as $json) {

      $institution = new Institution();
      $institution->id = $json["id"];
      $institution->is_stop = $json["is_stop"];
      $institution->statCode = $json["statCode"];
      $institution->locCode = $json["locCode"];
      $institution->oclcSymbol = $json["oclcSymbol"];
      $institution->locName = $json["locName"];
      $institution->address1 = $json["address1"];
      $institution->address2 = $json["address2"];
      $institution->city = $json["city"];
      $institution->state = $json["state"];
      $institution->zip = $json["zip"];
      $institution->sortCode = $json["sortCode"];
      $institution->interSort = $json["interSort"];
      $institution->permittedTo = $json["permittedTo"];

      array_push($phpInstitutionalObjectArray, $institution);

    }

    return $phpInstitutionalObjectArray;

  }

}

