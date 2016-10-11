<?php

require_once ('fpdf.php');

class PDF_Label extends FPDF
{
  // Private properties
  public $_Avery_Name    = '';                // Name of format
  public $_Margin_Left    = 0;                // Left margin of labels
  public $_Margin_Top    = 0;                // Top margin of labels
  public $_X_Space         = 0;                // Horizontal space between 2 labels
  public $_Y_Space         = 0;                // Vertical space between 2 labels
  public $_X_Number         = 0;                // Number of labels horizontally
  public $_Y_Number         = 0;                // Number of labels vertically
  public $_Width         = 0;                // Width of label
  public $_Height         = 0;                // Height of label
  public $_Char_Size        = 10;                // Character size
  public $_Line_Height    = 10;                // Default line height
  public $_Metric         = 'mm';                // Type of metric for labels.. Will help to calculate good values
  public $_Metric_Doc     = 'mm';                // Type of metric for the document
  public $_Font_Name        = 'Arial';            // Name of the font

  public $_COUNTX = 1;
  public $_COUNTY = 1;

  // Listing of labels size
  public $_Avery_Labels = array(
    '5160' => array('name' => '5160',    'paper-size' => 'letter',    'metric' => 'mm',    'marginLeft' => 1.762,    'marginTop' => 10.7,        'NX' => 3,    'NY' => 10,    'SpaceX' => 3.175,    'SpaceY' => 0,    'width' => 66.675,    'height' => 25.4,        'font-size' => 8),
    '5161' => array('name' => '5161',    'paper-size' => 'letter',    'metric' => 'mm',    'marginLeft' => 0.967,    'marginTop' => 10.7,        'NX' => 2,    'NY' => 10,    'SpaceX' => 3.967,    'SpaceY' => 0,    'width' => 101.6,        'height' => 25.4,        'font-size' => 8),
    '5162' => array('name' => '5162',    'paper-size' => 'letter',    'metric' => 'mm',    'marginLeft' => 0.97,        'marginTop' => 20.224,    'NX' => 2,    'NY' => 7,    'SpaceX' => 4.762,    'SpaceY' => 0,    'width' => 100.807,    'height' => 35.72,    'font-size' => 8),
    '5163' => array('name' => '5163',    'paper-size' => 'letter',    'metric' => 'mm',    'marginLeft' => 1.762,    'marginTop' => 10.7,         'NX' => 2,    'NY' => 5,    'SpaceX' => 3.175,    'SpaceY' => 0,    'width' => 101.6,        'height' => 50.8,        'font-size' => 8),
    '5164' => array('name' => '5164',    'paper-size' => 'letter',    'metric' => 'in',    'marginLeft' => 0.148,    'marginTop' => 0.5,         'NX' => 2,    'NY' => 3,    'SpaceX' => 0.2031,    'SpaceY' => 0,    'width' => 4.0,        'height' => 3.33,        'font-size' => 12),
    '8600' => array('name' => '8600',    'paper-size' => 'letter',    'metric' => 'mm',    'marginLeft' => 7.1,         'marginTop' => 19,         'NX' => 3,     'NY' => 10,     'SpaceX' => 9.5,         'SpaceY' => 3.1,     'width' => 66.6,         'height' => 25.4,        'font-size' => 8),
    'L7163' => array('name' => 'L7163',    'paper-size' => 'A4',        'metric' => 'mm',    'marginLeft' => 5,        'marginTop' => 15,         'NX' => 2,    'NY' => 7,    'SpaceX' => 25,        'SpaceY' => 0,    'width' => 99.1,        'height' => 38.1,        'font-size' => 9),
    // Modified "Letter" from back in the old days. Gonna have 4 labels per sheet now..
    'Letter' => array('name' => 'Letter',    'paper-size' => 'letter',        'metric' => 'mm',    'marginLeft' => 5,        'marginTop' => 5,         'NX' => 2,    'NY' => 2,    'SpaceX' => 10,        'SpaceY' => 0,    'width' => 130,        'height' => 105,        'font-size' => 9),

  );

  // convert units (in to mm, mm to in)
  // $src and $dest must be 'in' or 'mm'
  public function _Convert_Metric($value, $src, $dest)
  {
    if ($src != $dest) {
      $tab['in'] = 39.37008;
      $tab['mm'] = 1000;

      return $value * $tab[$dest] / $tab[$src];
    } else {
      return $value;
    }
  }

  // Give the height for a char size given.
  public function _Get_Height_Chars($pt)
  {
    // Array matching character sizes and line heights
    $_Table_Hauteur_Chars = array(6 => 2, 7 => 2.5, 8 => 3, 9 => 4, 10 => 5, 11 => 6, 12 => 7, 13 => 8, 14 => 9, 15 => 10);
    if (in_array($pt, array_keys($_Table_Hauteur_Chars))) {
      return $_Table_Hauteur_Chars[$pt];
    } else {
      return 100; // There is a prob..
    }
  }

  public function _Set_Format($format)
  {
    $this->_Metric         = $format['metric'];
    $this->_Avery_Name     = $format['name'];
    $this->_Margin_Left    = $this->_Convert_Metric($format['marginLeft'], $this->_Metric, $this->_Metric_Doc);
    $this->_Margin_Top    = $this->_Convert_Metric($format['marginTop'], $this->_Metric, $this->_Metric_Doc);
    $this->_X_Space     = $this->_Convert_Metric($format['SpaceX'], $this->_Metric, $this->_Metric_Doc);
    $this->_Y_Space     = $this->_Convert_Metric($format['SpaceY'], $this->_Metric, $this->_Metric_Doc);
    $this->_X_Number     = $format['NX'];
    $this->_Y_Number     = $format['NY'];
    $this->_Width         = $this->_Convert_Metric($format['width'], $this->_Metric, $this->_Metric_Doc);
    $this->_Height         = $this->_Convert_Metric($format['height'], $this->_Metric, $this->_Metric_Doc);
    $this->Set_Font_Size($format['font-size']);
  }

  // Constructor
  public function PDF_Label($format, $unit = 'mm', $posX = 1, $posY = 1)
  {
    if (is_array($format)) {
      // Custom format
      $Tformat = $format;
    } else {
      // Avery format
      $Tformat = $this->_Avery_Labels[$format];
    }

    parent::FPDF('L', $Tformat['metric'], $Tformat['paper-size']);
    $this->_Set_Format($Tformat);
    $this->Set_Font_Name('Arial');
    $this->SetMargins(0, 0);
    $this->SetAutoPageBreak(false);

    $this->_Metric_Doc = $unit;
    // Start at the given label position
    if ($posX > 1) {
      $posX--;
    } else {
      $posX = 0;
    }
    if ($posY > 1) {
      $posY--;
    } else {
      $posY = 0;
    }
    if ($posX >=  $this->_X_Number) {
      $posX =  $this->_X_Number-1;
    }
    if ($posY >=  $this->_Y_Number) {
      $posY =  $this->_Y_Number-1;
    }
    $this->_COUNTX = $posX;
    $this->_COUNTY = $posY;
  }

  // Sets the character size
  // This changes the line height too
  public function Set_Font_Size($pt)
  {
    if ($pt > 3) {
      $this->_Char_Size = $pt;
      $this->_Line_Height = $this->_Get_Height_Chars($pt);
      $this->SetFontSize($this->_Char_Size);
    }
  }

  // Method to change font name
  public function Set_Font_Name($fontname)
  {
    if ($fontname != '') {
      $this->_Font_Name = $fontname;
      $this->SetFont($this->_Font_Name);
    }
  }
  public $col = 0;

  public function SetCol($col)
  {
    //Move position to a column
    $this->col = $col;
    $x = 10+$col*160;
    $this->SetLeftMargin($x);
    $this->SetX($x);
  }

  public function AcceptPageBreak()
  {
    if ($this->col<1) {
      //Go to next column
      $this->SetCol($this->col+1);
      $this->SetY(10);

      return false;
    } else {
      //Go back to first column and issue page break
      $this->SetCol(0);

      return true;
    }
  }
  // Print a label
  public function Add_PDF_Label($texte)
  {
    // We are in a new page, then we must add a page
    if (($this->_COUNTX == 0) and ($this->_COUNTY == 0)) {
      $this->AddPage();
    }

    $_PosX = $this->_Margin_Left+($this->_COUNTX*($this->_Width+$this->_X_Space));
    $_PosY = $this->_Margin_Top+($this->_COUNTY*($this->_Height+$this->_Y_Space));
    $this->SetXY($_PosX+3, $_PosY+3);
    $this->MultiCell($this->_Width, $this->_Line_Height, $texte);
    $this->_COUNTY++;

    if ($this->_COUNTY == $this->_Y_Number) {
      // End of column reached, we start a new one
      $this->_COUNTX++;
      $this->_COUNTY = 0;
    }

    if ($this->_COUNTX == $this->_X_Number) {
      // Page full, we start a new one
      $this->_COUNTX = 0;
      $this->_COUNTY = 0;
    }
  }

  //Print the FROM: portion of the label
  public function PrintFrom($fromAddress, $_PosX)
  {
    // We will need to pad any lines at the bottom to make everything line up nice
    // in the case that there is missing data
    $pad = 0;

    // Title font: Arial bold 15
    $this->SetFont('Arial', 'B', 12);

    // "From" section title
    //$this->Cell($_PosX); // move to the right TODO: Remove
    $this->Cell(30, 4, 'FROM: '.$fromAddress['locCode'], 0, 1);
    $this->Ln(1.5);

    // Set smaller font
    $this->SetFont('Arial', '', 8);

    // From Address - just using location name and city/state now
    $margin = $_PosX;
    $lineHeight = 3.5;
    if ($fromAddress['locName']) {
      $this->Cell($margin);
      $this->Cell($_PosX+30, $lineHeight, substr($fromAddress['locName'], 0, 50), 0, 1);
    } else {
      $pad++;
    }
    if ($fromAddress['city'] && $fromAddress['state']) {
      $this->Cell($margin);
      $this->Cell($_PosX+30, $lineHeight, substr($fromAddress['city'], 0, 50).', '.$fromAddress['state'], 0, 1);
    } else {
      $pad++;
    }

    //Line breaks to push down the next section. Use $pad to make it even.
    $this->Ln($pad*4+24);
  }

  // Print the portion of the label
  // We don't need to pad this because it's on the bottom
  public function PrintTo($toAddress, $_PosX)
  {

    // Get the cursor all the way to the right. We will set Cells at 50% width exactly
    // then center the From Title;
    if ($_PosX >= 142.5) {
      $this->SetX(142.5);
    } else {
      $this->SetX(0);
    }

    // TO Header
    $this->SetFont('Arial', 'B', 32); // Set Header font large

    if ($toAddress['interSort'] == 'MOB') {
      $this->Cell(142.5, 12, 'ENE1234'.'_'.$_PosX, 0, 1, 'C'); // for example....
    } elseif ($toAddress['interSort'] == 'CLC') {
      $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['sortCode'], 0, 1, 'C');
    } elseif ($toAddress['interSort'] && $toAddress['locCode']) {
      $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['locCode'].'/'.$toAddress['sortCode'], 0, 1, 'C');
    } elseif ($toAddress['interSort'] && $toAddress['sortCode']) {
      $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['sortCode'], 0, 1, 'C');
    } else {
      $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['locCode'], 0, 1, 'C');
    }

    $this->Ln(3); // Pad the address at the top a little bit

    if ($toAddress['interSort'] == 'MOB') {
      $margin = $_PosX+35;
      $lineHeight = 5;
      $longLength = 40;
      $maxLength = 50;
      $this->Cell(142.5, 12,$this->Code128(50, 50, 'blah', 110, 20), 1, 1, 'C');
    } else {
      //To Address
      $margin = $_PosX+35;
      $lineHeight = 5;
      $longLength = 40;
      $maxLength = 50;

      $this->SetFont('Arial', 'B', 11);  // set font back to normal size

      if ($toAddress['locName']) {
        $this->Cell($margin, '', '', 2);
        if (strlen(substr($toAddress['locName'], 0, $maxLength)) > $longLength) {
          $this->SetFontSize(9);
        }
        $this->Cell($_PosX+30, $lineHeight, $toAddress['locName'], 0, 1);
        $this->SetFontSize(11);
      }

      if ($toAddress['address1']) {
        $this->Cell($margin, '', '', 2);
        if (strlen(substr($toAddress['address1'], 0, $maxLength)) > $longLength) {
          $this->SetFontSize(9);
        }
        $this->Cell($_PosX+30, $lineHeight, $toAddress['address1'], 0, 1);
        $this->SetFontSize(11);
      }

      if ($toAddress['address2']) {
        $this->Cell($margin, '', '', 2);
        if (strlen(substr($toAddress['address2'], 0, $maxLength)) > $longLength) {
          $this->SetFontSize(9);
        }
        $this->Cell($_PosX+30, $lineHeight, $toAddress['address2'], 0, 1);
        $this->SetFontSize(11);
      }

      if ($toAddress['city'] && $toAddress['state']) {
        $this->Cell($margin, '', '', 2);
        if ($toAddress['zip']) {
          $this->Cell($_PosX+30, $lineHeight, $toAddress['city'].', '.$toAddress['state'].' '.$toAddress['zip'], 0, 1);
        } else {
          $this->Cell($_PosX+30, $lineHeight, $toAddress['city'].', '.$toAddress['state'], 0, 1);
        }
      }
    }

    //Line break
    $this->Ln(2);
  }

  public function PrintSortCode($sortCode, $_PosX)
  {
    $this->Cell($_PosX+95);
    $this->SetFont('Arial', 'B', 12);
    $this->Cell(30, 6, $sortCode, 0, 1, R);
    //$this->Ln(7);
  }

  public function PrintLabel($fromAddress, $toAddress)
  {
    // We are in a new page, then we must add a page
    if (($this->_COUNTX == 0) and ($this->_COUNTY == 0)) {
      $this->AddPage();
    }

    $_PosX = $this->_Margin_Left+($this->_COUNTX*($this->_Width+$this->_X_Space));
    $_PosY = $this->_Margin_Top+($this->_COUNTY*($this->_Height+$this->_Y_Space));

    $this->SetXY($_PosX, $_PosY);
    //horizontal crop marks
    $this->Line(0, 106.5, 10, 106.5);
    $this->Line(140, 106.5, 145, 106.5);
    $this->Line(270, 106.5, 280, 106.5);
    //vertical crop marks
    $this->Line(142.5, 0, 142.5, 10);
    $this->Line(142.5, 103.5, 142.5, 109.5);
    $this->Line(142.5, 206, 142.5, 216);

    $this->MultiCell($this->_Width, $this->_Line_Height, $this->PrintFrom($fromAddress, $_PosX).$this->PrintTo($toAddress, $_PosX));

    /*$this->PrintFrom($fromAddress);
    $this->PrintTo($toAddress);
    $this->PrintSortCode($sortCode);*/
    $this->_COUNTY++;
    //
    if ($this->_COUNTY == $this->_Y_Number) {
      // End of column reached, we start a new one
      $this->_COUNTX++;
      $this->_COUNTY = 0;
    }

    if ($this->_COUNTX == $this->_X_Number) {
      // Page full, we start a new one
      $this->_COUNTX = 0;
      $this->_COUNTY = 0;
    }
    //
  }
}

?>
