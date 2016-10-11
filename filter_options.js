
function isPermitted(from_array_id) {
  // create an array of intersort values that this library is allowed to send to
  console.log(from_array_id-1);
  var permittedToVals = $jq("#from_id option[value="+(from_array_id)+"]")[0].attributes['data-permitted-to'].value.split(',')
  console.log($jq("#from_id option[value="+(from_array_id)+"]")[0]);
  console.log(permittedToVals);

  // Loop through option elements and check that the intersort of each
  // exists in the array of permittedToVals we just created
  // If it doesn't exist, then disable the option.

  var to_options = $jq("#to_id option")
  for (x = 0; x < to_options.length; x++) {
    var myIntersort = to_options[x].attributes['data-intersort'].value;
    if ($jq.inArray(myIntersort, permittedToVals) == -1) {
      to_options[x].disabled = true;
    } else {
      to_options[x].disabled = false;
    }
  }
  // update the fancy Chosen list to match the source list, which we've just
  // modified.
  $jq("#to_id").trigger("chosen:updated");
}

$jq(document).ready(function() {
  $jq('#from_id').on('chosen:ready', function(evt,params) {
    isPermitted(params['selected']);
  });
  $jq('#from_id').on('change', function(evt, params) {
   isPermitted(params['selected']);
  });
});
