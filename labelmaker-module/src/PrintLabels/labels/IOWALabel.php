<?php

class IOWALabel extends AbstractLabel {

  public function DrawShipFROM(): void {

    $this->labelMaker->SetFont('Arial', 'B', 12);

    // FROM:
    $this->labelMaker->Text(
      $this->SetX(12),
      $this->SetY(18),
      "FROM: " . $this->ShipFROM->locCode);

    $this->labelMaker->SetFont('Arial', '', 8);

    // under FROM:
    $this->labelMaker->Text(
      $this->SetX(12),
      $this->SetY(32),
      $this->ShipFROM->locName);

    $this->labelMaker->Text(
      $this->SetX(12),
      $this->SetY(42),
      $this->ShipFROM->city . ', ' . $this->ShipFROM->state);

  }

  public function DrawShipTO(): void {

    $this->labelMaker->SetFont('Arial', 'B', 8);

    // Location Name + Location Code
    $this->labelMaker->Text(
      $this->SetX(80),
      $this->SetY(145),
      $this->ShipTO->locName . ' ' . '(' . $this->ShipTO->locCode . ')');


    // Below Name - it's a stat code + the uuid ??? that's a little weird
    $this->labelMaker->Text(
      $this->SetX(80),
      $this->SetY(160),
      $this->ShipTO->statCode . '_' . $this->GetShipmentID());

  }

  public function DrawBarcode(): void {


    // Standard code 128 barcode
    $this->labelMaker->barcode->Generate(
      $this->SetX(80),
      $this->SetY(200),
      $this->ShipTO->statCode . "_" . $this->GetShipmentID(),
      235,
      60,
    );

    // Now the qrcode
//    $qrcode = new QRcode ($this->ShipTO->statCode . "_" . $this->GetShipmentID(), 'H');
//    $qrcode->disableBorder();
//    $qrcode->displayFPDF(
//      $this->labelMaker,
//      $this->SetX(10),
//      $this->SetY(80),
//      '80',
//      [255, 255, 255,],
//      [0, 0, 0, 0]);

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

    $this->labelMaker->SetFont('Arial', 'B', 42);

    $this->labelMaker->Text(
      $this->SetX(80),
      $this->SetY(120),
      $this->ShipTO->statCode);
  }

  public function DrawUUID(): void {
  }

  public function DrawExtras(): void {
  }

}
