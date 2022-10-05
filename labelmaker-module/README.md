<div align="center">
<img align="center" style="margin: 100px 0px 0px 0px" height="150" src="doc/img/mobius-mark.jpeg" />
<h2 style="margin-top: 0px;" align="center">Mobius Label Maker 2</h2>
<h5 align="center">The
<a href="http://mobiusconsortium.org/labelmaker">Mobius Label Maker</a>
is intended for making shipping labels to/from MOBIUS members and the Iowa partner libraries.</h5>

<img alt="Javascript" src="https://img.shields.io/badge/php-0E7FBF?logo=php&logoColor=white&style=flat" />
<img alt="Javascript" src="https://img.shields.io/badge/JavaScript-F7DF1E?logo=javascript&logoColor=white&style=flat" />
<img alt="Javascript" src="https://img.shields.io/badge/mysql-25AA25?logo=mysql&logoColor=white&style=flat" />
<img alt="Javascript" src="https://img.shields.io/badge/Drupal-006FB4?logo=drupal&logoColor=white&style=flat" />

<img width="1200" src="doc/img/mobius-label-maker-sample.png" />
</div>

## Installation

This is a Drupal Module & requires Drupal version 9+

The labelmaker directory goes here...

    {{drupal-installation-directory}}/web/modules/custom/

example:

    /var/www/drupal/web/modules/custom/labelmaker

Once the labelmaker directory is copied to the modules/custom directory enable the module & click install.
You should be able to reach the url at:

    http://{your-site-here}/labelmaker

## How To Use

Each label type (MOB,IASHR,ILA ect...) is represented by its own Label class.

Label classes are located:

    src/PrintLabels/labels/

This is where we create individual labels via an extended AbstractLabel class.

Your label class must implement all the methods defined in the interface Label.php

Be sure to extend the AbstractLabel class and then implement the interface methods.

Your Class should look something like this ABC Class below. Feel free to just copy + paste

```php
class ABCLabel extends AbstractLabel {

    public function DrawShipFROM(): void {
      // Put Code Here
    }

    public function DrawShipTO(): void {
      // Put Code Here
    }

    public function DrawBarcode(): void {
      // Put Code Here
    }

    public function DrawLogo(): void {
      // Put Code Here
    }

    public function DrawStatCode(): void {
      // Put Code Here
    }

    public function DrawUUID(): void {
      // Put Code Here
    }

    public function DrawExtras(): void {
      // Put Code Here
    }

}

```

Once you're done with your label class you'll add it to the label registry like below.

```php
    $labelRegistry = [

          // Core Labels
          "CLC" => new CLCLabel(),
          "DAV" => new DAVLabel(),
          "IASHR" => new IASHRLabel(),
          "ILA" => new ILALabel(),
          "MALA" => new MALALabel(),
          "MOB" => new MOBLabel(),
          "TAE" => new TAELabel(),

          // Add Custom Labels Below
          "ABC" => new ABCLabel(),

      ];
```

And that's it. Any label request that comes through with the interSort code "ABC" will be directed to this label.

*There is no need to add <b>require "some-label.php"</b> as we discover all .php classes in the
/labels directory.*

More information about creating label classes listed below.

## BackEnd Code

`src/PrintLabels`

The code is broken down into a few core classes.

- PrintLabels.php - Our Entry Point. We receive some POST json data, Instantiate the Shipping service and the Label
  Service.
- ShippingService.php - Provides Shipping From & Shipping To Objects
- LabelService.php - Responsible for assigning jobs to the correct label classes.
- FPDFLabelMaker.php - Extends the FPDF lib & adds extra functionality.
- Institution.php - This is a POPO data object used by the Shipping Service. It houses our Ship From & Ship To
  information.

We take the Shipping Service and inject it into the Label Service.
We also inject FPDFLabelMaker class into the Label Service.

#### Label Class

Our pdf label page is broken down into 4 quadrants.

1 - Top Left | 2 - Top Right | 3 - Bottom Left | 4 - Bottom Right

Each Label class is assigned a quadrant to generate a label on.

Use GetX($x) to specify x location relative to the label quadrant.

If you set the x value without calling GetX($x) you will be specifying the x location absolute to the page itself and
not the quadrant.
The same goes for GetY($y)

Here is some standard code used in the label classes

```php

// Set Font
$this->labelMaker->SetFont('Arial', 'B', 12);

// Add Text
$this->labelMaker->Text(x,y,txt);

// Standard code 128 barcode
$this->labelMaker->barcode->Generate(
  $this->GetX(80),
  $this->GetY(170),
  $this->GetShipmentID(),
  150, // width
  30, // height
);

// Add a logo
$filename = dirname(__FILE__) . '/img/mobius.gif';
$width = 125;
$this->labelMaker->Image(
  $filename,
  $this->GetX(245),
  $this->GetY(8),
  $width, 0, '', ''
);

// Rotate Something 90 degrees - Place before the thing you want to rotate (can be a pain...)
$this->labelMaker->Rotate(90, $this->GetX(40), $this->GetY(200));

// Rotate Rest
$this->labelMaker->Rotate(0, 0, 0);

// ShipTO & ShipFrom Properties
$this->ShipTO->id
$this->ShipTO->is_stop
$this->ShipTO->statCode
$this->ShipTO->locCode
$this->ShipTO->oclcSymbol
$this->ShipTO->locName
$this->ShipTO->address1
$this->ShipTO->address2
$this->ShipTO->city
$this->ShipTO->state
$this->ShipTO->zip
$this->ShipTO->sortCode
$this->ShipTO->interSort
$this->ShipTO->permittedTo

```

## Front End Code

Location:

    src/Controller/LabelMakerController.php
    templates/label-maker.html.twig

A Drupal requirement is the .htaccess file located
`src/PrintLabels/.htaccess`

Which contains...

      <IfModule mod_rewrite.c>
      RewriteEngine on
      # stuff to let through (ignore)
      RewriteRule (.*) $1 [L]
      </IfModule>

It's needed to allow outside drupal access to these files.
Without it, we can't send POST request to PrintLabels.php file.

## Some Reference Links

FPDF homepage - http://www.fpdf.org/

FPDF API Documentation - http://www.fpdf.org/en/doc/index.php

Some tutorials on fpdf - https://www.plus2net.com/php_tutorial/pdf-cell.php

Barcode script - http://www.fpdf.org/en/script/script88.php

Other scripts built w/fpdf library - http://www.fpdf.org/en/script/index.php

