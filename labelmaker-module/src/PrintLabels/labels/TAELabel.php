<?php

class TAELabel extends AbstractLabel {

  public function DrawShipFROM(): void {

    $this->labelMaker->SetFont('Arial', 'B', 12);

    // FROM:
    $this->labelMaker->Text(
      $this->SetX(55),
      $this->SetY(18),
      "FROM: " . $this->ShipFROM->locCode);

    $this->labelMaker->SetFont('Arial', '', 8);

    // under FROM:
    $this->labelMaker->Text(
      $this->SetX(55),
      $this->SetY(32),
      $this->ShipFROM->locName);


    $this->labelMaker->Text(
      $this->SetX(55),
      $this->SetY(42),
      $this->ShipFROM->city . ', ' . $this->ShipFROM->state);

  }

  public function DrawShipTO(): void {

    $this->labelMaker->SetFont('Arial', 'B', 8);

    // Location Name + Location Code
    $this->labelMaker->Text(
      $this->SetX(110),
      $this->SetY(170),
      $this->ShipTO->locName . ' ' . '(' . $this->ShipTO->locCode . ')');

    // Below Name - it's a stat code + the uuid ??? that's a little weird
    $this->labelMaker->Text(
      $this->SetX(110),
      $this->SetY(185),
      $this->ShipTO->city . ', ' . $this->ShipTO->state);

  }

  public function DrawBarcode(): void {

    $this->labelMaker->Rotate(90, $this->SetX(40), $this->SetY(200));

    // Standard code 128 barcode
    $this->labelMaker->barcode->Generate(
      $this->SetX(80),
      $this->SetY(170),
      $this->ShipTO->statCode . "_" . $this->GetShipmentID(),
      150,
      30,
    );

    // BagID::
    $this->labelMaker->Text(
      $this->SetX(105),
      $this->SetY(210),
      "BagID: " . $this->GetShipmentID());

    $this->labelMaker->Rotate(0, 0, 0);

  }

  public function DrawLogo(): void {

    $filename = dirname(__FILE__) . '/img/mobius.gif';

    $width = 125;

    $this->labelMaker->Image(
      $filename,
      $this->SetX(245),
      $this->SetY(8),
      $width, 0, '', ''
    );

  }

  public function DrawStatCode(): void {
    $this->labelMaker->SetFont('Arial', 'B', 32);

    $this->labelMaker->Text(
      $this->SetX(110),
      $this->SetY(152),
      $this->ShipTO->interSort . ': ' .
      $this->ShipTO->locCode . '/' .
      $this->ShipTO->sortCode);

  }

  public function DrawUUID(): void {
  }

  public function DrawExtras(): void {
  }

}
