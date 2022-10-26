[% USE Asset %]
[% SET footerjs = 1 %]



[% IF whole.error %]
    [% IF whole.message %]
    <div class="dialog message">There was an error processing your request: [%- whole.message | html -%].</div>
    [% ELSE %]
    <p>Unknown error</p>
    [% END %]
[% END %]

[% IF ( whole.stage == "init" ) %]
    <h2>Mark as unavailable ([% request.orderid | html %])</h2>

    [% IF ! ( request.status == 'REQ' ) %]
        <p>The current status ([% request.status | html %]) of the ILL request doesn't allow to mark this request as not available.</p>
        <p>This action is only possible until the item has been received.</p>

        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Cancel</a>

    [% ELSE %]

        <form id="SLNP_cancel_unavailable" name="SLNP_cancel_unavailable" method="POST" action=[% here | url %]>
            <fieldset class="rows">
                <legend>Cancellation</legend>
                <ol>
                    <li>
                        <label for="the_patron">Requesting patron:</label>
                        <div name="the_patron" id="the_patron">
                            <a target="_blank" href="/cgi-bin/koha/members/moremember.pl?borrowernumber=[% whole.value.patron.borrowernumber %]">
                            [% whole.value.patron.firstname | html %] [% whole.value.patron.surname | html %] ([% whole.value.patron.cardnumber | html %])</a>
                        </div>
                    </li>
                    <li>
                        <label for="notify_patron">Notify:</label>
                    [% IF whole.value.notify %]
                        <input type="checkbox" id="notify_patron" name="notify_patron" checked />
                    [% ELSE %]
                        <input type="checkbox" id="notify_patron" name="notify_patron" />
                    [% END %]
                    </li>
                </ol>

                <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id | html%]" type="hidden" />
                <input name="backend" id="backend" value="SLNP" type="hidden" />
                <input name="method" id="method" value="cancel_unavailable" type="hidden" />
                <input name="stage" id="stage" value="commit" type="hidden" />
            </fieldset>

            <fieldset class="action">
                <button type="submit" class="btn btn-default approve">
                    <i class="fa fa-check"></i> Cancel request
                </button>

                <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Cancel</a>
            </fieldset>
        </form>
    [% END %]

[% ELSE %]
    <p>Unknown stage: [% whole.stage %]</p>
[% END %]
