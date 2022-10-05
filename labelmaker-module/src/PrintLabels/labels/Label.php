<?php

interface Label {

  public function DrawShipFROM(): void;

  public function DrawShipTO(): void;

  public function DrawBarcode(): void;

  public function DrawLogo(): void;

  public function DrawStatCode(): void;

  public function DrawUUID(): void;

  public function DrawExtras(): void;

}
