[% USE raw %]
[% USE Asset %]
[% SET footerjs = 1 %]

[% USE Koha %]
[% USE AuthorisedValues %]
[% USE ItemTypes %]
[% USE KohaDates %]
[% USE Price %]

[% IF whole.error %]
  [% IF whole.status == 'missing_sendingIllLibraryInfo' %]
    <p><em>Note:</em> The mandatory field 'Lending library' is empty.</p>
  [% ELSE %]
    <p>Unknown error</p>
  [% END %]
[% END %]

[% IF whole.stage == "update" %]
  <h2>Edit delivery ([% whole.value.request.orderid %])</h2>
[% ELSIF whole.stage == 'init' %]
  <h2>Process delivery ([% whole.value.request.orderid %])</h2>

  <form id="SLNP_delivery" name="SLNP_delivery" method="POST" action=[% here %]>

    <fieldset class="rows">
      <legend>Delivery</legend>
      <ol id="general-slnp_delivery-fields">

        <li>
          <label class="required" for="type">Request type:</label>
            <select name="type" id="type" required="required">
            [% IF whole.value.medium == "loan" %]
              <option value="loan" selected="selected">Loan</option>
            [% ELSE %]
              <option value="loan">Loan</option>
            [% END %]
            [% IF whole.value.medium == "copy" %]
              <option value="copy" selected="selected">Copy</option>
            [% ELSE %]
              <option value="copy">Copy</option>
            [% END %]
          </select>
        </li>

        <li>
          <label class="required" for="delivery_date">Received on:</label>
          <input type="text" class="datepicker" name="delivery_date" id="delivery_date" size="10" maxlength="10" value="[% whole.value.other.deliverydate | $KohaDates %]" required="required" />
          <span class="hint">[% INCLUDE 'date-format.inc' %]</span>
        </li>

        <!--li id="sendingIllLibrary">
          <label class="required" for="sendingIllLibraryInfo">Lending library:</label>

          [% IF whole.value.other.sendingIllLibraryBorrowernumber %]
            [% SET sendingIllLibraryInfo = 'ISIL: ' _ whole.value.other.sendingIllLibraryIsil _ ' / ' _ whole.value.other.sendingIllLibrarySurname _ ' / City: ' _ whole.value.other.sendingIllLibraryCity %]
            <span></span><a target="blank" href="/cgi-bin/koha/members/moremember.pl?borrowernumber=[% whole.value.other.sendingIllLibraryBorrowernumber %]"><input disabled type="text" name="sendingIllLibraryInfo" id="sendingIllLibraryInfo" size="80" value="[% sendingIllLibraryInfo | html %]" required="required" /></a>
          [% ELSE %]
            <span></span><a target="blank" href="/cgi-bin/koha/members/moremember.pl"><input required="required" disabled type="text" name="sendingIllLibraryInfo" id="sendingIllLibraryInfo" size="80" value="" /></a>
          [% END %]
          <input type="hidden" id="sendingIllLibraryBorrowernumber" name="sendingIllLibraryBorrowernumber" value="[% whole.value.other.sendingIllLibraryBorrowernumber %]" />
          <input type="hidden" id="sendingIllLibraryIsil" name="sendingIllLibraryIsil" value="[% whole.value.other.sendingIllLibraryIsil %]" />
          <input type="hidden" id="sendingIllLibrarySurname" name="sendingIllLibrarySurname" value="[% whole.value.other.sendingIllLibrarySurname %]" />
          <input type="hidden" id="sendingIllLibraryCity" name="sendingIllLibraryCity" value="[% whole.value.other.sendingIllLibraryCity %]" />
          [% SET illcategs = '' %]
          [% FOREACH category IN whole.value.other.kohaIllPatronCategories %]
            [% SET illcategs = illcategs _ category.categorycode _ ',' %]
          [% END %]
           <input id="illlibrarysearch" type="button" [% IF whole.value.other.sendingIllLibraryBorrowernumber %]value="Update"[% ELSE %]value="Search"[% END %] onclick="DoPopIllLibrarySearch('illLibrary_search.pl?illcategories=[% illcategs %]');" />
        </li-->

        <li>
          <label class="required" for="lending_library">Lending library:</label>
            <select name="lending_library" id="lending_library" required="required" class="select2">
            [% FOREACH library IN whole.value.lending_libraries %]
                <option value="[% library.borrowernumber | html %]">[% library.surname _ library.othernames | html %]</option>
            [% END %]
          </select>
        </li>

        <li>
          <label for="request_charges">Cost:</label>
          <input type="text" size="10" name="request_charges" id="request_charges" value="[% whole.value.request_charges | $Price %]"  oninput="floatInput(document.SLNP_delivery.billedillrequestcosts,2)"  onchange="moneyFormat(document.SLNP_delivery.billedillrequestcosts)" />
        </li>

        <li>
          <label for="circulation_notes">Circulation restrictions:</label>
          <input type="textarea" rows="4" cols="100" name="circulation_notes" id="circulation_notes" value="[% whole.value.other.circulation_notes | html %]" />
        </li>

      </ol>
    </fieldset>

    <fieldset class="rows">
    <legend>Item</legend>
      <ol>
        <li>
          <label class="required" for="item_type">Item type:</label>
            <select name="item_type" id="item_type" required="required">
            [% FOREACH it IN whole.value.item_types %]
              [% IF it.selected %]
                <option value="[% it.value | html %]" selected="selected">[% ItemTypes.GetDescription(it.value) | html %]</option>
              [% ELSE %]
                <option value="[% it.value | html %]">[% ItemTypes.GetDescription(it.value) | html %]</option>
              [% END %]
            [% END %]
          </select>
        </li>

        <li>
          <label for="callnumber">Callnumber:</label>
          <input type="text" size="50" name="callnumber" id="callnumber" value="[% whole.value.other.callnumber | html %]" />
        </li>

        <!--li>
          <label for="noncirccollection">Not for loan:</label>
          [% IF whole.value.other.noncirccollection %]
            <input type="checkbox" name="noncirccollection" id="noncirccollection" value="1" checked="checked" />
          [% ELSE %]
            <input type="checkbox" name="noncirccollection" id="noncirccollection" value="1" />
          [% END %]
        </li-->

        <li>
          <label for="number_of_parts">Number of parts:</label>
          <input type="number" name="number_of_parts" id="number_of_parts" min="0" size="10" maxlength="10" value="[% whole.value.number_of_parts %]" />
        </li>

        <li>
          <label for="callnumber">Callnumber:</label>
          <input type="text" size="50" name="callnumber" id="callnumber" value="[% whole.value.other.callnumber | html %]" />
        </li>

        <li>
          <label for="usage_restrictions">Usage restrictions:</label>
          [% PROCESS 'av-build-dropbox.inc' name="usage_restrictions", category="RESTRICTED", empty=1 %]
        </li>

        <li>
          <label for="damaged">Damaged:</label>
          [% PROCESS 'av-build-dropbox.inc' name="damaged", category="DAMAGED", empty=1 %]
        </li>

        <li>
          <label class="required" for="duedate">Due date:</label>
          <input type="text" class="datepicker" name="duedate" id="duedate" size="10" maxlength="10" value="[% whole.value.other.duedate | $KohaDates %]" required="required" />
         <span class="hint">[% INCLUDE 'date-format.inc' %]</span>
        </li>

      </ol>
    </fieldset>

    <fieldset class="action">
      <input type="hidden" name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" />
      <input type="hidden" name="backend" id="backend" value="[% request.backend %]" />
      <input type="hidden" name="method" id="method" value="[% whole.method %]" />
      <input type="hidden" name="stage" id="stage" value="[% whole.stage %]" />
      <input type="hidden" name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber %]" />

      [% IF ( whole.stage == "deliveryInsert" ) %]
        <input type="submit" id="submitbutton" name="submitbutton" value="Save" onclick="stage.value='InsertAndPrint';" />
      [% ELSE %]    <!-- whole.stage == "deliveryUpdate" -->
        <input type="submit" id="submitbutton" name="submitbutton" value="Save changes" onclick="stage.value='UpdateAndMaybePrint';" />
        <input type="submit" id="printButton"  name="printButton"  value="Print" disabled onclick="stage.value='PrintOnly';" />
      [% END %]

      <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>
    </fieldset>
  </form>

[% ELSE %]
  <p>Unknown stage: '[% whole.stage %]'</p>
[% END %]

<script>
    document.addEventListener('DOMContentLoaded', function() {
        $('#lending_library').select2();
    });
</script>

<!--script type= "text/javascript">

    $(document).ready(function() {

        $('#lending_library').select2();

        [% IF whole.stage == "InsertAndPrint" || whole.stage == "UpdateAndMaybePrint" || whole.stage == "PrintOnly" %]
            var slipchecked = $("#illdeliveryslipprint").prop('checked');
            if ( slipchecked ) {
                var ret = printIllProcessingSlip();
            } else {
                document.getElementById("cancelbutton").click();
            }
        [% ELSIF whole.stage == "deliveryUpdate" %]
            actualizePrintButton(document.SLNP_delivery.printButton);
        [% END %]

        $("#printButton").on('click', function(e){
            e.preventDefault();
            var ret = false;
            var deliverylettercode = $("#illdeliverylettercode").val();
            var slipchecked = $("#illdeliveryslipprint").prop('checked');
            if ( !(deliverylettercode || slipchecked) ) {
                alert( _("You have not selected any letter or slip!") );
                return false;
            }
            if ( slipchecked > 0 ) {
                ret = printIllProcessingSlip();
            }
            if ( deliverylettercode ) {
                $('#SLNP_delivery').submit();
            }
            return ret;
        });

    });    // $(document).ready(function() END

    function actualizePrintButton (buttonObj) {
        if ( $("#illdeliverylettercode").val() || $("#illdeliveryslipprint").prop('checked') )
            buttonObj.disabled = false;
        else
            buttonObj.disabled = true;
    }

    function printIllProcessingSlip () {
        var slipcount = 0;
        if ( $("#illdeliveryslipprint").prop('checked') ) {
          slipcount = 2;
        }
        var borrowernumbers = [];
        borrowernumbers.push("[% whole.value.other.sendingIllLibraryBorrowernumber %]");
        borrowernumbers.push("[% whole.value.request.borrowernumber %]");
        var data = {
            use_letter: "[% whole.value.other.illdeliveryslipcode %]",
            use_email: '',
            slipcount: slipcount,
            illrequestid: "[% whole.illrequest_id %]",
            biblionumber: "[% whole.value.request.biblio_id %]",
            itemnumber: "[% whole.value.other.itemnumber %]",
            duedate: "[% whole.value.other.duedate %]",
            borrowernumbers: borrowernumbers
        };

        $.ajax({
            data: data,
            type: 'POST',
            url: '/cgi-bin/koha/svc/members/genIllDeliverySlip',
            success: function(data) {

                var processingslipwin = window.open("/cgi-bin/koha/tools/download-files.pl?filename=" + data.printedfile + "&op=download");

                processingslipwin.onload = function()
                {
                    document.getElementById("cancelbutton").click();
                    processingslipwin.print();
                    processingslipwin.close();
                };

            },
            error: function() {
                alert( _("A server error occured processing the processing slip print request.") );

                document.getElementById("cancelbutton").click();
            }
        });
    }


    function floatInput(floatAsText,decimalplaces) {
        // Not accepting more than 1 decimal separator ("." or ",") and 2 ciphers after the integer part of the input in money amount field.
        var len = floatAsText.value.length;
        var decSepPos = floatAsText.value.indexOf(".");
        var decSepPos2 = floatAsText.value.indexOf(",");
        if ( decSepPos2 >= 0 && (decSepPos2 < decSepPos || decSepPos < 0) ) {  
            decSepPos = decSepPos2;
        }
        if ( decSepPos >= 0 && len > decSepPos + 1 + decimalplaces ) {
            floatAsText.value = floatAsText.value.substr(0, decSepPos + 1 + decimalplaces);
        }
    }

    function moneyNormalize(textObj) {
        var amountNew = parseFloat(textObj.value.replace(",","."));
        if ( isNaN(amountNew) ) {
            amountNew = 0.0;
        }
        textObj.value = parseFloat(amountNew);
    }

    function moneyFormat(textObj) {
        var newValue = textObj.value.replace(",",".");
        var decAmount = "";
        var dolAmount = "";
        var decFlag   = false;
        var aChar     = "";

        for(i=0; i < newValue.length; i++) {
            aChar = newValue.substring(i, i+1);
            if (aChar >= "0" && aChar <= "9") {
                if(decFlag) {
                    decAmount = "" + decAmount + aChar;
                }
                else {
                    dolAmount = "" + dolAmount + aChar;
                }
            }
            if (aChar == ".") {
                if (decFlag) {
                    break;
                }
                decFlag = true;
            }
        }

        if (dolAmount == "") {
            dolAmount = "0";
        }
        // Strip leading 0s
        if (dolAmount.length > 1) {
            while(dolAmount.length > 1 && dolAmount.substring(0,1) == "0") {
                dolAmount = dolAmount.substring(1,dolAmount.length);
            }
        }
        if (decAmount.length > 2) {
            decAmount = decAmount.substring(0,2);
        }
        // Pad right side
        if (decAmount.length == 1) {
            decAmount = decAmount + "0";
        }
        if (decAmount.length == 0) {
        decAmount = decAmount + "00";
        }

        textObj.value = parseFloat(parseFloat(dolAmount + "." + decAmount).toFixed(2)).format_price();
    }


    function DoPopIllLibrarySearch(link) {
        var newWin = window.open(link,'popup','width=800,height=500,resizable=no,toolbar=false,scrollbars=yes,top');
    }


    function select_user(borrowernumber, sendingLib) {
        var form = $('#SLNP_delivery').get(0);

        if ( !sendingLib.borr_attr_attribute_SIGEL ) {
            sendingLib.borr_attr_attribute_SIGEL = '';
        }
        var sendingIllLibraryInfo = 'ISIL: ' + sendingLib.borr_attr_attribute_SIGEL + ' / ' + sendingLib.surname + ' / City: ' + sendingLib.city;
        $('#sendingIllLibrary')
            .show()
            .find('a')
            .attr("href","/cgi-bin/koha/members/moremember.pl?borrowernumber=" + sendingLib.borrowernumber);

        form.sendingIllLibraryBorrowernumber.value = sendingLib.borrowernumber;
        form.sendingIllLibraryIsil.value = sendingLib.borr_attr_attribute_SIGEL;
        form.sendingIllLibrarySurname.value = sendingLib.surname;
        form.sendingIllLibraryCity.value = sendingLib.city;
        form.sendingIllLibraryInfo.value = sendingIllLibraryInfo;

        form.illlibrarysearch.value = 'Update';

        return 0;
    }

</script-->

[%# INCLUDE 'intranet-bottom.inc' %]
