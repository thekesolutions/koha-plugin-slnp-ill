$(document).ready(function(){

    // button use case (single backend)
    $("#opac-illrequests #ill-new[href*='backend=SLNP']")
        .attr('href','{{portal_url}}')
        .attr('target','_blank');
    // dropdown use case
    $("#opac-illrequests #illrequests-create-button a[href*='backend=SLNP']")
        .attr('href','{{portal_url}}')
        .attr('target','_blank');
});
