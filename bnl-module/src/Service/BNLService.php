<?php


namespace Drupal\bnl\Service;

use Drupal\Core\Controller\ControllerBase;
use Symfony\Component\HttpFoundation\JsonResponse;

class BNLService extends ControllerBase {

  public function __construct() {
  }

  public function mobius_bnl_postback() {

    $data_array = [];
    if (isset($_GET['startdate']) && isset($_GET['enddate'])) {
      $clusters = [
        'owning' => ($_GET['cluster_owning'] ? $_GET['cluster_owning'] : ''),
        'borrowing' => ($_GET['cluster_borrowing'] ? $_GET['cluster_borrowing'] : ''),
      ];
      $clusters['owning'] .= ($_GET['system_owning'] ? ',' . $_GET['system_owning'] : '');
      $clusters['borrowing'] .= ($_GET['system_borrowing'] ? ',' . $_GET['system_borrowing'] : '');
      $clusters['owning'] = preg_replace('/^,?(.*)/', '$1', $clusters['owning']);
      $clusters['borrowing'] = preg_replace('/^,?(.*)/', '$1', $clusters['borrowing']);

      $branchArray = [
        'bnl_owning_name.id' => $_GET['branch_owning'],
        'bnl_borrowing_name.id' => $_GET['branch_borrowing'],
        'owning_cluster_ids.cid' => $clusters['owning'],
        'borrowing_cluster_ids.cid' => $clusters['borrowing'],
      ];

      if (isset($_GET['percentage'])) {
        $this->mobius_bnl_get_bnl_percentage($data_array, $_GET['startdate'], $_GET['enddate'], $branchArray);
      }
      else {
        $this->mobius_bnl_get_bnl_base($data_array, $_GET['startdate'], $_GET['enddate'], $branchArray);
      }

      return new JsonResponse($data_array);

    }

    else {
      if (isset($_GET['get_branches'])) {

        $this->mobius_bnl_get_all_branches($data_array);

        return new JsonResponse($data_array);
      }
      else {
        if (isset($_GET['get_data_date_range'])) {
          $this->mobius_bnl_get_data_date_ranges($data_array);
          return new JsonResponse($data_array);
        }
      }
    }

  }

  public function mobius_bnl_get_data_date_ranges(&$data_array) {
    $database = \Drupal::database();
    $data_array["date_start"] = "";
    $data_array["date_end"] = "";
    $query = $database->query("SELECT 'min' as \"type\",DATE_FORMAT(MIN(borrow_date), '%m/%Y') as \"date\" from mobius_bnl_bnl UNION ALL SELECT 'max' as \"type\",DATE_FORMAT(MAX(borrow_date), '%m/%Y') as \"date\" from mobius_bnl_bnl ");

    while ($libraryRow = $query->fetchAssoc()) {
      if ($libraryRow["type"] == "min") {
        $data_array["date_start"] = $libraryRow["date"];
      }
      else {
        $data_array["date_end"] = $libraryRow["date"];
      }
    }

  }

  public function mobius_bnl_get_all_branches(&$data_array) {
    $data_array["branch"] = [];
    $data_array["cluster"] = [];
    $data_array["branch_to_cluster"] = [];
    $data_array["branch_order"] = [];
    $data_array["suppressed_branch"] = [];
    $used = [];

    $database = \Drupal::database();

    // First get the overall branch names and clusters to which they belong
    $query = $database->query("SELECT fid,fname,cid,cname,ctype FROM mobius_bnl_branch_connection_map order by lower(fname)");

    while ($libraryRow = $query->fetchAssoc()) {
      // Record the order
      if (!$used[$libraryRow["fid"]]) {
        $used[$libraryRow["fid"]] = 1;
        $data_array["branch_order"][] = $libraryRow["fid"];
      }
      // Record the branches
      if (!$data_array["branch"][$libraryRow["fid"]]) {
        $data_array["branch"][$libraryRow["fid"]] = $libraryRow["fname"];
      }
      // Record the Clusters
      if (!$data_array["cluster"][$libraryRow["cid"]]) {
        $data_array["cluster"][$libraryRow["cid"]] = [
          'name' => $libraryRow["cname"],
          'type' => $libraryRow["ctype"],
        ];
      }

      // Connect branches to clusters
      if (!$data_array["branch_to_cluster"][$libraryRow["fid"]]) {
        $data_array["branch_to_cluster"][$libraryRow["fid"]] = [];
      }
      $data_array["branch_to_cluster"][$libraryRow["fid"]][$libraryRow["cid"]] = 1;
    }

    // Now gather the names that should not be displayed

    $query = $database->query("SELECT name FROM mobius_bnl_suppress_name_listing");

    while ($libraryRow = $query->fetchAssoc()) {
      if (!$data_array["suppressed_branch"][$libraryRow["name"]]) {
        $data_array["suppressed_branch"][$libraryRow["name"]] = 1;
      }
    }

  }

  public function mobius_bnl_get_bnl_base(&$data_array, $startDate, $endDate, $branchSelections) {

    $data_array["amount_branch"] = [];
    $data_array["amount_cluster"] = [];

    $gotmore = 1;
    $offset = 0;
    $chunk = 1000;
    $totalRows = 0;
    while ($gotmore > 0) {
      $columns = "";
      $vals = [$startDate, $endDate];

      $columns = "SELECT 'lent' as \"type\", bnl.borrow_date \"borrow_date\",
           bnl_borrowing_name.name \"borrowing_branch_name\", bnl_borrowing_name.id \"borrowing_branch_id\",
           bnl_owning_name.name \"owning_branch_name\", bnl_owning_name.id \"owning_branch_id\",
           (select min(cid) from mobius_bnl_branch_connection_map where fid=bnl_borrowing_branch.final_branch) \"borrowing_cluster_id\",
           (select min(cid) from mobius_bnl_branch_connection_map where fid=bnl_owning_branch.final_branch) \"owning_cluster_id\",
           sum(bnl.quantity) \"quantity\"";

      $fromClauseStart = "
            FROM
            mobius_bnl_bnl bnl,
            mobius_bnl_branch bnl_borrowing_branch,
            mobius_bnl_branch bnl_owning_branch,
            mobius_bnl_branch_name_final bnl_borrowing_name,
            mobius_bnl_branch_name_final bnl_owning_name
            WHERE
            bnl_borrowing_name.id = bnl_borrowing_branch.final_branch and
            bnl_owning_name.id = bnl_owning_branch.final_branch and
            bnl.borrowing_branch = bnl_borrowing_branch.id and
            bnl.owning_branch = bnl_owning_branch.id and
            bnl.borrow_date between str_to_date( concat(?,'-01') ,'%Y-%m-%d') and str_to_date( concat(?,'-01') ,'%Y-%m-%d')
            and bnl.quantity > 0
            ";

      $fromClause = $this->mobius_bnl_get_bnl_base_branches_from_clause($fromClauseStart, $vals, $branchSelections, 0);
      $groupClause = " group by 1,2,3,4,5,6,7,8";

      $query = $columns . $fromClause . $groupClause;

      $query .= "
        UNION ALL SELECT
           'borrow' as \"type\",
           bnl.borrow_date \"borrow_date\",
           bnl_borrowing_name.name \"borrowing_branch_name\", bnl_borrowing_name.id \"borrowing_branch_id\",
           bnl_owning_name.name \"owning_branch_name\", bnl_owning_name.id \"owning_branch_id\",
           (select min(cid) from mobius_bnl_branch_connection_map where fid=bnl_borrowing_branch.final_branch) \"borrowing_cluster_id\",
           (select min(cid) from mobius_bnl_branch_connection_map where fid=bnl_owning_branch.final_branch) \"owning_cluster_id\",
           sum(bnl.quantity) \"quantity\"";
      $vals[] = $startDate;
      $vals[] = $endDate;
      $fromClause = $this->mobius_bnl_get_bnl_base_branches_from_clause($fromClauseStart, $vals, $branchSelections, 1);
      $query .= $fromClause . $groupClause;

      $query .= "
            limit $chunk
            offset $offset";
      $bnl_def =
        [
          "lent" => [
            "inner" => "borrowing_branch_id",
            "outter" => "owning_branch_id",
          ],
          "borrow" => [
            "inner" => "owning_branch_id",
            "outter" => "borrowing_branch_id",
          ],
        ];
      if ($this->mobius_bnl_figure_specified_branches($branchSelections) == 1)  // Need to reverse if they only specified borrowing libraries
      {
        $bnl_def =
          [
            "borrow" => [
              "inner" => "borrowing_branch_id",
              "outter" => "owning_branch_id",
            ],
            "lent" => [
              "inner" => "owning_branch_id",
              "outter" => "borrowing_branch_id",
            ],
          ];
      }
      if ($this->mobius_bnl_figure_specified_branches($branchSelections) == 2)  // If they specified libraries on both sides, then leave it standard
      {
        $bnl_def =
          [
            "lent" => [
              "inner" => "borrowing_branch_id",
              "outter" => "owning_branch_id",
            ],
            "borrow" => [
              "inner" => "owning_branch_id",
              "outter" => "borrowing_branch_id",
            ],
          ];
      }


      $database = \Drupal::database();
      $result = $database->query($query, $vals);

      $gotmore = 0;
      while ($libraryRow = $result->fetchAssoc()) {

        $gotmore++;
        $outter = $libraryRow[$bnl_def[$libraryRow["type"]]["outter"]];
        $inner = $libraryRow[$bnl_def[$libraryRow["type"]]["inner"]];

        if (!$data_array[$libraryRow["type"]]) {
          $data_array[$libraryRow["type"]] = [];
        }
        if (!$data_array[$libraryRow["type"]][$libraryRow["borrow_date"]]) {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]] = [];
        }
        if (!$data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$outter]) {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$outter] = [];
        }
        if (!$data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$outter][$inner]) {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$outter][$inner] = ($libraryRow["quantity"] + 0);
        }
        else {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$outter][$inner] += ($libraryRow["quantity"] + 0);
        }

        // Add up totals for each whole cluster
        if (!$data_array["amount_cluster"][$libraryRow["borrowing_cluster_id"]]) {
          $data_array["amount_cluster"][$libraryRow["borrowing_cluster_id"]] = [];
        }
        if (!$data_array["amount_cluster"][$libraryRow["borrowing_cluster_id"]][$libraryRow["owning_cluster_id"]]) {
          $data_array["amount_cluster"][$libraryRow["borrowing_cluster_id"]][$libraryRow["owning_cluster_id"]] = ($libraryRow["quantity"] + 0);
        }
        else {
          $data_array["amount_cluster"][$libraryRow["borrowing_cluster_id"]][$libraryRow["owning_cluster_id"]] += ($libraryRow["quantity"] + 0);
        }

        unset($outter);
        unset($inner);
      }

      $totalRows += $gotmore;
# if we didn't receive a full chunk of data, then we don't need to go back to the database for more.
      if ($gotmore < $chunk)
      {
        $gotmore = 0;
      }
      unset($rows);
      unset($result);
      $offset += $chunk;
    }
    $data_array["query"] = $query;
    $data_array["result_rows"] = $totalRows;
  }

  public function mobius_bnl_get_bnl_percentage(&$data_array, $startDate, $endDate, $branchSelections) {

    $data_array["amount_branch"] = [];
    $data_array["amount_cluster"] = [];

    $gotmore = 1;
    $offset = 0;
    $chunk = 1000;
    $totalRows = 0;
    while ($gotmore > 0) {
      $columns = "";
      $vals = [$startDate, $endDate, $startDate, $endDate];
      $replacements = [
        "lent" => [
          "!!!type!!!" => "lent",
          "!!!column_var!!!" => "bnl_owning_name",
          "!!!total_lib_var!!!" => "owning_id",
          "!!!where_var!!!" => "bnl_borrowing_name",
        ],
        "borrow" => [
          "!!!type!!!" => "borrow",
          "!!!column_var!!!" => "bnl_borrowing_name",
          "!!!total_lib_var!!!" => "borrowing_id",
          "!!!where_var!!!" => "bnl_owning_name",
        ],
      ];
      if ($this->mobius_bnl_figure_specified_branches($branchSelections) == 1) {
        $replacements = [
          "lent" => [
            "!!!type!!!" => "lent",
            "!!!column_var!!!" => "bnl_borrowing_name",
            "!!!total_lib_var!!!" => "borrowing_id",
            "!!!where_var!!!" => "bnl_owning_name",
          ],
          "borrow" => [
            "!!!type!!!" => "borrow",
            "!!!column_var!!!" => "bnl_owning_name",
            "!!!total_lib_var!!!" => "owning_id",
            "!!!where_var!!!" => "bnl_borrowing_name",
          ],
        ];
      }

      $columns = "
            SELECT
            '!!!type!!!' as \"type\",
            bnl.borrow_date \"borrow_date\",
            !!!column_var!!!.id \"branch_id\",
            bnl_totals.cid,
            sum(bnl.quantity) \"quantity\",
            bnl_totals.total,round((sum(bnl.quantity) / bnl_totals.total) * 100,3) \"percentage\"
           ";

      $fromClauseStart = "
            FROM
            mobius_bnl_bnl bnl,
            (
                SELECT
                borrow_date,
                branch_system.cid,
                sum(quantity) \"total\"
                FROM
                mobius_bnl_bnl_final_branch_map bnl,
                mobius_bnl_branch_system branch_system
                WHERE
                branch_system.fid=bnl.!!!total_lib_var!!! AND
                bnl.borrow_date between str_to_date( concat(?,'-01') ,'%Y-%m-%d') and str_to_date( concat(?,'-01') ,'%Y-%m-%d') AND
                bnl.quantity > 0
                GROUP BY 1,2
                ORDER BY 1
            ) as bnl_totals,
            mobius_bnl_branch bnl_borrowing_branch,
            mobius_bnl_branch bnl_owning_branch,
            mobius_bnl_branch_name_final bnl_borrowing_name,
            mobius_bnl_branch_name_final bnl_owning_name,
            mobius_bnl_branch_system bnl_branch_system
            WHERE
            !!!where_var!!!.id=bnl_branch_system.fid AND
            bnl_branch_system.cid=bnl_totals.cid AND
            bnl_totals.borrow_date = bnl.borrow_date and
            bnl_borrowing_name.id = bnl_borrowing_branch.final_branch and
            bnl_owning_name.id = bnl_owning_branch.final_branch and
            bnl.borrowing_branch = bnl_borrowing_branch.id and
            bnl.owning_branch = bnl_owning_branch.id and
            bnl_borrowing_name.id != bnl_owning_name.id and
            bnl.borrow_date between str_to_date( concat(?,'-01') ,'%Y-%m-%d') and str_to_date( concat(?,'-01') ,'%Y-%m-%d')
            and bnl.quantity > 0
            ";

      $fromClause = $this->mobius_bnl_get_bnl_base_branches_from_clause($fromClauseStart, $vals, $branchSelections, 0);
      $groupClause = " group by 1,2,3,4,6";

      $query = $columns . $fromClause . $groupClause;
      foreach ($replacements['lent'] as $key => $value) {
        $query = preg_replace("/" . $key . "/", $value, $query);
      }

      $query .= "
        UNION ALL
        $columns";

      $vals[] = $startDate;
      $vals[] = $endDate;
      $vals[] = $startDate;
      $vals[] = $endDate;
      $fromClause = $this->mobius_bnl_get_bnl_base_branches_from_clause($fromClauseStart, $vals, $branchSelections, 1);
      $query .= $fromClause . $groupClause;
      foreach ($replacements['borrow'] as $key => $value) {
        $query = preg_replace("/" . $key . "/", $value, $query);
      }

      $query .= "
            limit $chunk
            offset $offset";

      //      foreach ($vals as $v) {
      //        print_r($v);
      //        $query = preg_replace('/\?/', "'$v'", $query, 1);
      //      }

      //            echo preg_replace('/\n/', '<br>', $query);
      //            print_r();
      //            exit;

      //      $result = db_query($query, $vals);


      $database = \Drupal::database();
      $result = $database->query($query, $vals);


      $gotmore = 0;
      while ($libraryRow = $result->fetchAssoc()) {
        $gotmore++;
        if (!$data_array[$libraryRow["type"]]) {
          $data_array[$libraryRow["type"]] = [];
        }
        if (!$data_array[$libraryRow["type"]][$libraryRow["borrow_date"]]) {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]] = [];
        }
        if (!$data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$libraryRow["branch_id"]]) {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$libraryRow["branch_id"]] = [];
        }
        if (!$data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$libraryRow["branch_id"]][$libraryRow["cid"]]) {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$libraryRow["branch_id"]][$libraryRow["cid"]] = [];
        }
        if (!$data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$libraryRow["branch_id"]][$libraryRow["cid"]]) {
          $data_array[$libraryRow["type"]][$libraryRow["borrow_date"]][$libraryRow["branch_id"]][$libraryRow["cid"]] = [
            $libraryRow["quantity"],
            $libraryRow["total"],
            $libraryRow["percentage"],
          ];
        }
      }

      //      $gotmore = $result->rowCount();
      $totalRows += $gotmore;
# if we didn't receive a full chunk of data, then we don't need to go back to the database for more.
      if ($gotmore < $chunk)
      {
        $gotmore = 0;
      }
      unset($rows);
      unset($result);
      $offset += $chunk;
    }

    $data_array["query"] = $query;
    $data_array["result_rows"] = $totalRows;
  }

  public function mobius_bnl_get_bnl_base_branches_from_clause($fromClause, &$vals, $branchSelections, $reverse) {
    if ($reverse) {
      $temp = $branchSelections['bnl_owning_name.id'];
      $branchSelections['bnl_owning_name.id'] = $branchSelections['bnl_borrowing_name.id'];
      $branchSelections['bnl_borrowing_name.id'] = $temp;

      $temp = $branchSelections['owning_cluster_ids.cid'];
      $branchSelections['owning_cluster_ids.cid'] = $branchSelections['borrowing_cluster_ids.cid'];
      $branchSelections['borrowing_cluster_ids.cid'] = $temp;
    }
    foreach ($branchSelections as $key => $value) {

      if (strlen($value) > 0) {
        $clause = "\nAND (";
        $something = 0;
        $values = explode(',', $value);
        $collection = "";
        foreach ($values as $id) {
          if (is_numeric($id)) // only digits allowed here
          {
            $something = 1;
            if (preg_match("/cluster/", $key)) // Clusters are handled differently
            {
              $collection .= "$id,";
            }
            else {
              $clause .= "\n$key = ? \nOR";
              $vals[] = $id;
            }
          }
        }
        if (preg_match("/cluster/", $key)) // Clusters are handled differently
        {
          $collection = substr($collection, 0, -1); // chop off the last ,
          $type = (preg_match("/owning/", $key) ? "owning" : "borrowing");
          $type = "bnl_" . $type . "_name.id";
          $clause .= "$type IN (SELECT fid FROM mobius_bnl_branch_connection_map WHERE cid IN ( $collection ) ) \n)";
        }
        else {
          $clause = substr($clause, 0, -2); // chop off the last "OR"
          $clause .= ")\n";
        }
        $fromClause = ($something ? $fromClause . $clause : $fromClause);

      }
    }
    return $fromClause;
  }

  public function mobius_bnl_figure_specified_branches($branchSelections) {
    $borrowing = 0;
    foreach ($branchSelections as $key => $value) {
      if (strlen($value) > 0) {

        if (preg_match("/borrowing/", $key)) {
          $borrowing = 1;
        }
      }
    }
    $ret = 0;
    // 0 = only owning specified
    // 1 = only borrowing specified
    // 2 = both owning and borrowing specified
    $ret = $borrowing ? 1 : 0;
    $ret = ($borrowing && $owning) ? 2 : $ret;
    return $ret;
  }

}
