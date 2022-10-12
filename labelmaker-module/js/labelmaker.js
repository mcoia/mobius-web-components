class LabelMaker {

  constructor() {
    this.checkCookieStatus();
    this.initChosen();
    this.initSubmitButton();
    this.filterOptionTags();
    this.hideDropDown();
    this.hideErrorMessage();
  }

  initSubmitButton() {

    // .label-maker-btn
    jQuery('.label-maker-btn').on('click', function () {

      let message = '';

      // 2nd Dropdown
      if (jQuery('#jsonTo').val() == '') {
        message = 'Destination Not Selected';
      }

      // 1st Dropdown
      if (jQuery('#jsonFrom').val() == '') {
        message = 'Ship From Not Selected';
      }

      if (message != '') {
        jQuery('#error-message').text(message);
      }
      else {
        jQuery('#labelForm').submit();
      }

    });

  }

  initChosen() {
    jQuery(".chosen-select").chosen({search_contains: true});
  }

  // jQuery did this...
  filterOptionTags() {

    jQuery('#jsonFrom').on('change', function (evt, params) {

      /*
          What we need to do...

          grab all the <option> tag elements from our jsonTo, iterate over them and compare our
          permitted to against the intersort data.

          for example...
          <option data-permitted-to='MALA,MOB,TAE,CLC,IOWA' data-intersort='MOB' value='{"id":"148","is_stop":"1","statCode":"MO-NO-106","locCode":"ATSU","oclcSymbol":"KOS","locName":"A.T. Still Memorial Lib. ","address1":"","address2":"800 W Jefferson St","city":"Kirksville","state":"MO","zip":"63501","sortCode":"NO","interSort":"MOB","permittedTo":"MALA,MOB,TAE,CLC,IOWA"}' class='MO'>A.T. Still Memorial Lib.  (MO: ATSU OCLC: KOS)</option>

         permitted to => MALA,MOB,TAE,CLC,IOWA
         intersort => MOB


        If the intersort value is NOT in our permitted to array
        then we'll disable the option tag eliminating it from the view.

      */

      // convert our params to json
      let jsonFrom = JSON.parse(params['selected']);

      // convert our json.permittedTo => array
      let permittedToArray = jsonFrom.permittedTo.split(',');

      // grab all option tags from our send to dropdown and check intersort
      // against permitted values
      jQuery('#jsonTo option').each(function (index) {

        // grab our current option element -
        // let optionElement = jQuery('#jsonFrom option')[index];
        let optionElement = jQuery(this)[0];

        let dataInterSortValue = jQuery(this).attr('data-intersort');

        // check if our instersort is in our permittedTo
        // disable the option if it's not
        if (jQuery.inArray(dataInterSortValue, permittedToArray) == -1) {
          optionElement.disabled = true;
        }
        else {
          optionElement.disabled = false;
        }

      });

      jQuery("#jsonTo").trigger("chosen:updated");

    });

  }

  // checks if we should hide the 2nd(#jsonTo) dropdown
  hideDropDown() {

    // check if the 1st dropdown(#jsonFrom) has a selection, if not we'll
    // hide the  2nd dropdown(#jsonTo)
    if (!this.isDropDownSelected()) {
      jQuery('#jsonTo_chosen').hide();

      // Add an event listener and check for changes on the first dropdown
      // and show the 2nd dropdown if we detect something...
      jQuery('#jsonFrom').on('change', function () {
        jQuery('#jsonTo_chosen').show();
      });

    }

  }

  isDropDownSelected() {

    /*
        We check for a .val() of ''
        instead of something like is(':selected')
        because the dropdown is technically selected, just with a default
        filler text 'Select a FROM address' || Click and/or start typing....
    */

    return jQuery('#jsonFrom').val() != '';

  }

  hideErrorMessage() {

    jQuery('#jsonFrom').on('change', function () {
      jQuery('#error-message').text('');
    });

    jQuery('#jsonTo').on('change', function () {
      jQuery('#error-message').text('');
    });

  }

  getCookie(cname) {
    let name = cname + "=";
    let decodedCookie = decodeURIComponent(document.cookie);
    let ca = decodedCookie.split(';');
    for (let i = 0; i < ca.length; i++) {
      let c = ca[i];
      while (c.charAt(0) == ' ') {
        c = c.substring(1);
      }
      if (c.indexOf(name) == 0) {
        return c.substring(name.length, c.length);
      }
    }
    return "";
  }

  checkCookieStatus() {

    let institutionID = this.getCookie('label-from');

    jQuery('#jsonFrom option').each(function (i) {

      // this is like a continue; but for jQuery.
      // we have to skip the first <option> as it's blank
      if (i == 0) {
        return true;
      }

      let dropdownID = JSON.parse(jQuery(this).val()).id;

      if (institutionID == dropdownID) {

        jQuery(this).attr('selected', 'selected');
        // jQuery("#jsonFrom").trigger("chosen:updated");

      }

    });

  }

}

jQuery(document).ready(function () {
  new LabelMaker();
});
