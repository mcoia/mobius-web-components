<?php
setcookie('labelFrom', $_POST['from_id'], time()+(60*60*24*365), '/', 'mobiusconsortium.org');
////////////////////////////////////////////////////
// PDF_Label
//
// Class to print labels in Avery or custom formats
//
//
// Copyright (C) 2003 Laurent PASSEBECQ (LPA)
// Based on code by Steve Dillon : steved@mad.scientist.com
//
//-------------------------------------------------------------------
// VERSIONS :
// 1.0  : Initial release
// 1.1  : + : Added unit in the constructor
//        + : Now Positions start @ (1,1).. then the first image @top-left of a page is (1,1)
//        + : Added in the description of a label :
//                font-size    : defaut char size (can be changed by calling Set_Char_Size(xx);
//                paper-size    : Size of the paper for this sheet (thanx to Al Canton)
//                metric        : type of unit used in this description
//                              You can define your label properties in inches by setting metric to 'in'
//                              and printing in millimiter by setting unit to 'mm' in constructor.
//              Added some labels :
//                5160, 5161, 5162, 5163,5164 : thanx to Al Canton : acanton@adams-blake.com
//                8600                         : thanx to Kunal Walia : kunal@u.washington.edu
//        + : Added 3mm to the position of labels to avoid errors
// 1.2  : + : Added Set_Font_Name method
//        = : Bug of positioning
//        = : Set_Font_Size modified -> Now, just modify the size of the font
//        = : Set_Char_Size renamed to Set_Font_Size
////////////////////////////////////////////////////

/**
 * PDF_Label - PDF label editing.
 *
 * @author Laurent PASSEBECQ <lpasseb@numericable.fr>
 * @copyright 2003 Laurent PASSEBECQ
 **/
require_once './fpdf16/fpdf.php';
require_once './qrcode/qrcode.class.php';
require_once './fpdf16/rotation.php';

define('DRUPAL_ROOT', '/drupal');
require_once DRUPAL_ROOT . '/includes/bootstrap.inc';
drupal_bootstrap(DRUPAL_BOOTSTRAP_FULL);

class PDF_Label extends FPDF
{
  // Private properties
  public $_Avery_Name = '';                // Name of format
  public $_Margin_Left = 0;                // Left margin of labels
  public $_Margin_Top = 0;                // Top margin of labels
  public $_X_Space = 0;                // Horizontal space between 2 labels
  public $_Y_Space = 0;                // Vertical space between 2 labels
  public $_X_Number = 0;                // Number of labels horizontally
  public $_Y_Number = 0;                // Number of labels vertically
  public $_Width = 0;                // Width of label
  public $_Height = 0;                // Height of label
  public $_Char_Size = 10;                // Character size
  public $_Line_Height = 10;                // Default line height
  public $_Metric = 'mm';                // Type of metric for labels.. Will help to calculate good values
  public $_Metric_Doc = 'mm';                // Type of metric for the document
  public $_Font_Name = 'Arial';            // Name of the font
  public $col = 0;
  public $_COUNTX = 1;
  public $_COUNTY = 1;

  // Listing of labels size
  public $_Avery_Labels = array(
    '5160' => array('name' => '5160', 'paper-size' => 'letter', 'metric' => 'mm', 'marginLeft' => 1.762, 'marginTop' => 10.7, 'NX' => 3, 'NY' => 10, 'SpaceX' => 3.175, 'SpaceY' => 0, 'width' => 66.675, 'height' => 25.4, 'font-size' => 8),
    '5161' => array('name' => '5161', 'paper-size' => 'letter', 'metric' => 'mm', 'marginLeft' => 0.967, 'marginTop' => 10.7, 'NX' => 2, 'NY' => 10, 'SpaceX' => 3.967, 'SpaceY' => 0, 'width' => 101.6, 'height' => 25.4, 'font-size' => 8),
    '5162' => array('name' => '5162', 'paper-size' => 'letter', 'metric' => 'mm', 'marginLeft' => 0.97, 'marginTop' => 20.224, 'NX' => 2, 'NY' => 7, 'SpaceX' => 4.762, 'SpaceY' => 0, 'width' => 100.807, 'height' => 35.72, 'font-size' => 8),
    '5163' => array('name' => '5163', 'paper-size' => 'letter', 'metric' => 'mm', 'marginLeft' => 1.762, 'marginTop' => 10.7, 'NX' => 2, 'NY' => 5, 'SpaceX' => 3.175, 'SpaceY' => 0, 'width' => 101.6, 'height' => 50.8, 'font-size' => 8),
    '5164' => array('name' => '5164', 'paper-size' => 'letter', 'metric' => 'in', 'marginLeft' => 0.148, 'marginTop' => 0.5, 'NX' => 2, 'NY' => 3, 'SpaceX' => 0.2031, 'SpaceY' => 0, 'width' => 4.0, 'height' => 3.33, 'font-size' => 12),
    '8600' => array('name' => '8600', 'paper-size' => 'letter', 'metric' => 'mm', 'marginLeft' => 7.1, 'marginTop' => 19, 'NX' => 3, 'NY' => 10, 'SpaceX' => 9.5, 'SpaceY' => 3.1, 'width' => 66.6, 'height' => 25.4, 'font-size' => 8),
    'L7163' => array('name' => 'L7163', 'paper-size' => 'A4', 'metric' => 'mm', 'marginLeft' => 5, 'marginTop' => 15, 'NX' => 2, 'NY' => 7, 'SpaceX' => 25, 'SpaceY' => 0, 'width' => 99.1, 'height' => 38.1, 'font-size' => 9),
    // Modified "Letter" from back in the old days. Gonna have 4 labels per sheet now..
    'Letter' => array('name' => 'Letter', 'paper-size' => 'letter', 'metric' => 'mm', 'marginLeft' => 5, 'marginTop' => 5, 'NX' => 2, 'NY' => 2, 'SpaceX' => 10, 'SpaceY' => 0, 'width' => 130, 'height' => 105, 'font-size' => 9),

  );

// convert units (in to mm, mm to in)
// $src and $dest must be 'in' or 'mm'
function _Convert_Metric($value, $src, $dest)
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
function _Get_Height_Chars($pt)
{
  // Array matching character sizes and line heights
  $_Table_Hauteur_Chars = array(6 => 2, 7 => 2.5, 8 => 3, 9 => 4, 10 => 5, 11 => 6, 12 => 7, 13 => 8, 14 => 9, 15 => 10);
  if (in_array($pt, array_keys($_Table_Hauteur_Chars))) {
    return $_Table_Hauteur_Chars[$pt];
  } else {
    return 100; // There is a prob..
  }
}

function _Set_Format($format)
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
function PDF_Label($format, $unit = 'mm', $posX = 1, $posY = 1)
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

  // this is code128 constructor code
  $this->T128[] = array(2, 1, 2, 2, 2, 2);           //0 : [ ]               // composition des caractères
  $this->T128[] = array(2, 2, 2, 1, 2, 2);           //1 : [!]
  $this->T128[] = array(2, 2, 2, 2, 2, 1);           //2 : ["]
  $this->T128[] = array(1, 2, 1, 2, 2, 3);           //3 : [#]
  $this->T128[] = array(1, 2, 1, 3, 2, 2);           //4 : [$]
  $this->T128[] = array(1, 3, 1, 2, 2, 2);           //5 : [%]
  $this->T128[] = array(1, 2, 2, 2, 1, 3);           //6 : [&]
  $this->T128[] = array(1, 2, 2, 3, 1, 2);           //7 : [']
  $this->T128[] = array(1, 3, 2, 2, 1, 2);           //8 : [(]
  $this->T128[] = array(2, 2, 1, 2, 1, 3);           //9 : [)]
  $this->T128[] = array(2, 2, 1, 3, 1, 2);           //10 : [*]
  $this->T128[] = array(2, 3, 1, 2, 1, 2);           //11 : [+]
  $this->T128[] = array(1, 1, 2, 2, 3, 2);           //12 : [,]
  $this->T128[] = array(1, 2, 2, 1, 3, 2);           //13 : [-]
  $this->T128[] = array(1, 2, 2, 2, 3, 1);           //14 : [.]
  $this->T128[] = array(1, 1, 3, 2, 2, 2);           //15 : [/]
  $this->T128[] = array(1, 2, 3, 1, 2, 2);           //16 : [0]
  $this->T128[] = array(1, 2, 3, 2, 2, 1);           //17 : [1]
  $this->T128[] = array(2, 2, 3, 2, 1, 1);           //18 : [2]
  $this->T128[] = array(2, 2, 1, 1, 3, 2);           //19 : [3]
  $this->T128[] = array(2, 2, 1, 2, 3, 1);           //20 : [4]
  $this->T128[] = array(2, 1, 3, 2, 1, 2);           //21 : [5]
  $this->T128[] = array(2, 2, 3, 1, 1, 2);           //22 : [6]
  $this->T128[] = array(3, 1, 2, 1, 3, 1);           //23 : [7]
  $this->T128[] = array(3, 1, 1, 2, 2, 2);           //24 : [8]
  $this->T128[] = array(3, 2, 1, 1, 2, 2);           //25 : [9]
  $this->T128[] = array(3, 2, 1, 2, 2, 1);           //26 : [:]
  $this->T128[] = array(3, 1, 2, 2, 1, 2);           //27 : [;]
  $this->T128[] = array(3, 2, 2, 1, 1, 2);           //28 : [<]
  $this->T128[] = array(3, 2, 2, 2, 1, 1);           //29 : [=]
  $this->T128[] = array(2, 1, 2, 1, 2, 3);           //30 : [>]
  $this->T128[] = array(2, 1, 2, 3, 2, 1);           //31 : [?]
  $this->T128[] = array(2, 3, 2, 1, 2, 1);           //32 : [@]
  $this->T128[] = array(1, 1, 1, 3, 2, 3);           //33 : [A]
  $this->T128[] = array(1, 3, 1, 1, 2, 3);           //34 : [B]
  $this->T128[] = array(1, 3, 1, 3, 2, 1);           //35 : [C]
  $this->T128[] = array(1, 1, 2, 3, 1, 3);           //36 : [D]
  $this->T128[] = array(1, 3, 2, 1, 1, 3);           //37 : [E]
  $this->T128[] = array(1, 3, 2, 3, 1, 1);           //38 : [F]
  $this->T128[] = array(2, 1, 1, 3, 1, 3);           //39 : [G]
  $this->T128[] = array(2, 3, 1, 1, 1, 3);           //40 : [H]
  $this->T128[] = array(2, 3, 1, 3, 1, 1);           //41 : [I]
  $this->T128[] = array(1, 1, 2, 1, 3, 3);           //42 : [J]
  $this->T128[] = array(1, 1, 2, 3, 3, 1);           //43 : [K]
  $this->T128[] = array(1, 3, 2, 1, 3, 1);           //44 : [L]
  $this->T128[] = array(1, 1, 3, 1, 2, 3);           //45 : [M]
  $this->T128[] = array(1, 1, 3, 3, 2, 1);           //46 : [N]
  $this->T128[] = array(1, 3, 3, 1, 2, 1);           //47 : [O]
  $this->T128[] = array(3, 1, 3, 1, 2, 1);           //48 : [P]
  $this->T128[] = array(2, 1, 1, 3, 3, 1);           //49 : [Q]
  $this->T128[] = array(2, 3, 1, 1, 3, 1);           //50 : [R]
  $this->T128[] = array(2, 1, 3, 1, 1, 3);           //51 : [S]
  $this->T128[] = array(2, 1, 3, 3, 1, 1);           //52 : [T]
  $this->T128[] = array(2, 1, 3, 1, 3, 1);           //53 : [U]
  $this->T128[] = array(3, 1, 1, 1, 2, 3);           //54 : [V]
  $this->T128[] = array(3, 1, 1, 3, 2, 1);           //55 : [W]
  $this->T128[] = array(3, 3, 1, 1, 2, 1);           //56 : [X]
  $this->T128[] = array(3, 1, 2, 1, 1, 3);           //57 : [Y]
  $this->T128[] = array(3, 1, 2, 3, 1, 1);           //58 : [Z]
  $this->T128[] = array(3, 3, 2, 1, 1, 1);           //59 : [[]
  $this->T128[] = array(3, 1, 4, 1, 1, 1);           //60 : [\]
  $this->T128[] = array(2, 2, 1, 4, 1, 1);           //61 : []]
  $this->T128[] = array(4, 3, 1, 1, 1, 1);           //62 : [^]
  $this->T128[] = array(1, 1, 1, 2, 2, 4);           //63 : [_]
  $this->T128[] = array(1, 1, 1, 4, 2, 2);           //64 : [`]
  $this->T128[] = array(1, 2, 1, 1, 2, 4);           //65 : [a]
  $this->T128[] = array(1, 2, 1, 4, 2, 1);           //66 : [b]
  $this->T128[] = array(1, 4, 1, 1, 2, 2);           //67 : [c]
  $this->T128[] = array(1, 4, 1, 2, 2, 1);           //68 : [d]
  $this->T128[] = array(1, 1, 2, 2, 1, 4);           //69 : [e]
  $this->T128[] = array(1, 1, 2, 4, 1, 2);           //70 : [f]
  $this->T128[] = array(1, 2, 2, 1, 1, 4);           //71 : [g]
  $this->T128[] = array(1, 2, 2, 4, 1, 1);           //72 : [h]
  $this->T128[] = array(1, 4, 2, 1, 1, 2);           //73 : [i]
  $this->T128[] = array(1, 4, 2, 2, 1, 1);           //74 : [j]
  $this->T128[] = array(2, 4, 1, 2, 1, 1);           //75 : [k]
  $this->T128[] = array(2, 2, 1, 1, 1, 4);           //76 : [l]
  $this->T128[] = array(4, 1, 3, 1, 1, 1);           //77 : [m]
  $this->T128[] = array(2, 4, 1, 1, 1, 2);           //78 : [n]
  $this->T128[] = array(1, 3, 4, 1, 1, 1);           //79 : [o]
  $this->T128[] = array(1, 1, 1, 2, 4, 2);           //80 : [p]
  $this->T128[] = array(1, 2, 1, 1, 4, 2);           //81 : [q]
  $this->T128[] = array(1, 2, 1, 2, 4, 1);           //82 : [r]
  $this->T128[] = array(1, 1, 4, 2, 1, 2);           //83 : [s]
  $this->T128[] = array(1, 2, 4, 1, 1, 2);           //84 : [t]
  $this->T128[] = array(1, 2, 4, 2, 1, 1);           //85 : [u]
  $this->T128[] = array(4, 1, 1, 2, 1, 2);           //86 : [v]
  $this->T128[] = array(4, 2, 1, 1, 1, 2);           //87 : [w]
  $this->T128[] = array(4, 2, 1, 2, 1, 1);           //88 : [x]
  $this->T128[] = array(2, 1, 2, 1, 4, 1);           //89 : [y]
  $this->T128[] = array(2, 1, 4, 1, 2, 1);           //90 : [z]
  $this->T128[] = array(4, 1, 2, 1, 2, 1);           //91 : [{]
  $this->T128[] = array(1, 1, 1, 1, 4, 3);           //92 : [|]
  $this->T128[] = array(1, 1, 1, 3, 4, 1);           //93 : [}]
  $this->T128[] = array(1, 3, 1, 1, 4, 1);           //94 : [~]
  $this->T128[] = array(1, 1, 4, 1, 1, 3);           //95 : [DEL]
  $this->T128[] = array(1, 1, 4, 3, 1, 1);           //96 : [FNC3]
  $this->T128[] = array(4, 1, 1, 1, 1, 3);           //97 : [FNC2]
  $this->T128[] = array(4, 1, 1, 3, 1, 1);           //98 : [SHIFT]
  $this->T128[] = array(1, 1, 3, 1, 4, 1);           //99 : [Cswap]
  $this->T128[] = array(1, 1, 4, 1, 3, 1);           //100 : [Bswap]
  $this->T128[] = array(3, 1, 1, 1, 4, 1);           //101 : [Aswap]
  $this->T128[] = array(4, 1, 1, 1, 3, 1);           //102 : [FNC1]
  $this->T128[] = array(2, 1, 1, 4, 1, 2);           //103 : [Astart]
  $this->T128[] = array(2, 1, 1, 2, 1, 4);           //104 : [Bstart]
  $this->T128[] = array(2, 1, 1, 2, 3, 2);           //105 : [Cstart]
  $this->T128[] = array(2, 3, 3, 1, 1, 1);           //106 : [STOP]
  $this->T128[] = array(2, 1);                       //107 : [END BAR]

  for ($i = 32; $i <= 95; $i++) {                                            // jeux de caractères
      $this->ABCset .= chr($i);
  }
  $this->Aset = $this->ABCset;
  $this->Bset = $this->ABCset;

  for ($i = 0; $i <= 31; $i++) {
      $this->ABCset .= chr($i);
      $this->Aset .= chr($i);
  }
  for ($i = 96; $i <= 127; $i++) {
      $this->ABCset .= chr($i);
      $this->Bset .= chr($i);
  }
  for ($i = 200; $i <= 210; $i++) {                                           // controle 128
      $this->ABCset .= chr($i);
      $this->Aset .= chr($i);
      $this->Bset .= chr($i);
  }
  $this->Cset="0123456789".chr(206);

  for ($i=0; $i<96; $i++) {                                                   // convertisseurs des jeux A & B
      @$this->SetFrom["A"] .= chr($i);
      @$this->SetFrom["B"] .= chr($i + 32);
      @$this->SetTo["A"] .= chr(($i < 32) ? $i+64 : $i-32);
      @$this->SetTo["B"] .= chr($i);
  }
  for ($i=96; $i<107; $i++) {                                                 // contrôle des jeux A & B
      @$this->SetFrom["A"] .= chr($i + 104);
      @$this->SetFrom["B"] .= chr($i + 104);
      @$this->SetTo["A"] .= chr($i);
      @$this->SetTo["B"] .= chr($i);
  }
}

// Sets the character size
// This changes the line height too
function Set_Font_Size($pt)
{
  if ($pt > 3) {
    $this->_Char_Size = $pt;
    $this->_Line_Height = $this->_Get_Height_Chars($pt);
    $this->SetFontSize($this->_Char_Size);
  }
}

// Method to change font name
function Set_Font_Name($fontname)
{
  if ($fontname != '') {
    $this->_Font_Name = $fontname;
    $this->SetFont($this->_Font_Name);
  }
}


function SetCol($col)
{
  //Move position to a column
  $this->col = $col;
  $x = 10+$col*160;
  $this->SetLeftMargin($x);
  $this->SetX($x);
}

function AcceptPageBreak()
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

function Rotate($angle=0,$x=-1,$y=-1)
{
    if($x==-1)
        $x=$this->x;
    if($y==-1)
        $y=$this->y;
    if($this->angle!=0)
        $this->_out('Q');
    $this->angle=$angle;
    if($angle!=0)
    {
        $angle*=M_PI/180;
        $c=cos($angle);
        $s=sin($angle);
        $cx=$x*$this->k;
        $cy=($this->h-$y)*$this->k;
        $this->_out(sprintf('q %.5F %.5F %.5F %.5F %.2F %.2F cm 1 0 0 1 %.2F %.2F cm',$c,$s,-$s,$c,$cx,$cy,-$cx,-$cy));
    }
}
// Print a label
function Add_PDF_Label($texte)
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

// BEGIN Code128 Stuff
var $T128;                                             // tableau des codes 128
var $ABCset="";                                        // jeu des caractères éligibles au C128
var $Aset="";                                          // Set A du jeu des caractères éligibles
var $Bset="";                                          // Set B du jeu des caractères éligibles
var $Cset="";                                          // Set C du jeu des caractères éligibles
var $SetFrom;                                          // Convertisseur source des jeux vers le tableau
var $SetTo;                                            // Convertisseur destination des jeux vers le tableau
var $JStart = array("A"=>103, "B"=>104, "C"=>105);     // Caractères de sélection de jeu au début du C128
var $JSwap = array("A"=>101, "B"=>100, "C"=>99);       // Caractères de changement de jeu

//________________ Fonction encodage et dessin du code 128 _____________________
function Code128($x, $y, $code, $w, $h) {
    $Aguid = "";                                                                      // Création des guides de choix ABC
    $Bguid = "";
    $Cguid = "";
    for ($i=0; $i < strlen($code); $i++) {
        $needle = substr($code,$i,1);
        $Aguid .= ((strpos($this->Aset,$needle)===false) ? "N" : "O");
        $Bguid .= ((strpos($this->Bset,$needle)===false) ? "N" : "O");
        $Cguid .= ((strpos($this->Cset,$needle)===false) ? "N" : "O");
    }

    $SminiC = "OOOO";
    $IminiC = 4;

    $crypt = "";
    while ($code > "") {
                                                                                    // BOUCLE PRINCIPALE DE CODAGE
        $i = strpos($Cguid,$SminiC);                                                // forçage du jeu C, si possible
        if ($i!==false) {
            $Aguid [$i] = "N";
            $Bguid [$i] = "N";
        }

        if (substr($Cguid,0,$IminiC) == $SminiC) {                                  // jeu C
            $crypt .= chr(($crypt > "") ? $this->JSwap["C"] : $this->JStart["C"]);  // début Cstart, sinon Cswap
            $made = strpos($Cguid,"N");                                             // étendu du set C
            if ($made === false) {
                $made = strlen($Cguid);
            }
            if (fmod($made,2)==1) {
                $made--;                                                            // seulement un nombre pair
            }
            for ($i=0; $i < $made; $i += 2) {
                $crypt .= chr(strval(substr($code,$i,2)));                          // conversion 2 par 2
            }
            $jeu = "C";
        } else {
            $madeA = strpos($Aguid,"N");                                            // étendu du set A
            if ($madeA === false) {
                $madeA = strlen($Aguid);
            }
            $madeB = strpos($Bguid,"N");                                            // étendu du set B
            if ($madeB === false) {
                $madeB = strlen($Bguid);
            }
            $made = (($madeA < $madeB) ? $madeB : $madeA );                         // étendu traitée
            $jeu = (($madeA < $madeB) ? "B" : "A" );                                // Jeu en cours

            $crypt .= chr(($crypt > "") ? $this->JSwap[$jeu] : $this->JStart[$jeu]); // début start, sinon swap

            $crypt .= strtr(substr($code, 0,$made), $this->SetFrom[$jeu], $this->SetTo[$jeu]); // conversion selon jeu

        }
        $code = substr($code,$made);                                           // raccourcir légende et guides de la zone traitée
        $Aguid = substr($Aguid,$made);
        $Bguid = substr($Bguid,$made);
        $Cguid = substr($Cguid,$made);
    }                                                                          // FIN BOUCLE PRINCIPALE

    $check = ord($crypt[0]);                                                   // calcul de la somme de contrôle
    for ($i=0; $i<strlen($crypt); $i++) {
        $check += (ord($crypt[$i]) * $i);
    }
    $check %= 103;

    $crypt .= chr($check) . chr(106) . chr(107);                               // Chaine Cryptée complète

    $i = (strlen($crypt) * 11) - 8;                                            // calcul de la largeur du module
    $modul = $w/$i;

    for ($i=0; $i<strlen($crypt); $i++) {                                      // BOUCLE D'IMPRESSION
        $c = $this->T128[ord($crypt[$i])];
        for ($j=0; $j<count($c); $j++) {
            $this->Rect($x,$y,$c[$j]*$modul,$h,"F");
            $x += ($c[$j++]+$c[$j])*$modul;
        }
    }
}
//END Code128 Stuff

//Print the FROM: portion of the label
function PrintFrom($toAddress, $fromAddress, $_PosX)
{
  // We will need to pad any lines at the bottom to make everything line up nice
  // in the case that there is missing data
  $pad = 0;

  $this->Image(DRUPAL_ROOT . '/' . drupal_get_path('module', 'labelmaker') . '/MOBIUS_logo.gif', $this->GetX()+85, $this->GetY(), 45);


  // "From" section title
  if (!preg_match('/MOB|IOWA/', $toAddress['interSort']) || !preg_match('/MOB|IOWA/', $fromAddress['interSort'])) {
	// frombar
	$shipmentID = uniqid();
	$this->Rotate(90, $this->GetX()+25,$this->GetY()+25);
	$this->SetFont('Arial', '', 8);
	$this->Code128($this->GetX(), $this->GetY(), $shipmentID, 50, 10);
	$this->SetXY($this->GetX(), $this->GetY()+10);
    	$this->Cell(50, 4, "BagID: " . $shipmentID, 0, 0, "C");	
	$this->Rotate(0);
	$barcodeMargin = 14;
	#$this->Cell($_PosX+30, $_PosX+20, "BagID: ". $shipmentID, 0, 1, 'C');
  	$this->SetXY($this->GetX(), $this->GetY()-10);	
  }
  // Title font: Arial bold 15
  $this->SetFont('Arial', 'B', 12);
  $this->SetX($_PosX+$margin+$barcodeMargin);
  $this->Cell(30, 4, 'FROM: '.$fromAddress['locCode'], 0, 1);
  $this->Ln(1.5);

  // Set smaller font
  $this->SetFont('Arial', '', 8);

  // From Address - just using location name and city/state now
  $margin = $_PosX;
  $lineHeight = 3.5;
  if ($fromAddress['locName']) {
    $this->Cell($margin+$barcodeMargin);
    $this->Cell($_PosX+30, $lineHeight, substr($fromAddress['locName'], 0, 50), 0, 1);
  } else {
    $pad++;
  }
  if ($fromAddress['city'] && $fromAddress['state']) {
    $this->Cell($margin+$barcodeMargin);
    $this->Cell($_PosX+30, $lineHeight, substr($fromAddress['city'], 0, 50).', '.$fromAddress['state'], 0, 1);
  } else {
    $pad++;
  }

  //Line breaks to push down the next section. Use $pad to make it even.
  $this->Ln($pad*4+16);
}

// Print the portion of the label
// We don't need to pad this because it's on the bottom
function PrintTo($toAddress, $fromAddress, $_PosX)
{

  if ($toAddress['interSort'] == 'MOB' && $fromAddress['interSort'] == 'MOB') {
    $labeltype = 'MOB';
  }

  // TO Header
  if (preg_match('/MOB|IOWA/', $toAddress['interSort']) && preg_match('/MOB|IOWA/', $fromAddress['interSort'])) {
    $this->SetFont('Arial', 'B', 42);
  } else {
    $this->SetFont('Arial', 'B', 32);
    $this->Ln(12);
  }

  // Get the cursor all the way to the right. We will set Cells at 50% width exactly
  // then center the From Title;
  if ($_PosX >= 142.5) {
    $this->SetX(142.5);
  } else {
    $this->SetX(0);
  }

  if (preg_match('/MOB|IOWA/', $toAddress['interSort']) && preg_match('/MOB|IOWA/',$fromAddress['interSort'])) {
    $shipmentID = strtoupper($toAddress['statCode'] . '_' . uniqid());

    $this->SetXY($this->GetX()+10, $this->GetY()-5);
    $qrcode = new QRcode ($shipmentID, 'H'); // Error level: L, M, Q, H
    $qrcode->disableBorder();
    $qrcode->displayFPDF($this, $this->GetX(), $this->GetY(), '30', array(255,255,255), array(0,0,0,0));

    $this->SetXY($this->GetX()+30, $this->GetY()+5);
    $this->Cell(102.5, 12, $toAddress['statCode'], 0, 1, 'C');
    //$this->SetXY($this->GetX(), $this->GetY());
    if ($_PosX >= 142.5) {
      $this->SetX(142.5);
    } else {
      $this->SetX(0);
    }
    $this->SetFont('Arial', 'B', 10);
    $this->SetXY($this->GetX()+40, $this->GetY()+2);
    if($toAddress['locCode']) {
      $tmpCode = " ({$toAddress['locCode']})";
    }
    $this->Cell(102.5, 8, $toAddress['locName'] . $tmpCode, 0, 1, 'C');
    if ($_PosX >= 142.5) {
      $this->SetX(142.5);
    } else {
      $this->SetX(0);
    }
    $this->SetXY($this->GetX()+40, $this->GetY()-2);
    $this->Cell(102.5, 8, $shipmentID, 0, 1, 'C');
  } elseif (preg_match('/MOB|IOWA/', $toAddress['interSort']) && preg_match('/MOB|IOWA/',$fromAddress['interSort'])) {
    $this->SetFont('Arial', 'B', 42);
    $this->Cell(142.5, 12, $toAddress['interSort'].':'.$toAddress['statCode'], 0, 1, 'C');
    $this->SetFont('Arial', 'B', 10);
  } elseif ($fromAddress['interSort'] == 'TAE' && preg_match('/MOB|IOWA|MALA|CLC/', $toAddress['interSort'])) {
    $this->SetFont('Arial', 'B', 30);
    if ($toAddress['interSort'] == 'MALA') {
     $this->Cell(142.5, 12, $toAddress['interSort'].'/'.$toAddress['sortCode'], 0, 1, 'C');
    } elseif ($toAddress['interSort'] == 'CLC') {
     $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['sortCode'], 0, 1, 'C');
    } else {
     $this->Cell(142.5, 12, $toAddress['interSort'].':'.$toAddress['statCode'], 0, 1, 'C');
    }
    $this->SetFont('Arial', 'B', 10);
  } elseif ($toAddress['interSort'] == 'CLC') {
    $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['sortCode'], 0, 1, 'C');
  } elseif ($toAddress['interSort'] == 'MALA') {
    $this->Cell(142.5, 12, $toAddress['interSort'].'/'.$toAddress['sortCode'], 0, 1, 'C');
  } elseif ($toAddress['interSort'] && $toAddress['locCode']) {
    $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['locCode'].'/'.$toAddress['sortCode'], 0, 1, 'C');
  } elseif ($toAddress['interSort'] && $toAddress['sortCode']) {
    $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['sortCode'], 0, 1, 'C');
  } else {
    $this->Cell(142.5, 12, $toAddress['interSort'].': '.$toAddress['locCode'], 0, 1, 'C');
  }

  //$this->Ln(2); // Pad the address at the top a little bit

  if (preg_match('/MOB|IOWA/', $toAddress['interSort']) && preg_match('/MOB|IOWA/', $fromAddress['interSort'])) {
    //$lineHeight = 5;
    $longLength = 40;
    $maxLength = 50;

    if ($_PosX >= 142.5) {
      $this->SetX(172.5);
    } else {
      $this->SetX(30);
    }

    $this->SetXY($this->GetX(), $this->GetY()+10);
    $barcode = $this->Code128($this->GetX(), $this->GetY(), $shipmentID, 82.5, 20);

    //$this->SetXY($this->GetX(), $this->GetY()+30);
    if ($_PosX >= 142.5) {
      $this->SetX(142.5);
    } else {
      $this->SetX(0);
    }
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
      if ($toAddress['locCode']) {
        $this->Cell($_PosX+30, $lineHeight, $toAddress['locName'] . " (" .  $toAddress['locCode'] .")", 0, 1);
        $this->SetFontSize(11);
      } else {
        $this->Cell($_PosX+30, $lineHeight, $toAddress['locName'], 0, 1);
        $this->SetFontSize(11);
      } 
    }

    if ($toAddress['address1'] && !preg_match('/MOB|IOWA/',$toAddress['interSort'])) {
      $this->Cell($margin, '', '', 2);
      if (strlen(substr($toAddress['address1'], 0, $maxLength)) > $longLength) {
        $this->SetFontSize(9);
      }
      $this->Cell($_PosX+30, $lineHeight, $toAddress['address1'], 0, 1);
      $this->SetFontSize(11);
    }

    if ($toAddress['address2'] && !preg_match('/MOB|IOWA/', $toAddress['interSort'])) {
      $this->Cell($margin, '', '', 2);
      if (strlen(substr($toAddress['address2'], 0, $maxLength)) > $longLength) {
        $this->SetFontSize(9);
      }
      $this->Cell($_PosX+30, $lineHeight, $toAddress['address2'], 0, 1);
      $this->SetFontSize(11);
    }

    if ($toAddress['city'] && $toAddress['state'] && !preg_match('/MOB|IOWA/', $toAddress['interSort'])) {
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

function PrintSortCode($sortCode, $_PosX)
{
  $this->Cell($_PosX+95);
  $this->SetFont('Arial', 'B', 12);
  $this->Cell(30, 6, $sortCode, 0, 1, R);
  //$this->Ln(7);
}

function PrintLabel($fromAddress, $toAddress)
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

  $this->MultiCell($this->_Width, $this->_Line_Height, $this->PrintFrom($toAddress, $fromAddress, $_PosX).$this->PrintTo($toAddress, $fromAddress, $_PosX));

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

function get_to()
{
  $to_id = $_POST['to_id'];
  $toArray = array();
  foreach ($to_id as $to) {
    $query = "SELECT * FROM label_maker_nodes WHERE id={$to}  ORDER BY locName";
    $result = db_query($query);
    $institution = json_decode(json_encode($result->fetchAllAssoc('id')), True);
    //file_put_contents('php://stderr', print_r($institution[$to], TRUE));
    $filterArgs = array(
      'locCode' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'statCode' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'locName' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'address1' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'address2' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'city' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'state' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'zip' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'sortCode' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ),
      'interSort' => array(
        'filter' => FILTER_SANITIZE_STRING,
        'flags' => FILTER_FLAG_STRIP_LOW,
      ), );

    $toArray[] = filter_var_array($institution[$to], $filterArgs);
  }
  return $toArray;
}

function get_from()
{
  $from_id = $_POST['from_id'];
  $query = "SELECT * FROM label_maker_nodes WHERE id={$_POST['from_id']}  ORDER BY locName";
  $result = db_query($query);
  $fromArray = json_decode(json_encode($result->fetchAllAssoc('id')), True);

  $filterArgs = array(
    'locCode' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'locName' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'address1' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'address2' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'city' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'state' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'zip' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'sortCode' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
    'interSort' => array(
      'filter' => FILTER_SANITIZE_STRING,
      'flags' => FILTER_FLAG_STRIP_LOW,
    ),
  );

  return filter_var_array($fromArray[$from_id], $filterArgs);
}

/*-------------------------------------------------
To create the object, 2 possibilities:
either pass a custom format via an array
or use a built-in AVERY name
-------------------------------------------------*/

// Example of custom format; we start at the second column
//$pdf = new PDF_Label(array('name'=>'perso1', 'paper-size'=>'A4', 'marginLeft'=>1, 'marginTop'=>1, 'NX'=>2, 'NY'=>7, 'SpaceX'=>0, 'SpaceY'=>0, 'width'=>99.1, 'height'=>38.1, 'metric'=>'mm', 'font-size'=>14), 1, 2);
// Standard format
$pdf = new PDF_Label('Letter', 'mm', 1, 1);

//$pdf->Open();

//check for required fields
if ($_POST['from_id'] == '' || $_POST['to_id'] == '') {
  drupal_set_message('Both the FROM and TO fields are required.', 'error');
  drupal_goto(DRUPAL_ROOT . '/' . drupal_get_path('module', 'labelmaker'), array('from_id' => $_POST['from_id'], 'to_id' => $_POST['to_id'], 'quantity' => $_POST['quantity']));
}

ob_start();
// Print labels
if ($_POST) {
  $fromArray = get_from();
  $toArray = get_to();
  $quantity = $_POST['quantity'];

  for ($i = 0;$i<sizeof(get_to());$i++) {
    for ($q = 0;$q<$quantity;$q++) {
      $pdf->PrintLabel($fromArray, $toArray[$i]);
    }
  }
  $pdf->Output('MOBIUS-Label.pdf', 'D');
}
ob_end_flush();
?>
