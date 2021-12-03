[% USE Asset %]


[% IF whole.error %]
    <p>Unknown error</p>
[% END %]

[% IF ( whole.stage == "confirmcommit" ) %]
    <h2>Loss notification for ILL request ([% request.orderid %])</h2>
    <p>If you confirm this action, the ILL request status will be updated to 'Completed'.</p>
    <p>This means that either the patron has lost the item,<br>
       or that the item went missing before checkout,<br>
       or after checkin in the library.
    </p>

    [% IF ! ( request.status == 'LOSTBCO' || request.status == 'LOSTACO' ) %]
        <p><strong>
            The current status ([% request.status %]) of the ILL request doesn't allow for creating a loss notification.<br>
            You have to set the lost status in the ILL item first.</strong></p>
    [% END %]

    <form id="SLNP_itemlost" name="SLNP_itemlost" method="POST" action=[% here %]>

        <label for="illitemlostlibraryletterprint">Create a loss notification for the lending library:</label>
        [% IF whole.value.other.illitemlostlibrarylettercode %]
            <input type="checkbox" name="illitemlostlibraryletterprint" id="illitemlostlibraryletterprint" value="1" [% IF whole.value.other.illitemlostlibraryletterprint %]checked="checked"[% END %] />
        [% ELSE %]
            <input type="checkbox" name="illitemlostlibraryletterprint" id="illitemlostlibraryletterprint" value="1" disabled />
        [% END %]
        <br>

        [% IF ( request.status == 'LOSTBCO' ) %]
            <label for="illitemlostborrowerletterprint">Create a loss notification for the patron:</label>
            [% IF whole.value.other.illitemlostborrowerlettercode %]
                <input type="checkbox" name="illitemlostborrowerletterprint" id="illitemlostborrowerletterprint" value="1" [% IF whole.value.other.illitemlostborrowerletterprint %]checked="checked"[% END %] />
            [% ELSE %]
                <input type="checkbox" name="illitemlostborrowerletterprint" id="illitemlostborrowerletterprint" value="1" disabled />
            [% END %]
            <br>
        [% END %]

        <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" type="hidden" />
        <input name="backend" id="backend" value="SLNP" type="hidden" />
        <input name="method" id="method" value="meldeVerlust" type="hidden" />
        <input name="stage" id="stage" value="[% whole.stage %]" type="hidden" />
        <input name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber %]" type="hidden" />
        <input name="sendingIllLibraryBorrowernumber" id="sendingIllLibraryBorrowernumber" value="[% whole.value.other.sendingIllLibraryBorrowernumber %]" type="hidden" />
        <input name="illitemlostlibrarylettercode" id="illitemlostlibrarylettercode" value="[% whole.value.other.illitemlostlibrarylettercode %]" type="hidden" />
        <input name="illitemlostborrowerlettercode" id="illitemlostborrowerlettercode" value="[% whole.value.other.illitemlostborrowerlettercode %]" type="hidden" />
        <br>

        [% IF ( whole.stage == "confirmcommit" ) %]
            <input id="submitbutton" name="submitbutton" type="submit" value="OK" onclick="stage.value='confirmcommit'" />
        [% ELSE %]
            <input id="submitbutton" name="submitbutton" type="submit" value="OK" onclick="stage.value='commit'" disabled />
        [% END %]

        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>

    </form>

[% ELSE %]
    <p>Unknown stage: [% whole.stage %]</p>
[% END %]



<script type= "text/javascript">

    $(document).ready(function() {
        [% IF ! ( request.status == 'LOSTBCO' || request.status == 'LOSTACO' ) %]
            submitbutton.disabled = true;
        [% END %]

    });

</script>
