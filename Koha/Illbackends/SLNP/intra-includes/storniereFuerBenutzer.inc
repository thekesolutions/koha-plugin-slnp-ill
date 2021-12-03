[% USE Asset %]

[% IF whole.error %]
    <p>Unknown error</p>
[% END %]

[% IF ( whole.stage == "confirmcommit" ) %]
    <h2>Cancel ILL request ([% request.orderid %])</h2>
    <p>By confirming this action the status of the ILL request will be updated to 'Completed' or 'Cancelled'.</p>
    <p>This means, that the lending library has confirmed either that the shipment of the requested item can be cancelled<br>
    or that the item has already been sent.</p>
    <p>For the first case the ILL request status will be updated to 'Completed' and the temporarily added bibliographic record and item record will be deleted.<br>
    For the second case the status of the ILL request will be updated to 'Cancelled' and the item can be returned to the lending library immediately after arrival.</p>

    [% IF ( request.status != 'REQ' ) %]
        <hr>
        <p>The current status ([% request.status %]) of the ILL request doesn't allow for cancellation.</p>
        <p>This action is not possible before the delivery was processed.</p>
        <p>If the user doesn't want to check out the item after it was received, the item can be returned to the lending library immediately.</p>

        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>

    [% ELSE %]

        <form id="SLNP_cancelled" name="SLNP_cancelled" method="POST" action=[% here %]>

            <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" type="hidden" />
            <input name="backend" id="backend" value="SLNP" type="hidden" />
            <input name="method" id="method" value="storniereFuerBenutzer" type="hidden" />
            <input name="stage" id="stage" value="[% whole.stage %]" type="hidden" />
            <input name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber %]" type="hidden" />

            <div>
                <input type="radio" id="alreadyShippedNo" name="alreadyShipped" value="alreadyShippedNo"> 
                <label for="alreadyShippedNo">The requested item will not be sent from the owning library.</label>
            </div>
            <div>
                <input type="radio" id="alreadyShippedYes" name="alreadyShipped" value="alreadyShippedYes" checked>
                <label for="alreadyShippedYes">The requested item has already been sent to the requesting library.</label>
            </div>
            <br>

            [% IF ( whole.stage == "confirmcommit" ) %]
                <input id="submitbutton" name="submitbutton" type="submit" value="Confirm" onclick="stage.value='commit'" />
            [% ELSE %]
                <input id="submitbutton" name="submitbutton" type="submit" value="Confirm" onclick="stage.value='commit'" disabled />
            [% END %]

            <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>

        </form>
    [% END %]

[% ELSE %]
    <p>Unknown stage: [% whole.stage %]</p>
[% END %]



<script type= "text/javascript">

    $(document).ready(function() {
        [% IF ! ( request.status == 'REQ' ) %]
            submitbutton.disabled = true;
        [% END %]
    })

</script>
