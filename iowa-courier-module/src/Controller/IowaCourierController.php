<?php /** @noinspection PhpArrayShapeAttributeCanBeAddedInspection */

namespace Drupal\iowacourier\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\iowacourier\Service\IowaCourierService;

class IowaCourierController extends ControllerBase {

  public IowaCourierService $iowaCourierService;

  public function __construct() {
    $this->iowaCourierService = new IowaCourierService();
  }


  public function getTwigTemplate(): array {


    $varColDump = $this->iowaCourierService->mobius_iowacourier_generateHTMLTable();

    $html = '

    <h3>Important note:</h3>
<p>
Libraries can update individual library information in the State Library of Iowa\'s <a href="https://www.statelibraryofiowa.org/ld/c-d/directories/index">Iowa Library Directory</a>, and the information will appear on this page. </br>
Pick-up/delivery times may vary slightly from what is listed on this page.</p>
<h3>How to navigate this page:</h3>
<ul>
<li>Clicking on the name of the library will display information about that library as it appears in the State Library of Iowa’s Iowa Library Directory.</li>
<li>Click each column to sort in ascending or descending order.</li>
<li>Click on the route number to display all the libraries who share that route and a map showing the route.</li>
<li>Use the search box to search all the data, such as county, route number, etc.</li>
</ul>
     ' . $varColDump;


    return [
      '#theme' => 'iowacourier',
      '#html' => $html,
    ];

  }

}
