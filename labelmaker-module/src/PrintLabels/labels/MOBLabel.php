<?php

class MOBLabel extends AbstractLabel {

  public function DrawShipFROM(): void {

    $this->labelMaker->SetFont('Arial', 'B', 12);

    // FROM:
    $this->labelMaker->Text(
      $this->GetX(12),
      $this->GetY(18),
      "FROM: " . $this->ShipFROM->locCode);

    $this->labelMaker->SetFont('Arial', '', 8);

    // under FROM:
    $this->labelMaker->Text(
      $this->GetX(12),
      $this->GetY(32),
      $this->ShipFROM->locName);

    $this->labelMaker->Text(
      $this->GetX(12),
      $this->GetY(42),
      $this->ShipFROM->city . ', ' . $this->ShipFROM->state);

  }

  public function DrawShipTO(): void {

    $this->labelMaker->SetFont('Arial', 'B', 10);


    // check for long address names and re-position them if necessary.
    if (strlen($this->ShipTO->locName) >= 46) {

      // Location Name + Location Code
      $this->labelMaker->Text(
        $this->GetX(120),
        $this->GetY(145),
        $this->ShipTO->locName . ' ' . '(' . $this->ShipTO->locCode . ')');
    }
    else {
      // Location Name + Location Code
      $this->labelMaker->Text(
        $this->GetX(180),
        $this->GetY(145),
        $this->ShipTO->locName . ' ' . '(' . $this->ShipTO->locCode . ')');
    }

    // Below Name - it's a stat code + the uuid ??? that's a little weird
    $this->labelMaker->Text(
      $this->GetX(183),
      $this->GetY(160),
      $this->ShipTO->statCode . '_' . $this->GetShipmentID());

  }

  public function DrawBarcode(): void {

    // Standard code 128 barcode
    $this->labelMaker->barcode->Generate(
      $this->GetX(80),
      $this->GetY(200),
      $this->GetShipmentID(),
      235,
      60,
    );

    // Now the qrcode
    $qrcode = new QRcode ($this->GetShipmentID(), 'H');
    $qrcode->disableBorder();
    $qrcode->displayFPDF(
      $this->labelMaker,
      $this->GetX(28),
      $this->GetY(78),
      '80',
      [255, 255, 255,],
      [0, 0, 0, 0]);

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

    $this->labelMaker->SetFont('Arial', 'B', 42);

    $this->labelMaker->Text(
      $this->GetX(140),
      $this->GetY(120),
      $this->ShipTO->statCode);
  }

  public function DrawUUID(): void {
  }

  public function DrawExtras(): void {
  }

}