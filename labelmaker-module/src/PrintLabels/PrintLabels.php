<?php
/** @noinspection PhpArrayShapeAttributeCanBeAddedInspection */

ob_start();

require_once 'lib/fpdf/fpdf.php';
require_once 'lib/fpdf/barcode.php';
require_once 'lib/qrcode/qrcode.class.php';
require 'model/Institution.php';
require 'services/ShippingService.php';
require 'services/LabelService.php';
require 'FPDFLabelMaker.php';
require 'labels/Label.php';
require 'labels/AbstractLabel.php';

// Import all php files inside our labels directory
foreach (glob("labels/*.php") as $filename) {
  if ($filename != 'labels/AbstractLabel.php' && $filename != 'labels/Label.php') {
    require $filename;
  }
}

/*

                    Add Custom Labels to the registry below.
                    !!! Do NOT add a require entry above !!!

               If you are unsure about what do to consult the README.md

*/

$labelRegistry = [

  // Core Labels
  "CLC" => new CLCLabel(),
  "IASHR" => new IASHRLabel(),
  "IOWA" => new IOWALabel(),
  "IOWAN" => new IOWALabel(),
  "MALA" => new MALALabel(),
  "MOB" => new MOBLabel(),
  "TAE" => new TAELabel(),

  // Add Custom Labels Below

];


/*

           !!! Do NOT modify any code beyond this point !!!
                       Unless you want too...

*/

// This is the Institutions we'll be shipping To. This IS an array.
// It's based off our label_maker_nodes database table.
$shipToJSONArray = $_POST['jsonTo'];

// This is the Institution we ship from. This is NOT an array.
// It's based off our label_maker_nodes database table.
$shipFromJSON = $_POST['jsonFrom'];

$totalPrintLabels = $_POST['quantity'];


$shippingService = new ShippingService($shipFromJSON, $shipToJSONArray);

// build our pdf generator & print the labels
$labelService = new LabelService(
  $labelRegistry,
  $shippingService,
  new FPDFLabelMaker()
);

$labelService->printLabels($totalPrintLabels);

setcookie('label-from', $shippingService->ShipFROM->id, time() + (60 * 60 * 24 * 365), '/');

ob_end_flush();
