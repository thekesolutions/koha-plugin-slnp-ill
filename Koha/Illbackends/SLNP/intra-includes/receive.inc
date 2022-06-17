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
  <h2>Edit delivery ([% request.orderid %])</h2>
[% ELSIF whole.stage == 'init' %]
  <h2>Process delivery ([% request.orderid %])</h2>

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
          <label class="required" for="received_on_date">Received on:</label>
          <input type="text" class="datepicker" name="received_on_date" id="received_on_date" size="10" maxlength="10" value="[% whole.value.received_on_date | $KohaDates %]" required="required" />
          <span class="hint">[% INCLUDE 'date-format.inc' %]</span>
        </li>

        <li>
          <label class="required" for="lending_library">Lending library:</label>
            <select name="lending_library" id="lending_library" required="required" class="select2" style="width: 45%">
                <option value="">&nbsp;</option>
            [% FOREACH library IN whole.value.lending_libraries %]
                <option value="[% library.borrowernumber | html %]">[% library.surname | html %][% IF library.othernames %] ([% library.othernames | html %])[% END %]</option>
            [% END %]
          </select>
        </li>

        <li>
          <label for="request_charges">Cost:</label>
          <input type="text" size="10" name="request_charges" id="request_charges" value="[% whole.value.request_charges | $Price %]" />
        [% IF whole.value.charge_extra_fee_by_default %]
          <input type="checkbox" id="charge_extra_fee" name="charge_extra_fee" checked />
        [% ELSE %]
          <input type="checkbox" id="charge_extra_fee" name="charge_extra_fee" />
        [% END %]
          <span>Charge patron</span>
        </li>

        <li>
          <label for="circulation_notes">Circulation restrictions:</label>
          <input type="text" size="50" name="circulation_notes" id="circulation_notes" value="[% whole.value.other.circulation_notes | html %]" />
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
          <label for="item_callnumber">Callnumber:</label>
          <input type="text" size="50" name="item_callnumber" id="item_callnumber" value="[% whole.value.item.itemcallnumber | html %]" />
        </li>

        <li>
          <label for="item_number_of_parts">Number of parts:</label>
          <input type="text" size="50" name="item_number_of_parts" id="item_number_of_parts" value="[% whole.value.item.materials | html %]" />
        </li>

        <li>
          <label for="item_usage_restrictions">Usage restrictions:</label>
          [% PROCESS 'av-build-dropbox.inc' name="item_usage_restrictions", category="RESTRICTED", empty=1, default=whole.value.item.restricted %]
        </li>

        <li>
          <label for="item_damaged">Damaged:</label>
          [% PROCESS 'av-build-dropbox.inc' name="item_damaged", category="DAMAGED", empty=1, default=whole.value.item.damaged %]
        </li>

        <li>
          <label for="item_internal_note">Internal note:</label>
          <input type="text" size="50" name="item_internal_note" id="item_internal_note" value="[% whole.value.item.itemnotes_nonpublic | html %]" />
        </li>

        <li>
          <label for="due_date">Due date:</label>
          <input type="text" class="datepicker" name="due_date" id="due_date" size="10" maxlength="10" value="[% whole.value.other.due_date | $KohaDates %]" />
         <span class="hint">[% INCLUDE 'date-format.inc' %]</span>
        </li>

      </ol>
    </fieldset>

    <fieldset class="rows">
    <legend>Notification</legend>
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
    </fieldset>

    <fieldset class="action">
      <input type="hidden" name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" />
      <input type="hidden" name="backend" id="backend" value="[% request.backend %]" />
      <input type="hidden" name="method" id="method" value="receive" />
      <input type="hidden" name="stage" id="stage" value="commit" />
      <input type="hidden" name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber %]" />

      <button type="submit" class="btn btn-default approve">
        <i class="fa fa-check"></i> Receive
      </button>

      <button type="submit" class="btn btn-default openWin" data-url="/api/v1/contrib/slnp/ill_requests/[% whole.illrequest_id | uri %]/print_slips/ILL_RECEIVE_SLIP" data-prevent-default="yes">
        <i class="fa fa-print"></i> Print slip and receive
      </button>

      <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Cancel</a>

    </fieldset>
  </form>

[% ELSE %]
  <p>Unknown stage: '[% whole.stage %]'</p>
[% END %]

<script>
    document.addEventListener('DOMContentLoaded', function() {
        $('#lending_library').select2();

        function Dopop(link) {
            var newin = window.open(link, 'popup', 'width=600,height=400,resizable=1,toolbar=0,scrollbars=1,top');
        }

        $('.openWin').on("click",function(e){
            Dopop( $(this).data("url") );

            if ( $(this).data("prevent-default" === 'yes' ) ) {
                e.preventDefault();
            }
        });
    });
</script>
