<?php

class CLCLabel extends AbstractLabel {

  public function DrawShipFROM(): void {

    $this->labelMaker->SetFont('Arial', 'B', 12);

    // FROM:
    $this->labelMaker->Text(
      $this->GetX(55),
      $this->GetY(18),
      "FROM: " . $this->ShipFROM->locCode);

    $this->labelMaker->SetFont('Arial', '', 8);

    // under FROM:
    $this->labelMaker->Text(
      $this->GetX(55),
      $this->GetY(32),
      $this->ShipFROM->locName);


    $this->labelMaker->Text(
      $this->GetX(55),
      $this->GetY(42),
      $this->ShipFROM->city . ', ' . $this->ShipFROM->state);

  }

  public function DrawShipTO(): void {

    $this->labelMaker->SetFont('Arial', 'B', 8);

    // Location Name + Location Code
    $this->labelMaker->Text(
      $this->GetX(110),
      $this->GetY(170),
      $this->ShipTO->locName . ' ' . '(' . $this->ShipTO->locCode . ')');

    /*
       This portion has been taken out by request.

     // Below Name - it's a stat code + the uuid ??? that's a little weird
     $this->labelMaker->Text(
       $this->GetX(110),
       $this->GetY(185),
       $this->ShipTO->city . ', ' . $this->ShipTO->state);

    */

  }

  public function DrawBarcode(): void {


    $this->labelMaker->Rotate(90, $this->GetX(40), $this->GetY(200));

    // Standard code 128 barcode
    $this->labelMaker->barcode->Generate(
      $this->GetX(80),
      $this->GetY(170),
      $this->ShipTO->statCode . $this->GetShipmentID(),
      150,
      30,
    );

    // BagID::
    $this->labelMaker->Text(
      $this->GetX(105),
      $this->GetY(210),
      "BagID: " . $this->GetShipmentID());

    $this->labelMaker->Rotate(0, 0, 0);

  }

  public function DrawLogo(): void {


    $filename = dirname(__FILE__) . '/img/mobius.gif';

    $width = 125;

    $this->labelMaker->Image(
      $filename,
      $this->GetX(245),
      $this->GetY(8),
      $width, 0, '', ''
    );

  }

  public function DrawStatCode(): void {
    $this->labelMaker->SetFont('Arial', 'B', 32);

    $this->labelMaker->Text(
      $this->GetX(110),
      $this->GetY(152),
      $this->ShipTO->interSort . ': ' . $this->ShipTO->sortCode);

  }

  public function DrawUUID(): void {
    // TODO: Implement DrawUUID() method.
  }

  public function DrawExtras(): void {
    // TODO: Implement DrawExtras() method.
  }

}
