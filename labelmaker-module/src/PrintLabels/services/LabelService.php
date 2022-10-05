<?php

class LabelService {

  private ShippingService $shippingService;

  private FPDFLabelMaker $FPDFLabelMaker;

  private array $labelRegistry;

  public function __construct($labelRegistry, $shippingService, $labelMaker) {
    $this->labelRegistry = $labelRegistry;
    $this->shippingService = $shippingService;
    $this->FPDFLabelMaker = $labelMaker;
    $this->AssignFPDFLabelMakerToLabelRegistry();
  }

  /**
   * Assign the FPDF Label Maker to all our labels in the label registry.
   *
   * @return void
   */
  private function AssignFPDFLabelMakerToLabelRegistry(): void {
    foreach ($this->labelRegistry as $label) {
      $label->labelMaker = $this->FPDFLabelMaker;
    }
  }

  /**
   * Iterates thru our Ship To Address and assigns them to the labels in our
   * label registry
   *
   */
  public function printLabels(int $totalLabelCount): void {

    // Shipping From Institution Object
    $shipFROM = $this->shippingService->ShipFROM;

    // This is the starting quadrant - Top Left
    $quadrantNumber = 1;

    // Get our page setup
    $this->FPDFLabelMaker->AddPage();
    $this->FPDFLabelMaker->DrawLabelCutLines();
    $this->FPDFLabelMaker->SetFont('Arial');
    $this->FPDFLabelMaker->SetFontSize(10);

    $labelsToBeMadeTotal = count($this->shippingService->ShipTO) * $totalLabelCount;
    $labelsToBeMadeCurrentCount = 0;

    // Iterate over the ShipTo destinations and assign them to the appropriate label class
    foreach ($this->shippingService->ShipTO as $shipTO) {

      // Print more than 1 label
      for ($currentLabelCount = 1; $currentLabelCount <= $totalLabelCount; $currentLabelCount++) {

        // We use a try->catch in case print to a label that isn't in the label registry
        try {

          // Grab our Label Class from the registry
          $label = $this->labelRegistry[$shipTO->interSort];

          // Here we set the shipping From & To Institution Objects
          $label->SetShippingAddress($shipFROM, $shipTO);

          // Set our quadrant
          $label->SetQuadrantNumber($quadrantNumber);

          // Generate an Uppercase UUID
          $label->SetShipmentID(strtoupper(uniqid()));

          // Here we'll call our interface methods
          $label->DrawShipTO();
          $label->DrawShipFROM();
          $label->DrawBarcode();
          $label->DrawLogo();
          $label->DrawStatCode();
          $label->DrawUUID();
          $label->DrawExtras();

        } catch (Exception $exception) {
          //        throw new Exception('Label Class Not Found ' . $exception);
        }

        // Increment our quadrant - Only 4 quadrants
        $quadrantNumber++;
        $labelsToBeMadeCurrentCount++;
        if ($quadrantNumber == 5 && $labelsToBeMadeCurrentCount < $labelsToBeMadeTotal) {
          $quadrantNumber = 1;
          $this->FPDFLabelMaker->AddPage();
          $this->FPDFLabelMaker->DrawLabelCutLines();
        }

      }

    }

    $this->FPDFLabelMaker->Output('MOBIUS-Label.pdf', 'D');

  }

}
