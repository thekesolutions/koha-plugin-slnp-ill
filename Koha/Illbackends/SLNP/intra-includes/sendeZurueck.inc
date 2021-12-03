[% USE Asset %]


[% IF whole.error %]
    <p>Unknown error</p>
[% END %]

[% IF whole.stage == "confirmcommit" %]
    <h2>Return to library ([% request.orderid %])</h2>
    <p>By confirming this action the status of the ILL request will be updated to 'Completed'.</p>
    <p>This means that the patron has returned the item or that the ILL request was cancelled before checkout.</p>

    [% IF ( request.status == 'RECVD' ) %]
        <p>
            <strong>
                The ILL item hasn't been checked out to the patron yet.<br>
                Please only confirm the action, if you want to cancel the ILL request.
            </strong>
        </p>
    [% ELSE %]
        [% IF ! ( request.status == 'CHKDIN' || request.status == 'CNCLDFU' ) %]
            <p>
                <strong>
                    The current status ([% request.status %]) of the ILL request doesn't allow for this action.<br>
                    Before returning the item to the lending library, the ILL request must be cancelled or checked in.
                </strong>
            </p>
        [% END %]
    [% END %]

    <form id="SLNP_shipback" name="SLNP_shipback" method="POST" action=[% here %]>

        <label for="illshipbackslipprint">Create return letter:</label>
        [% IF whole.value.other.illshipbacklettercode %]
            <input type="checkbox" name="illshipbackslipprint" id="illshipbackslipprint" value="1" [% IF whole.value.other.illshipbackslipprint %]checked="checked"[% END %] />
        [% ELSE %]
            <input type="checkbox" name="illshipbackslipprint" id="illshipbackslipprint" value="1" disabled />
        [% END %]
        <br>

        <input type="hidden" name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" />
        <input type="hidden" name="backend" id="backend" value="[% request.backend %]" />
        <input type="hidden" name="method" id="method" value="[% whole.method %]" />
        <input type="hidden" name="stage" id="stage" value="[% whole.stage %]" />
        <input type="hidden" name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber %]" />
        <br>

        <input id="submitbutton" name="submitbutton" type="submit" value="Confirm" onclick="stage.value='storeandprint';" />

        <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>

    </form>

[% ELSIF whole.stage == "storeandprint" %]

  <p>Return to ILL request</p>

  <form id="SLNP_shipback" name="SLNP_shipback" method="POST" action=[% here %]>
    <input style="display:none" type="checkbox" name="illshipbackslipprint" id="illshipbackslipprint" value="1" [% IF ( whole.value.other.illshipbackslipprint ) %]checked="checked"[% END %] />
    <input style="display:none" id="submitbutton" name="submitbutton" type="submit" value="Confirm" onclick="stage.value='storeandprint';" />
    <a style="display:none" class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>
  </form>

[% ELSE %]
    <p>Unknown stage: '[% whole.stage %]'</p>
[% END %]



<script type= "text/javascript">

    $(document).ready(function() {
        [% IF ! ( request.status == 'RECVD' || request.status == 'CHKDIN' || request.status == 'CNCLDFU' ) %]
            submitbutton.disabled = true;
        [% END %]

        [% IF whole.stage == 'storeandprint' %]
            var slipchecked = $("#illshipbackslipprint").prop('checked');
            if ( slipchecked ) {
                var ret = printIllShipbackSlip();
            } else {
                document.getElementById("cancelbutton").click();
            }
        [% END %]
    });    // $(document).ready(function() END

    function printIllShipbackSlip () {
        var borrowernumbers = [];
        borrowernumbers.push("[% whole.value.other.sendingIllLibraryBorrowernumber %]");
        borrowernumbers.push("[% whole.value.request.borrowernumber %]");

        var data = {
            use_letter: "[% whole.value.other.illshipbacklettercode %]",
            use_email: '',
            slipcount: '1',
            illrequestid: "[% whole.illrequest_id %]",
            biblionumber: "[% request.biblio_id %]",
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
                alert( _("A server error occured while processing the print request.") );

                document.getElementById("cancelbutton").click();
            }
        });
    }

</script>
