<h2>Mark as lost/missing ([% request.orderid %])</h2>
<p>Setting an item to lost/missing is done by setting the corresponding status for the ILL item.<br>
   By doing this the status of the ILL request will be set to 'Lost' or 'Missing'.<br> 
   ILL requests with this status can be closed by creating a 'Loss notification'.<br>
   Only by using the 'Loss notification' action a notice will be sent to the lending library and where appropriate to the patron.
</p>

<a class="text" href="/cgi-bin/koha/catalogue/detail.pl?biblionumber=[% request.biblio_id %]" target="_blank" >Set lost status</a>

<a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id %]">Cancel</a>
