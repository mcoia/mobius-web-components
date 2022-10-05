<?php

abstract class AbstractLabel implements Label {

  public int $quadrantNumber;

  public FPDFLabelMaker $labelMaker;

  public Institution $ShipTO;

  public Institution $ShipFROM;

  private string $shipmentID;

  public function SetShippingAddress(Institution $ShipFROMInstitution, Institution $ShipTOInstitution) {
    $this->ShipFROM = $ShipFROMInstitution;
    $this->ShipTO = $ShipTOInstitution;
  }

  public function SetQuadrantNumber($quadrantNumber) {
    $this->quadrantNumber = $quadrantNumber;
  }

  public function GetQuadrantNumber(): int {
    return $this->quadrantNumber;
  }

  public function GetX($x): int {
    return $this->labelMaker->GetQuadrantCoordinateArray($this->quadrantNumber)['x'] + $x;
  }

  public function GetY($y): int {
    return $this->labelMaker->GetQuadrantCoordinateArray($this->quadrantNumber)['y'] + $y;
  }

  public function GetShipmentID(): string {
    return $this->shipmentID;
  }

  public function SetShipmentID($shipmentID): void {
    $this->shipmentID = $shipmentID;
  }

}
