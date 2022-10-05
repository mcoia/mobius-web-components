<?php

class IASHRLabel extends AbstractLabel {

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

    // Location Name + Location Code
    $this->labelMaker->Text(
      $this->GetX(110),
      $this->GetY(180),
      $this->ShipTO->locName . ' ' . '(' . $this->ShipTO->locCode . ')');

    // Street address
    $this->labelMaker->Text(
      $this->GetX(110),
      $this->GetY(193),
      $this->ShipTO->address1);


    // City State zip
    $this->labelMaker->Text(
      $this->GetX(110),
      $this->GetY(206),
      $this->ShipTO->city . ', ' .
      $this->ShipTO->state . ' ' .
      $this->ShipTO->zip);

  }

  public function DrawBarcode(): void {

  }

  public function DrawLogo(): void {

    $filename = dirname(__FILE__) . '/img/ia_shares_logo.gif';

    $width = 175;

    $this->labelMaker->Image(
      $filename,
      $this->GetX(200),
      $this->GetY(8),
      $width, 0, '', ''
    );

  }

  public function DrawStatCode(): void {

    $this->labelMaker->SetFont('Arial', 'B', 42);

    $this->labelMaker->Text(
      $this->GetX(120),
      $this->GetY(160),
      $this->ShipTO->statCode);
  }

  public function DrawUUID(): void {
  }

  public function DrawExtras(): void {

    $this->labelMaker->SetFont('Arial', 'I', 8);

    // The caption below
    $this->labelMaker->Text(
      $this->GetX(20),
      $this->GetY(230),
      '"IA Shares is made possible by the '
    );

    $this->labelMaker->SetFont('Arial', 'BI', 8);

    $this->labelMaker->Text(
      $this->GetX(145),
      $this->GetY(230),
      'Institute of Museum and Library Services '
    );

    $this->labelMaker->SetFont('Arial', 'I', 8);

    $this->labelMaker->Text(
      $this->GetX(304),
      $this->GetY(230),
      'under'
    );

    $this->labelMaker->Text(
      $this->GetX(20),
      $this->GetY(240),
      'the provisions of the Library Services and Technology Act as administered by the'
    );

    $this->labelMaker->SetFont('Arial', 'BI', 8);

    $this->labelMaker->Text(
      $this->GetX(20),
      $this->GetY(250),
      'State Library of Iowa."'
    );


  }

}
