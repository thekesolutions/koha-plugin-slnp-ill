[% USE Asset %]
[% SET footerjs = 1 %]



[% IF whole.error %]
    <p>Unknown error</p>
[% END %]

[% IF ( whole.stage == "confirmcommit" ) %]
    <h2>Mark as not available ([% request.orderid %])</h2>
    <p>By confirming this action the status of the ILL request is updated to 'Completed'.</p>
    <p>This means that the owning library won't deliver the requested item,<br>
    that the ILL request won't be fulfilled, <br> 
    and that the temporarily added bibliographic record and item record will be deleted.</p>

    [% IF ! ( request.status == 'REQ' || request.status == 'CNCLDFU' ) %]
        <p>The current status ([% request.status %]) of the ILL request doesn't allow to mark this request as not available.</p>
        <p>This action is only possible until the item has been received.</p>

        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>

    [% ELSE %]

        <form id="SLNP_notdelivered" name="SLNP_notdelivered" method="POST" action=[% here %]>

            <label for="illnotdeliveredletterprint">Notification of the requesting patron:</label>
            [% IF whole.value.other.illnotdeliveredlettercode %]
                <input type="checkbox" name="illnotdeliveredletterprint" id="illnotdeliveredletterprint" value="1" [% IF whole.value.other.illnotdeliveredletterprint %]checked="checked"[% END %] />
            [% ELSE %]
                <input type="checkbox" name="illnotdeliveredletterprint" id="illnotdeliveredletterprint" value="1" disabled />
            [% END %]
            <br>

            <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" type="hidden" />
            <input name="backend" id="backend" value="SLNP" type="hidden" />
            <input name="method" id="method" value="kennzeichneNegativ" type="hidden" />
            <input name="stage" id="stage" value="[% whole.stage %]" type="hidden" />
            <input name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber %]" type="hidden" />
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
        [% IF ! ( request.status == 'REQ' || request.status == 'CNCLDFU' ) %]
            submitbutton.disabled = true;
        [% END %]
    })

</script>
