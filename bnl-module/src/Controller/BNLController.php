<?php /** @noinspection PhpArrayShapeAttributeCanBeAddedInspection */

namespace Drupal\bnl\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Render\HtmlResponse;
use Symfony\Component\HttpFoundation\Request;

class BNLController extends ControllerBase {

  public function __construct() {
  }

  public function getTwigTemplate(): array {

    $BNLAbsolutePath = \Drupal::service('extension.list.module')
      ->getPath('bnl');

    return [
      '#theme' => 'bnl',
      '#path' => $BNLAbsolutePath,
    ];

  }


}
