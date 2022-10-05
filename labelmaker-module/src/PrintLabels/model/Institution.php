<?php

/**
 * A POPO modeled after the label_maker_nodes database table.
 */
class Institution {

  public int $id;

  public int $is_stop;

  public string $statCode;

  public string $locCode;

  public string $oclcSymbol;

  public string $locName;

  public string $address1;

  public string $address2;

  public string $city;

  public string $state;

  public string $zip;

  public string $sortCode;

  public string $interSort;

  public string $permittedTo;

}

