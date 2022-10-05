<?php /** @noinspection PhpArrayShapeAttributeCanBeAddedInspection */

class FPDFLabelMaker extends FPDF {

  /*

   Types of labels: from col 'interSort'
      MOB
      IASHR
      DAV
      ILA
      MALA <-- No Mobius Logo
      TAE
      CLC

  Things we know....
    we print in landscape mode
    8.5 x 11
    We have 4 label quadrants p/page

  */

  // our page margins in px
  public int $margin = 5;

  // Part of the rotate method
  private int $angle = 0;

  public BarcodeGenerator $barcode;

  public function __construct() {
    parent::__construct("L", "pt", "Letter");
    $this->barcode = new BarcodeGenerator($this);
  }

  public function DrawLabelCutLines(): void {

    // line length in px
    $lineLength = 20;

    /* Center Grid Lines */
    $this->SetLineWidth(.3);

    // Horizontal Line
    $this->Line(($this->GetPageCenterX() - ($lineLength / 2)), $this->GetPageCenterY(), ($this->GetPageCenterX() + ($lineLength / 2)), $this->GetPageCenterY());

    // Vertical Line
    $this->Line($this->GetPageCenterX(), ($this->GetPageCenterY() - ($lineLength / 2)), $this->GetPageCenterX(), ($this->GetPageCenterY() + ($lineLength / 2)));

    /* Top,Right,Bottom,Left Grid Lines */

    // For the rest of the lines we make the line length a bit longer
    $lineLength = $lineLength * 2;

    /* Top */
    $this->Line($this->GetPageCenterX(), 0, $this->GetPageCenterX(), $lineLength);

    /* Right */
    $this->Line($this->GetPageWidth(), $this->GetPageCenterY(), ($this->GetPageWidth() - $lineLength), $this->GetPageCenterY());

    /* Bottom */
    $this->Line($this->GetPageCenterX(), $this->GetPageHeight(), $this->GetPageCenterX(), ($this->GetPageHeight() - $lineLength));

    /* Left */
    $this->Line(0, $this->GetPageCenterY(), $lineLength, $this->GetPageCenterY());

  }

  public function GetPageCenterX(): float|int {
    return $this->GetPageWidth() / 2;
  }

  public function GetPageCenterY(): float|int {
    return $this->GetPageHeight() / 2;
  }

  /**
   * Returns an array with the x,y,x2,y2 start & end px position of a quadrant
   * between 1-4
   *
   * 1 - Top Left
   * 2 - Top Right
   * 3 - Bottom Left
   * 4 - Bottom Right
   *
   * @param $quadrantNumber
   *
   * @return array
   */
  public function GetQuadrantCoordinateArray($quadrantNumber): array {

    $x1 = 0;
    $x2 = 0;
    $y1 = 0;
    $y2 = 0;

    if ($quadrantNumber == 1) {
      $x1 = $this->margin;
      $y1 = $this->margin;
      $x2 = $this->GetPageCenterX() - $this->margin;
      $y2 = $this->GetPageCenterY() - $this->margin;
    }

    if ($quadrantNumber == 2) {
      $x1 = $this->GetPageCenterX() + $this->margin;
      $y1 = $this->margin;
      $x2 = $this->GetPageWidth() - $this->margin;
      $y2 = $this->GetPageCenterY() - $this->margin;
    }

    if ($quadrantNumber == 3) {
      $x1 = $this->margin;
      $y1 = $this->GetPageCenterY() + $this->margin;
      $x2 = $this->GetPageCenterX() - $this->margin;
      $y2 = $this->GetPageHeight() - $this->margin;
    }

    if ($quadrantNumber == 4) {
      $x1 = $this->GetPageCenterX() + $this->margin;
      $y1 = $this->GetPageCenterY() + $this->margin;
      $x2 = $this->GetPageWidth() - $this->margin;
      $y2 = $this->GetPageHeight() - $this->margin;
    }

    return [
      "x" => $x1,
      "y" => $y1,
      "x2" => $x2,
      "y2" => $y2,
    ];

  }

  public function GetQuadrantSizeX(): float|int {
    return $this->GetPageWidth() / 2 - ($this->margin * 2);
  }

  public function GetQuadrantSizeY(): float|int {
    return $this->GetPageHeight() / 2 - ($this->margin * 2);
  }

  public function GetQuadrantCenterX($quadrantNumber): float|int {

    $quadrantXY = $this->GetQuadrantCoordinateArray($quadrantNumber);

    return ($quadrantXY['x2'] - $quadrantXY['x']) / 2;

  }

  public function GetQuadrantCenterY($quadrantNumber): float|int {

    $quadrantXY = $this->GetQuadrantCoordinateArray($quadrantNumber);

    return ($quadrantXY['y2'] - $quadrantXY['y']) / 2;

  }

  function Rotate($angle, $x = -1, $y = -1) {
    if ($x == -1) {
      $x = $this->x;
    }
    if ($y == -1) {
      $y = $this->y;
    }
    if ($this->angle != 0) {
      $this->_out('Q');
    }
    $this->angle = $angle;
    if ($angle != 0) {
      $angle *= M_PI / 180;
      $c = cos($angle);
      $s = sin($angle);
      $cx = $x * $this->k;
      $cy = ($this->h - $y) * $this->k;
      $this->_out(sprintf('q %.5F %.5F %.5F %.5F %.2F %.2F cm 1 0 0 1 %.2F %.2F cm', $c, $s, -$s, $c, $cx, $cy, -$cx, -$cy));
    }
  }

}
