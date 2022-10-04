package Koha::Illbackends::SLNP::Base;

# Copyright 2018-2021 (C) LMSCLoud GmbH
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Carp;
use Clone qw( clone );
use Data::Dumper;
use File::Basename qw( dirname );
use JSON qw( to_json );
use MARC::Record;
use Scalar::Util qw(blessed);
use Try::Tiny;
use URI::Escape;
use XML::LibXML;
use YAML;

use C4::Biblio qw( AddBiblio DelBiblio );
use C4::Context;
use C4::Letters qw(GetPreparedLetter);
use C4::Members::Messaging;
use C4::Reserves qw(AddReserve);

use Koha::Biblios;
use Koha::Database;
use Koha::DateUtils qw(dt_from_string output_pref);
use Koha::Illrequest::Config;
use Koha::Items;
use Koha::Libraries;
use Koha::Logger;
use Koha::Patron::Attributes;
use Koha::Patron::Categories;
use Koha::Patrons;

use Koha::Plugin::Com::Theke::SLNP;
use SLNP::Exceptions;

=head1 NAME

Koha::Illbackends::SLNP::Base - Koha ILL Backend: SLNP

=head1 SYNOPSIS

Koha ILL implementation for the "SLNP" backend.

Some library consortia in Germany run ILL servers that use SLNP (Simple Library Network Protocol) 
for communication with the integrated library management systems.
ZFL is the abbreviation for 'Zentrale Fernleihe' (central interlibrary loan).

=head1 DESCRIPTION

SLNP (TM) (Simple Library Network Protocol) is a TCP network socket based protocol 
designed and introduced by the company Sisis Informationssysteme GmbH (later a part of OCLC) 
for their library management system SISIS-SunRise (TM).
This protocol supports the bussiness processes of libraries.
A subset of SLNP that enables the communication required for regional an national ILL (Inter Library Loan) processes
has been published by Sisis Informationssysteme GmbH as basis for 
connection of library management systems to ILL servers that use SLNP.
Sisis Informationssysteme GmbH / OCLC owns all rights to SLNP.
SLNP is a registered trademark of Sisis Informationssysteme GmbH / OCLC.

This ILL backend provides a simple method to handle Interlibrary Loan requests that are initiated by an regional ILL server using the SLNP protocol.
The additional service 'ILLZFLServerKoha' manages the communication with the regional ILL server and will insert records in tables illrequests and illrequestattributes by calling the 'create' method of SLNP. 
The remaining features of this ILL backend are accessible via the standard ILL framework in the Koha staff interface.

=head1 API

=head2 Class methods

=head3 new

=cut

sub new {

    # -> instantiate the backend
    my ($class) = @_;

    my $plugin = Koha::Plugin::Com::Theke::SLNP->new;
    my $configuration = $plugin->configuration;

    my $self = {
        framework     => $configuration->{default_framework} // 'FA',
        plugin        => $plugin,
        configuration => $configuration,
        logger        => Koha::Logger->get,
    };

    bless( $self, $class );
    return $self;
}

=head3 _config

    my $config = $slnp_backend->_config($config);
    my $config = $slnp_backend->_config;

Getter/Setter for our config object.

=cut

sub _config {
    my ( $self, $config ) = @_;

    $self->{config} = $config if ($config);

    return $self->{config};
}

=head3 status_graph

=cut

sub status_graph {
    return {
        REQ => {
            prev_actions   => [],
            id             => 'REQ',
            name           => 'Bestellt',
            ui_method_name => undef,
            method         => undef,
            next_actions   => [ 'RECVD', 'NEGFLAG' ],
            ui_method_icon => '',
        },

        RECVD => {
            prev_actions   => [ 'REQ' ],
            id             => 'RECVD',
            name           => 'Eingangsverbucht',
            ui_method_name => 'Eingang verbuchen',
            method         => 'receive',
            next_actions   => [ 'RECVDUPD' ],                    # in reality: ['CHK']
            ui_method_icon => 'fa-download',
        },

        RECVDUPD => {
            prev_actions   => [ 'RECVD' ],
            id             => 'RECVDUPD',
            name           => 'Eingangsverbucht',
            ui_method_name => 'Eingang bearbeiten',
            method         => 'update',
            next_actions   => [],
            ui_method_icon => 'fa-pencil',
        },

        CHK => {
            prev_actions   => [],
            id             => 'CHK',
            name           => 'Ausgeliehen',
            ui_method_name => '',
            method         => '',
            next_actions   => [],
            ui_method_icon => 'fa-check',
        },

        RET => {
            prev_actions   => [],
            id             => 'RET',
            name           => "R\N{U+fc}ckgegeben",
            ui_method_name => '',
            method         => '',
            next_actions   => ['COMP'],
            ui_method_icon => 'fa-check',
        },

        COMP => {
            prev_actions   => [ 'RET' ],
            id             => 'COMP',
            name           => 'Completed',
            ui_method_name => 'Mark completed',
            method         => 'mark_completed',
            next_actions   => [],
            ui_method_icon => 'fa-check',
        },

        # # Pseudo status, not stored in illrequests. Sole purpose: displaying "Rueckversenden" dialog (status becomes 'COMP')
        # SNTBCK => {                                               # medium is sent back, mark this ILL request as COMP
        #     prev_actions   => [ 'RECVD', 'CNCLDFU', 'RET' ],
        #     id             => 'SNTBCK',
        #     name           => "Zur\N{U+fc}ckversandt",
        #     ui_method_name => "R\N{U+fc}ckversenden",
        #     method         => 'sendeZurueck',
        #     next_actions   => [],                                 # in reality: ['COMP']
        #     ui_method_icon => 'fa-check',
        # },

        # # Pseudo status, not stored in illrequests. Sole purpose: displaying 'Verlust buchen' dialog (status stays unchanged)
        # LOSTHOWTO => {
        #     prev_actions   => [ 'RECVD', 'CHK', 'RET' ],
        #     id             => 'LOSTHOWTO',
        #     name           => 'Verlust HowTo',
        #     ui_method_name => 'Verlust buchen',
        #     method         => 'bucheVerlust',
        #     next_actions   => [],                                 # in reality: status stays unchanged
        #     ui_method_icon => 'fa-times',
        # },

        # # status 'LostBeforeCheckOut' (not for GUI, now internally handled by itemLost(), called by cataloguing::additem.pl and catalogue::updateitem.pl )
        # LOSTBCO => {                                              # lost by library Before CheckOut
        #     prev_actions   => [],                                     # Officially empty, so not used in GUI. in reality: ['RECVD']
        #     id             => 'LOSTBCO',
        #     name           => 'Verlust vor Ausleihe',
        #     ui_method_name => 'Aufruf_durch_Koha_Verlust-Buchung',    # not used in GUI
        #     method         => 'itemLost',
        #     next_actions   => [],                                     # in reality: ['COMP']
        #     ui_method_icon => 'fa-times',
        # },

        # # status 'LostAfterCheckOut' (not for GUI, now internally handled by itemLost(), called by cataloguing::additem.pl and catalogue::updateitem.pl )
        # LOSTACO => {                                                  # lost by user After CheckOut or by library after CheckIn
        #     prev_actions   => [],                                     # Officially empty, so not used in GUI. in reality: ['CHK', 'RET']
        #     id             => 'LOSTACO',
        #     name           => 'Verlust',
        #     ui_method_name => 'Aufruf_durch_Koha_Verlust-Buchung',    # not used in GUI
        #     method         => 'itemLost',
        #     next_actions   => [],                                     # in reality: ['COMP']
        #     ui_method_icon => 'fa-times',
        # },

        # # Pseudo status, not stored in illrequests. Sole purpose: displaying 'Verlust melden' dialog (status becomes 'COMP')
        # LOST => {
        #     prev_actions   => [ 'LOSTBCO', 'LOSTACO' ],
        #     id             => 'LOST',
        #     name           => 'Verlustgebucht',
        #     ui_method_name => 'Verlust melden',
        #     method         => 'meldeVerlust',
        #     next_actions   => ['COMP'],
        #     ui_method_icon => 'fa-times',
        # },

        # Pseudo status, not stored in illrequests. Sole purpose: displaying 'Negativ-Kennzeichen' dialog (status becomes 'COMP')
        NEGFLAG => {
            prev_actions => [ 'REQ' ],
            id           => 'NEGFLAG',
            name         => "Negativ/gel\N{U+f6}scht",

            #ui_method_name => "Negativ-Kennzeichen / l\N{U+f6}schen",
            ui_method_name => 'Negativ-Kennzeichen',
            method         => 'cancel_unavailable',
            next_actions   => [],                      # in reality: ['COMP']
            ui_method_icon => 'fa-times',
        },
    };
}

sub name {
    return "SLNP";
}

=head3 capabilities

    $capability = $backend->capabilities($name);

Return the sub implementing a capability selected by I<$name>, or 0 if that
capability is not implemented.

=cut

# sub capabilities {
#     my ( $self, $name ) = @_;
#     my ($query) = @_;
#     my $capabilities = {

# # experimental, general access, not used yet (usage: my $duedate = $illrequest->_backend_capability( "getIllrequestattributes", [$illrequest,["duedate"]] );)
#         getIllrequestattributes => sub { $self->getIllrequestattributes(@_); },

#         # used capabilities:
#         getIllrequestDateDue   => sub { $self->getIllrequestDateDue(@_); },
#         isShippingBackRequired => sub { $self->isShippingBackRequired(@_); },
#         itemCheckedOut         => sub { $self->itemCheckedOut(@_); },
#         itemCheckedIn          => sub { $self->itemCheckedIn(@_); },
#         itemLost               => sub { $self->itemLost(@_); },
#         isReserveFeeAcceptable => sub { $self->isReserveFeeAcceptable(@_); },
#         sortAction             => sub { $self->sortAction(@_); }
#     };
#     return $capabilities->{$name};
# }

=head3 metadata

Return a hashref containing canonical values from the key/value
illrequestattributes table.
Theese canonical values are used in the table view and record view of the ILL framework
und so can not be renamed without adaptions.

=cut

sub metadata {
    my ( $self, $request ) = @_;

    my %map = (
        'Article_author' => 'article_author',    # used alternatively to 'Author'
        'Article_title'  => 'article_title',     # used alternatively to 'Title'
        'Author'         => 'author',
        'ISBN'           => 'isbn',
        'Order ID'       => 'zflorderid',
        'Title'          => 'title',
    );

    my %attr;
    for my $k ( keys %map ) {
        my $v = $request->illrequestattributes->find( { type => $map{$k} } );
        $attr{$k} = $v->value if defined $v;
    }
    if ( $attr{Article_author} ) {
        if ( length( $attr{Article_author} ) ) {
            $attr{Author} = $attr{Article_author};
        }
        delete $attr{Article_author};
    }
    if ( $attr{Article_title} ) {
        if ( length( $attr{Article_title} ) ) {
            $attr{Title} = $attr{Article_title};
        }
        delete $attr{Article_title};
    }

    return \%attr;
}

=head3 create

    my $response = $slnp_backend->create( $params );

Checks values in $params and inserts an illrequests record.
The values in $params normally are filled by SLNPFLBestellung.pm based on the request parameters of the received SLNP command 'SLNPFLBestellung'.
Returns an ILL backend standard response for the create method call.

=cut

sub create {
    my ( $self, $params ) = @_;
    my $stage = $params->{other}->{stage};

    my $backend_result = {
        backend => $self->name,
        method  => 'create',
        stage   => $stage,
        error   => 0,
        status  => '',
        message => '',
        value   => {}
    };

    # Initiate process stage is dummy for SLNP
    if ( !$stage || $stage eq 'init' ) {

        # ILL request is created by the external server sending
        # a SLNPFLBestellung request, so no manual handling at this stage
        # Pass useful information for rendering the create page
        $backend_result->{value}->{portal_url} = $self->{configuration}->{portal_url} // 'https://fix.me';
    }

    # Validate SLNP request parameter values and insert new ILL request in DB
    elsif ( $stage eq 'commit' ) {

        # Search for the patron using the passed cardnumber
        my $patron = Koha::Patrons->find({ cardnumber => $params->{other}->{attributes}->{cardnumber} });

        SLNP::Exception::PatronNotFound->throw(
            "Patron not found with cardnumber: "
              . $params->{other}->{attributes}->{cardnumber} )
          unless $patron;

        $params->{other}->{borrowernumber} = $patron->borrowernumber;
        $backend_result->{borrowernumber} = $params->{other}->{borrowernumber};

        SLNP::Exception::MissingParameter->throw( param => 'title')
          unless $params->{other}->{attributes}->{title};

        SLNP::Exception::MissingParameter->throw( param => 'medium')
          unless $params->{other}->{medium};

        my $library_id = $params->{other}->{branchcode};

        SLNP::Exception::MissingParameter->throw( param => 'branchcode')
          unless $library_id;

        SLNP::Exception::BadConfig->throw( param => 'default_ill_branch', value => $library_id )
          unless Koha::Libraries->find($library_id);

        my $biblio_id = $self->add_biblio( $params->{other} );
        my $item_id   = $self->add_item(
            {
                biblio_id       => $biblio_id,
                medium          => $params->{other}->{medium},
                library_id      => $library_id,
                callnumber      => $params->{other}->{attributes}->{shelfmark},
                notes           => undef,
                notes_nonpublic => $params->{other}->{attributes}->{notes},
                orderid         => $params->{other}->{orderid},                   # zflorderid
            }
        )->id;

        my $now = dt_from_string();
        my $fee = $self->charge_ill_fee( { patron => $patron, item_id => $item_id } );

        $params->{request}->set(
            {
                borrowernumber => $patron->borrowernumber,
                biblio_id      => $biblio_id,
                branchcode     => $library_id,
                status         => 'REQ',
                placed         => $now,
                updated        => $now,
                medium         => $params->{other}->{medium},
                orderid        => $params->{other}->{orderid},
                backend        => $self->name,
                price_paid     => "$fee", # FIXME: varchar => formatting?
            }
        )->store;

        # populate table illrequestattributes
        $params->{other}->{attributes}->{item_id} = $item_id;
        while ( my ( $type, $value ) = each %{ $params->{other}->{attributes} } ) {

            try {
                Koha::Illrequestattribute->new(
                    {   illrequest_id => $params->{request}->illrequest_id,
                        type          => $type,
                        value         => $value,
                    }
                )->store;
            };
        }

        $backend_result->{stage} = "commit";
        $backend_result->{value} = $params;
    }

    # Invalid stage, return error.
    else {
        $backend_result->{stage}  = $params->{stage};
        $backend_result->{error}  = 1;
        $backend_result->{status} = 'unknown_stage';
    }

    return $backend_result;
}

=head3 receive

    $backend->receive;

Handle receiving the request. It should involve the following I<stage>:

=over

=item B<no stage> initial stage, for rendering the form (a.k.a. I<init>).

=item B<commit> process the receiving parameters.

=back

=cut

sub receive {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $method  = $params->{other}->{method};
    my $stage   = $params->{other}->{stage};

    my $item = $self->get_item_from_request({ request => $request });

    my $template_params = {};

    my $backend_result = {
        backend => $self->name,
        method  => "receive",
        stage   => $stage, # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => $template_params,
        next    => "illview",
        illrequest_id => $request->id,
    };

    if ( !defined $stage ) { # init
        $template_params->{medium} = $request->medium;

        my $partner_category_code = $self->{configuration}->{partner_category_code} // 'IL';
        $template_params->{mandatory_lending_library} = !defined $self->{configuration}->{mandatory_lending_library}
          ? 1    # defaults to true
          : ( $self->{configuration}->{mandatory_lending_library} eq 'false' ) ? 0 : 1;

        my $lending_libraries = Koha::Patrons->search(
            { categorycode => $partner_category_code },
            { order_by     => [ 'surname', 'othernames' ] }
        );

        $self->{logger}->error("No patrons defined as lending libraries (categorycode=$partner_category_code)")
          unless $lending_libraries->count > 0;

        $template_params->{received_on_date}  = dt_from_string;
        $template_params->{lending_libraries} = $lending_libraries;
        $template_params->{item}              = $item;
        $template_params->{patron}            = $request->patron;

        # FIXME: Check in newer Koha how booleans are dealth with in YAML
        $template_params->{charge_extra_fee_by_default} =
          ( $self->{configuration}->{charge_extra_fee_by_default} eq 'true' )
          ? 1
          : 0;

        my $patron_preferences = C4::Members::Messaging::GetMessagingPreferences({
            borrowernumber => $template_params->{patron}->borrowernumber,
            message_name   => 'Ill_ready',
        });

        if ( exists $patron_preferences->{transports}->{email} ) {
            $template_params->{notify} = 1;
        }

        $template_params->{opac_note}  = $request->notesopac;
        $template_params->{staff_note} = $request->notesstaff;

        $template_params->{item_types} = [
            { value => $self->get_item_type( 'copy' ), selected => ( $request->medium eq 'copy' ) ? 1 : 0 },
            { value => $self->get_item_type( 'loan' ), selected => ( $request->medium eq 'loan' ) ? 1 : 0 },
        ];

        $backend_result->{stage} = 'init';
    }
    elsif ( $stage eq 'commit' ) {
        # process the receiving parameters

        try {
            Koha::Database->new->schema->txn_do(
                sub {

                my $request_type = $params->{other}->{type} // 'loan';

                my $new_attributes = {};

                $new_attributes->{type} = $request_type eq 'loan' ? 'Leihe' : 'Kopie';

                $new_attributes->{received_on_date} = dt_from_string($params->{other}->{received_on_date})
                if $params->{other}->{received_on_date};

                $new_attributes->{due_date} = dt_from_string($params->{other}->{due_date})
                if $params->{other}->{due_date};

                $new_attributes->{request_charges} = $params->{other}->{request_charges}
                if $params->{other}->{request_charges};

                $new_attributes->{lending_library} = $params->{other}->{lending_library}
                if $params->{other}->{lending_library};

                if ( $params->{other}->{charge_extra_fee} and
                    $params->{other}->{request_charges} and
                    $params->{other}->{request_charges} > 0 ) {
                    my $debit = $request->patron->account->add_debit(
                        {
                            amount    => $params->{other}->{request_charges},
                            item_id   => $item->id,
                            interface => 'intranet',
                            type      => $self->{configuration}->{extra_fee_debit_type} // 'ILL',
                        }
                    );

                    $request->cost($params->{other}->{request_charges});
                    $new_attributes->{debit_id} = $debit->id;
                }

                $new_attributes->{circulation_notes} =
                $params->{other}->{circulation_notes}
                if $params->{other}->{circulation_notes};

                # place a hold on behalf of the patron
                # FIXME: Should call CanItemBeReserved first?
                my $biblio  = $request->biblio;
                my $hold_id = C4::Reserves::AddReserve(
                    {
                        branchcode       => $request->branchcode,
                        borrowernumber   => $request->borrowernumber,
                        biblionumber     => $request->biblio_id,
                        priority         => 1,
                        reservation_date => undef,
                        expiration_date  => undef,
                        notes            => $self->{configuration}->{default_hold_note} // 'Placed by ILL',
                        title            => $biblio->title,
                        itemnumber       => $item->id,
                        found            => undef,
                        itemtype         => undef
                    }
                );

                $new_attributes->{hold_id} = $hold_id;

                while ( my ( $type, $value ) = each %{$new_attributes} ) {

                    my $attr = $request->illrequestattributes->find(
                        {
                            type => $type
                        }
                    );

                    if ($attr) {    # update
                        if ( $attr->value ne $value ) {
                            $attr->update( { value => $value, } );
                        }
                    }
                    else {          # new
                        $attr = Koha::Illrequestattribute->new(
                            {
                                illrequest_id => $request->id,
                                type          => $type,
                                value         => $value,
                            }
                        )->store;
                    }
                }

                # item information
                my $item_type = $self->{configuration}->{item_types}->{$request_type};
                $item->set(
                    {   itype               => $item_type,
                        restricted          => $params->{other}->{item_usage_restrictions},
                        itemcallnumber      => $params->{other}->{item_callnumber},
                        damaged             => $params->{other}->{item_damaged},
                        itemnotes_nonpublic => $params->{other}->{item_internal_note},
                        materials           => $params->{other}->{item_number_of_parts},
                    }
                )->store;

                $request->set(
                    {   medium     => $request_type,
                        notesopac  => $params->{other}->{opac_note},
                        notesstaff => $params->{other}->{staff_note},
                        status     => 'RECVD',
                    }
                )->store;

                $backend_result->{stage} = 'commit';
            });
        }
        catch {
            warn "$_";
            if ( blessed($_) and $_->isa('Koha::Exceptions::Account::UnrecognisedType') ) {
                $backend_result->{status} = 'invalid_debit_type';
            }
            else {
                $backend_result->{status} = 'unknown';
            }

            $backend_result->{error}  = 1;
            $backend_result->{stage} = 'commit';
        };
    }
    else {
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

=head3 update

    $backend->update;

Handle updating the request.

=cut

sub update {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $method  = $params->{other}->{method};
    my $stage   = $params->{other}->{stage};

    my $item = $self->get_item_from_request({ request => $request });

    my $template_params = {};

    my $backend_result = {
        backend => $self->name,
        method  => "update",
        stage   => $stage, # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => $template_params,
        next    => "illview",
        illrequest_id => $request->id,
    };

    if ( !defined $stage ) { # init, show information

        $template_params->{medium} = $request->medium;

        my $partner_category_code = $self->{configuration}->{partner_category_code} // 'IL';
        $template_params->{mandatory_lending_library} = !defined $self->{configuration}->{mandatory_lending_library}
          ? 1    # defaults to true
          : ( $self->{configuration}->{mandatory_lending_library} eq 'false' ) ? 0 : 1;

        my $lending_libraries = Koha::Patrons->search(
            { categorycode => $partner_category_code },
            { order_by     => [ 'surname', 'othernames' ] }
        );

        $template_params->{lending_libraries} = $lending_libraries;
        my $selected_lending_library = $request->illrequestattributes->search({ type => 'lending_library' })->next;
        $template_params->{selected_lending_library_id} = $selected_lending_library->value
          if $selected_lending_library;

        my $request_charges = $request->illrequestattributes->search({ type => 'request_charges' })->next;
        $template_params->{request_charges} = $request_charges->value
          if $request_charges;

        my $circulation_notes = $request->illrequestattributes->search({ type => 'circulation_notes' })->next;
        $template_params->{circulation_notes} = $circulation_notes->value
          if $circulation_notes;

        my $received_on_date = $request->illrequestattributes->search({ type => 'received_on_date' })->next;
        $template_params->{received_on_date} = dt_from_string($received_on_date->value)
          if $received_on_date;

        my $due_date = $request->illrequestattributes->search({ type => 'due_date' })->next;
        $template_params->{due_date} = dt_from_string($due_date->value)
          if $due_date;

        $template_params->{item}   = $item;
        $template_params->{patron} = $request->patron;

        $template_params->{opac_note}  = $request->notesopac;
        $template_params->{staff_note} = $request->notesstaff;

        $template_params->{item_types} = [
            { value => $self->get_item_type( 'copy' ), selected => ( $request->medium eq 'copy' ) ? 1 : 0 },
            { value => $self->get_item_type( 'loan' ), selected => ( $request->medium eq 'loan' ) ? 1 : 0 },
        ];

        $backend_result->{stage} = 'init';
    }
    elsif ( $stage eq 'commit' ) {
        # process the receiving parameters

        try {

            my $request_type = $params->{other}->{type} // 'loan';

            my $new_attributes = {};

            $new_attributes->{type} = $request_type eq 'loan' ? 'Leihe' : 'Kopie';

            $new_attributes->{received_on_date} = dt_from_string( $params->{other}->{received_on_date} )
              if $params->{other}->{received_on_date};

            $new_attributes->{due_date} = dt_from_string( $params->{other}->{due_date} )
              if $params->{other}->{due_date};

            $new_attributes->{request_charges} = $params->{other}->{request_charges}
              if $params->{other}->{request_charges};

            $new_attributes->{lending_library} = $params->{other}->{lending_library};

            if ( $params->{other}->{charge_extra_fee} and
                 $params->{other}->{request_charges} and
                 $params->{other}->{request_charges} > 0 ) {
                my $debit = $request->patron->account->add_debit(
                    {
                        amount => $params->{other}->{request_charges},
                        type   => $self->{configuration}->{extra_fee_debit_type}
                          // 'ILL',
                        interface => 'intranet',
                    }
                );

                $new_attributes->{debit_id} = $debit->id;
            }

            $new_attributes->{circulation_notes} =
              $params->{other}->{circulation_notes}
              if $params->{other}->{circulation_notes};

            while ( my ( $type, $value ) = each %{$new_attributes} ) {

                my $attr = $request->illrequestattributes->find(
                    {
                        type => $type
                    }
                );

                if ($attr) {    # update
                    if ( $attr->value ne $value ) {
                        $attr->update( { value => $value, } );
                    }
                }
                else {          # new
                    $attr = Koha::Illrequestattribute->new(
                        {
                            illrequest_id => $request->id,
                            type          => $type,
                            value         => $value,
                        }
                    )->store;
                }
            }

            # item information
            $item->itype( $params->{other}->{item_type} )
              if $params->{other}->{item_type};

            $item->restricted( $params->{other}->{item_usage_restrictions} )
              if defined $params->{other}->{item_usage_restrictions};

            $item->itemcallnumber( $params->{other}->{item_callnumber} )
              if $params->{other}->{item_callnumber};

            $item->damaged ( $params->{other}->{item_damaged} )
              if $params->{other}->{item_damaged};

            $item->itemnotes_nonpublic( $params->{other}->{item_internal_note} )
              if $params->{other}->{item_internal_note};

            $item->materials( $params->{other}->{item_number_of_parts} )
              if $params->{other}->{item_number_of_parts};

            $item->store;

            if ( $params->{other}->{notify_patron} eq 'on' ) {
                my $letter = $request->get_notice(
                    { notice_code => 'ILL_PICKUP_READY', transport => 'email' }
                );

                my $result = C4::Letters::EnqueueLetter(
                    {
                        letter                 => $letter,
                        borrowernumber         => $request->borrowernumber,
                        message_transport_type => 'email',
                    }
                );
            }

            # item information
            my $item_type = $self->{configuration}->{item_types}->{$request_type};
            $item->set(
                {   itype               => $item_type,
                    restricted          => $params->{other}->{item_usage_restrictions},
                    itemcallnumber      => $params->{other}->{item_callnumber},
                    damaged             => $params->{other}->{item_damaged},
                    itemnotes_nonpublic => $params->{other}->{item_internal_note},
                    materials           => $params->{other}->{item_number_of_parts},
                }
            )->store;

            $request->set(
                {   medium     => $request_type,
                    notesopac  => $params->{other}->{opac_note},
                    notesstaff => $params->{other}->{staff_note},
                }
            )->store;

            $backend_result->{stage} = 'commit';
        }
        catch {
            warn "$_";
            $backend_result->{stage} = 'commit';
        };
    }
    else {
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

sub format_to_dbmoneyfloat {
    my ($floatstr) = @_;
    my $ret = $floatstr;

# The float value in $floatstr has been formatted by javascript for display in the HTML page, but we need it in database form again (i.e without thousands separator, with decimal separator '.').
    my $thousands_sep = ' ';                      # default, correct if Koha.Preference("CurrencyFormat") == 'FR'  (i.e. european format like "1 234 567,89")
    if ( substr( $floatstr, -3, 1 ) eq '.' ) {    # american format, like "1,234,567.89"
        $thousands_sep = ',';
    }
    $ret =~ s/$thousands_sep//g;                  # get rid of the thousands separator
    $ret =~ tr/,/./;                              # decimal separator in DB is '.'
    return $ret;
}

sub printIllNoticeSlnp {
    my ( $branchcode, $borrowernumber, $biblionumber, $itemnumber, $illrequest_id, $illreqattr_hashptr, $accountBorrowernumber, $letter_code ) = @_;
    #my $noticeFees          = C4::NoticeFees->new();
    my $patron              = Koha::Patrons->find($borrowernumber);
    my $library             = Koha::Libraries->find($branchcode)->unblessed;
    my $admin_email_address = $library->{branchemail} || C4::Context->preference('KohaAdminEmailAddress');

    # Try to get the borrower's email address
    my $to_address = $patron->notice_email_address;

    my %letter_params = (
        module     => 'circulation',
        branchcode => $branchcode,
        lang       => $patron->lang,
        tables     => {
            'branches'             => $library,
            'borrowers'            => $patron->unblessed,
            'biblio'               => $biblionumber,
            'biblioitems'          => $biblionumber,
            'items'                => $itemnumber,
            'account'              => $accountBorrowernumber,    # if $borrowernumber marks sending library, this marks the orderer, and vice versa (or 0)
            'illrequests'          => $illrequest_id,
            'illrequestattributes' => $illreqattr_hashptr,
        },
    );

    my $send_notification = sub {
        my ( $mtt, $borrowernumber, $letter_code ) = (@_);
        return unless defined $letter_code;
        $letter_params{letter_code}            = $letter_code;
        $letter_params{message_transport_type} = $mtt;
        my $letter = C4::Letters::GetPreparedLetter(%letter_params);
        unless ($letter) {
            warn "Could not find a letter called '$letter_params{'letter_code'}' for $mtt in the '$letter_params{'module'}' module";
            return;
        }

        C4::Letters::EnqueueLetter(
            {   letter                 => $letter,
                borrowernumber         => $borrowernumber,
                from_address           => $admin_email_address,
                message_transport_type => $mtt,
                branchcode             => $branchcode
            }
        );

        # # check whether there are notice fee rules defined
        # if ( $noticeFees->checkForNoticeFeeRules() == 1 ) {

        #     #check whether there is a matching notice fee rule
        #     my $noticeFeeRule = $noticeFees->getNoticeFeeRule( $letter_params{branchcode}, $patron->categorycode, $mtt, $letter_code );

        #     if ($noticeFeeRule) {
        #         my $fee = $noticeFeeRule->notice_fee();

        #         if ( $fee && $fee > 0.0 ) {

        #             # Bad for the patron, staff has assigned a notice fee for sending the notification
        #             $noticeFees->AddNoticeFee(
        #                 {   borrowernumber => $borrowernumber,
        #                     amount         => $fee,
        #                     letter_code    => $letter_code,
        #                     letter_date    => output_pref( { dt => dt_from_string, dateonly => 1 } ),

        #                     # these are parameters that we need for fancy message printing
        #                     branchcode => $letter_params{branchcode},
        #                     substitute => {
        #                         bib     => $library->{branchname},
        #                         'count' => 1,
        #                     },
        #                     tables => $letter_params{tables}

        #                 }
        #             );
        #         }
        #     }
        # }
    };

    if ($to_address) {
        &$send_notification( 'email', $borrowernumber, $letter_code );
    } else {
        &$send_notification( 'print', $borrowernumber, $letter_code );
    }
}

# shipping back the ILL item to the owning library
sub sendeZurueck {
    my ( $self, $params ) = @_;
    my $stage          = $params->{other}->{stage};
    my $backend_result = {
        backend => $self->name,
        method  => "sendeZurueck",
        stage   => $stage,           # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => {},
        next    => "illview",
    };
    $backend_result->{value}->{other}->{illshipbacklettercode} = C4::Context->preference("illShipBackLettercode");
    if ( $backend_result->{value}->{other}->{illshipbacklettercode} ) {
        $backend_result->{value}->{other}->{illshipbackslipprint} = 1;
    } else {
        $backend_result->{value}->{other}->{illshipbackslipprint} = 0;
    }

    $backend_result->{illrequest_id}                      = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{illrequest_id}  = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{biblio_id}      = $params->{request}->biblio_id();
    $backend_result->{value}->{request}->{borrowernumber} = $params->{request}->borrowernumber();
    $backend_result->{value}->{other}->{type}             = $params->{request}->medium();

    if ( !$stage || $stage eq 'init' ) {
        $backend_result->{stage} = "confirmcommit";
    } elsif ( $stage eq 'storeandprint' || $stage eq 'commit' ) {

        # read relevant data from illrequestatributes
        my @interesting_fields = ( 'isbn', 'issn', 'itemnumber', 'sendingIllLibraryBorrowernumber', 'sendingIllLibraryIsil', 'shelfmark', 'title', 'zflorderid' );

        my $fieldResults = $params->{request}->illrequestattributes->search( { type => { '-in' => \@interesting_fields } } );
        my $illreqattr   = { map { ( $_->type => $_->value ) } ( $fieldResults->as_list ) };
        foreach my $type ( keys %{$illreqattr} ) {
            $backend_result->{value}->{other}->{$type} = $illreqattr->{$type};
        }

        # finally delete biblio and items data
        #XXXWH delBiblioAndItem(scalar $params->{request}->biblio_id(), $backend_result->{value}->{other}->{itemnumber});

        # set illrequest.completed date to today
        $params->{request}->completed( output_pref( { dt => dt_from_string, dateformat => 'iso' } ) );
        $params->{request}->status('COMP')->store;

        $backend_result->{value}->{request} = $params->{request};
        $backend_result->{value}->{other}->{illshipbackslipprint} = $params->{other}->{illshipbackslipprint};

    } else {

        # in case of faulty or testing stage, we just return the standard $backend_result with original stage
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

# display a dialog that explains how to mark an ILL item as lost
sub bucheVerlust {
    my ( $self, $params ) = @_;
    my $stage          = $params->{other}->{stage};
    my $backend_result = {
        backend => $self->name,
        method  => "bucheVerlust",
        stage   => $stage,           # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => {},
        next    => "illview",
    };

    $backend_result->{illrequest_id}                      = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{illrequest_id}  = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{biblio_id}      = $params->{request}->biblio_id();
    $backend_result->{value}->{request}->{borrowernumber} = $params->{request}->borrowernumber();
    $backend_result->{value}->{other}->{type}             = $params->{request}->medium();

    return $backend_result;
}

# if the ILL item is lost, display a dialog that enables a message to the owning library (and the orderer) that the item can not be shipped back
sub meldeVerlust {
    my ( $self, $params ) = @_;
    my $stage          = $params->{other}->{stage};
    my $backend_result = {
        backend => $self->name,
        method  => "meldeVerlust",
        stage   => $stage,           # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => {},
        next    => "illview",
    };

    $backend_result->{illrequest_id}                      = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{illrequest_id}  = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{biblio_id}      = $params->{request}->biblio_id();
    $backend_result->{value}->{request}->{borrowernumber} = $params->{request}->borrowernumber();
    $backend_result->{value}->{other}->{type}             = $params->{request}->medium();

    if ( !$stage || $stage eq 'init' ) {
        $backend_result->{stage} = "confirmcommit";

# information for the owning library that the ordered ILL medium has been lost (e.g. with letter.code ILLSLNP_LOSTITEM_LIBRARY) if configured (syspref ILLItemLostLibraryLettercode)
        $backend_result->{value}->{other}->{illitemlostlibrarylettercode} = C4::Context->preference("illItemLostLibraryLettercode");
        if ( $backend_result->{value}->{other}->{illitemlostlibrarylettercode} ) {
            $backend_result->{value}->{other}->{illitemlostlibraryletterprint} = 1;
        } else {
            $backend_result->{value}->{other}->{illitemlostlibraryletterprint} = 0;
        }

# information for the borrower that the ordered ILL medium has been lost before check out (e.g. with letter.code ILLSLNP_LOSTITEM_BORROWER) if configured (syspref ILLItemLostBorrowerLettercode)
        $backend_result->{value}->{other}->{illitemlostborrowerlettercode} = C4::Context->preference("illItemLostBorrowerLettercode");
        if ( $backend_result->{value}->{other}->{illitemlostborrowerlettercode} ) {
            $backend_result->{value}->{other}->{illitemlostborrowerletterprint} = 1;
        } else {
            $backend_result->{value}->{other}->{illitemlostborrowerletterprint} = 0;
        }

        # read relevant data from illrequestatributes
        my @interesting_fields = ( 'itemnumber', 'sendingIllLibraryBorrowernumber' );

        my $fieldResults = $params->{request}->illrequestattributes->search( { type => { '-in' => \@interesting_fields } } );
        my $illreqattr   = { map { ( $_->type => $_->value ) } ( $fieldResults->as_list ) };
        foreach my $type ( keys %{$illreqattr} ) {
            $backend_result->{value}->{other}->{$type} = $illreqattr->{$type};
        }

    } elsif ( $stage eq 'confirmcommit' ) {
        $backend_result->{value}->{other}->{illitemlostlibrarylettercode}    = $params->{other}->{illitemlostlibrarylettercode};
        $backend_result->{value}->{other}->{illitemlostlibraryletterprint}   = $params->{other}->{illitemlostlibraryletterprint};
        $backend_result->{value}->{other}->{illitemlostborrowerlettercode}   = $params->{other}->{illitemlostborrowerlettercode};
        $backend_result->{value}->{other}->{illitemlostborrowerletterprint}  = $params->{other}->{illitemlostborrowerletterprint};
        $backend_result->{value}->{other}->{itemnumber}                      = $params->{other}->{itemnumber};
        $backend_result->{value}->{other}->{sendingIllLibraryBorrowernumber} = $params->{other}->{sendingIllLibraryBorrowernumber};

        # send information to the owning library that the ordered ILL medium has been lost (after delivery, before shipping back)
        if (   $params->{other}->{illitemlostlibraryletterprint}
            && $params->{other}->{illitemlostlibrarylettercode}
            && length( $params->{other}->{illitemlostlibrarylettercode} ) ) {
            my $fieldResults = $params->{request}->illrequestattributes->search();
            my $illreqattr   = { map { ( $_->type => $_->value ) } ( $fieldResults->as_list ) };
            &printIllNoticeSlnp(
                $params->{request}->branchcode(),
                $params->{other}->{sendingIllLibraryBorrowernumber},
                undef, undef, $params->{request}->illrequest_id(),
                $illreqattr,
                $params->{request}->borrowernumber(),
                $params->{other}->{illitemlostlibrarylettercode}
            );
        }

        if ( $params->{request}->status() eq 'LOSTBCO' ) {

            # send information to the borrower about the denied delivery of the ordered ILL medium (because it has been lost before check out)
            if (   $params->{other}->{illitemlostborrowerletterprint}
                && $params->{other}->{illitemlostborrowerlettercode}
                && length( $params->{other}->{illitemlostborrowerlettercode} ) ) {
                my $fieldResults = $params->{request}->illrequestattributes->search();
                my $illreqattr   = { map { ( $_->type => $_->value ) } ( $fieldResults->as_list ) };
                &printIllNoticeSlnp(
                    $params->{request}->branchcode(),
                    $params->{request}->borrowernumber(),
                    undef, undef, $params->{request}->illrequest_id(),
                    $illreqattr,
                    $params->{other}->{sendingIllLibraryBorrowernumber},
                    $params->{other}->{illitemlostborrowerlettercode}
                );
            }
        }

        # Finally delete biblio and items data, but only if not stored in DB table issues any more.
        # try to etrieve the issue
        my $issue = Koha::Checkouts->find( { itemnumber => $params->{other}->{itemnumber} } );
        if ( !$issue ) {
            delBiblioAndItem( $params->{request}->biblio_id(), $params->{other}->{itemnumber} );
        }

        # set illrequest.completed date to today
        $params->{request}->completed( output_pref( { dt => dt_from_string, dateformat => 'iso' } ) );
        $params->{request}->status('COMP')->store;

        $backend_result->{value}->{request} = $params->{request};
        $backend_result->{stage} = 'commit';

    } else {

        # in case of faulty or testing stage, we just return the standard $backend_result with original stage
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

# Handles the cancellation of the ordering borrower before the ILL item is received.
# If the borrower cancels his order after receipt of the ILL item in the library (before checkout), the sendeZurueck() method is used
sub storniereFuerBenutzer {
    my ( $self, $params ) = @_;
    my $stage          = $params->{other}->{stage};
    my $backend_result = {
        backend => $self->name,
        method  => "storniereFuerBenutzer",
        stage   => $stage,                    # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => {},
        next    => "illview",
    };
    $backend_result->{illrequest_id}                      = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{illrequest_id}  = $params->{request}->illrequest_id;
    $backend_result->{value}->{request}->{biblio_id}      = $params->{request}->biblio_id();
    $backend_result->{value}->{request}->{borrowernumber} = $params->{request}->borrowernumber();
    $backend_result->{value}->{other}->{type}             = $params->{request}->medium();

    if ( !$stage || $stage eq 'init' ) {
        $backend_result->{stage} = "confirmcommit";

    } elsif ( $stage eq 'commit' || $stage eq 'confirmcommit' ) {

        # read relevant data from illrequestatributes
        my @interesting_fields = ( 'itemnumber', 'author', 'title' );

        my $fieldResults = $params->{request}->illrequestattributes->search( { type => { '-in' => \@interesting_fields } } );
        my $illreqattr   = { map { ( $_->type => $_->value ) } ( $fieldResults->as_list ) };
        foreach my $type ( keys %{$illreqattr} ) {
            $backend_result->{value}->{other}->{$type} = $illreqattr->{$type};
        }

        if ( $params->{other}->{alreadyShipped} eq 'alreadyShippedYes' ) {
            $params->{request}->status('CNCLDFU')->store;
        } else {

            # finally delete biblio and items data
            delBiblioAndItem( scalar $params->{request}->biblio_id(), $backend_result->{value}->{other}->{itemnumber} );

            # set illrequest.completed date to today
            $params->{request}->completed( output_pref( { dt => dt_from_string, dateformat => 'iso' } ) );
            $params->{request}->status('COMP')->store;
        }
        $backend_result->{value}->{request} = $params->{request};

    } else {

        # in case of faulty or testing stage, we just return the standard $backend_result with original stage
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

=head3 cancel_unavailable

    $request->cancel_unavailable;

=cut

sub cancel_unavailable {
    my ( $self, $params ) = @_;

    my $stage = $params->{other}->{stage};
    my $template_params = {};

    my $backend_result = {
        backend => $self->name,
        method  => "cancel_unavailable",
        stage   => $stage,                 # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => $template_params,
        next    => "illview",
    };

    my $request = $params->{request};

    $backend_result->{illrequest_id}  = $request->illrequest_id;
    $template_params->{other}->{type} = $request->medium;
    $template_params->{request}       = $request;

    if ( !$stage ) {

        my $patron_preferences = C4::Members::Messaging::GetMessagingPreferences({
            borrowernumber => $request->borrowernumber,
            message_name   => 'Ill_unavailable',
        });

        if ( exists $patron_preferences->{transports}->{email} ) {
            $template_params->{notify} = 1;
        }

        $backend_result->{stage} = "init";

    } elsif ( $stage eq 'commit' ) {

        # delete biblio and item
        my $biblio = Koha::Biblios->find( $request->biblionumber );
        my $items  = $biblio->items;
        # delete the items using safe_delete
        while ( my $item = $items->next ) {
            $item->safe_delete;
        }
        # delete the biblio
        DelBiblio( $biblio->id );

        # mark as complete
        $request->set(
            {
                completed => \'NOW()',
                status    => 'COMP',
            }
        )->store;

        # send message
        if ( $params->{other}->{notify_patron} eq 'on' ) {
            my $letter = $request->get_notice(
                { notice_code => 'ILL_REQUEST_UNAVAIL', transport => 'email' }
            );
            my $result = C4::Letters::EnqueueLetter(
                {
                    letter                 => $letter,
                    borrowernumber         => $request->borrowernumber,
                    message_transport_type => 'email',
                }
            );
        }

    } else {

        # in case of faulty or testing stage, we just return the standard $backend_result with original stage
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

# deletes biblio and item data of the ILL item from the database, normally if illrequests.status is set to 'COMP'
sub delBiblioAndItem {
    my ( $biblionumber, $itemnumber ) = @_;
    my $holds = Koha::Holds->search( { itemnumber => $itemnumber } );
    if ($holds) {
        $holds->delete();
    }
    my $res = C4::Items::DelItemCheck( $biblionumber, $itemnumber );
    my $error;
    if ( $res eq '1' ) {
        $error = &DelBiblio($biblionumber);
    }
    if ( $res ne '1' || $error ) {
        warn "ERROR when deleting ILL title $biblionumber ($error) or ILL item $itemnumber ($res)";
        print
"Content-Type: text/html\n\n<html><body><h4>ERROR when deleting ILL title $biblionumber (error:$error) <br />or when deleting ILL item $itemnumber (res:$res)</h4></body></html>";
        exit;
    }
}

=head3 add_biblio

    my $biblionumber = $slnp_backend->add_biblio($params->{other});

Create a basic biblio record for the passed SLNP API request

=cut

sub add_biblio {
    my ( $self, $other ) = @_;

    return try {
        # We're going to try and populate author, title, etc.
        my $author = $other->{attributes}->{author};
        my $title  = $other->{attributes}->{title};
        my $isbn   = $other->{attributes}->{isbn};
        my $issn   = $other->{attributes}->{issn};

        my $configuration = $self->{configuration};

        # Create the MARC::Record object and populate it
        my $marcrecord = MARC::Record->new();
        $marcrecord->MARC::Record::encoding('UTF-8');

        if ( $isbn && length($isbn) > 0 ) {
            my $marc_isbn = MARC::Field->new( '020', ' ', ' ', 'a' => $isbn );
            $marcrecord->insert_fields_ordered($marc_isbn);
        }
        if ( $issn && length($issn) > 0 ) {
            my $marc_issn = MARC::Field->new( '022', ' ', ' ', 'a' => $issn );
            $marcrecord->insert_fields_ordered($marc_issn);
        }
        if ($author) {
            my $marc_author = MARC::Field->new( '100', '1', '', 'a' => $author );
            $marcrecord->insert_fields_ordered($marc_author);
        }
        my $marc_field245;
        if ( defined($title) && length($title) > 0 ) {
            my $prefix = $configuration->{title_prefix} // '';
            my $suffix = $configuration->{title_suffix} // '';
            $marc_field245 = MARC::Field->new( '245', '0', '0', 'a' => $prefix . $title . $suffix );
        }
        if ( defined($author) && length($author) > 0 ) {
            if ( !defined($marc_field245) ) {
                $marc_field245 = MARC::Field->new( '245', '0', '0', 'c' => $author );
            } else {
                $marc_field245->add_subfields( 'c' => $author );
            }
        }
        if ( defined($marc_field245) ) {
            $marcrecord->insert_fields_ordered($marc_field245);
        }

        # set opac display suppression flag of the record
        my $marc_field942 = MARC::Field->new( '942', '', '', n => '1' );
        $marcrecord->append_fields($marc_field942);

        my $biblionumber = C4::Biblio::AddBiblio( $marcrecord, $self->{framework} );

        return $biblionumber;
    }
    catch {
        SLNP::Exception->throw( "error_creating_biblio" );
    };
}

=head3 add_item

    my $item = $slnp_backend->add_item(
        {
            biblio_id       => $biblio->id,
            medium          => 'Book' / 'Article',
            library_id      => $library_id,
            callnumber      => $callnumber,
            notes           => $item_notes,
            notes_nonpublic => $item_notes_nonpublic,
        }
    );

Create a I<Koha::Item> object from the ill request data.

=cut

sub add_item {
    my ( $self, $params ) = @_;

    my @mandatory = (
        'biblio_id', 'medium', 'library_id', 'orderid'
    );
    for my $param (@mandatory) {
        unless ( defined( $params->{$param} ) ) {
            SLNP::Exception::MissingParameter->throw( param => $param );
        }
    }

    my $biblio  = Koha::Biblios->find( $params->{biblio_id} );
    my $request = $params->{request};

    unless ($biblio) {
        SLNP::Exception::UnknownBiblioId->throw(
            biblio_id => $params->{biblio_id} );
    }

    my $item_type = $self->get_item_type( $params->{medium} );
    # Barcode needs to be prefixed
    my $barcode = $self->{configuration}->{barcode_prefix} . $params->{orderid};

    return Koha::Item->new(
        {
            homebranch          => $params->{library_id},
            barcode             => $barcode,
            notforloan          => undef,
            itemcallnumber      => undef,
            itemnotes           => $params->{notes},
            itemnotes_nonpublic => $params->{notes_nonpublic},
            holdingbranch       => $params->{library_id},
            itype               => $item_type,
            biblionumber        => $biblio->biblionumber,
            biblioitemnumber    => $biblio->biblioitem->biblioitemnumber,
            stocknumber         => undef,
        }
    )->store;
}

# methods that are called by the Koha application via the ILL framework, but not exclusively by the framework

sub isShippingBackRequired {
    my ( $self, $request ) = @_;
    my $shippingBackRequired = 1;

    if ( $request->medium() eq 'copy' ) {
        $shippingBackRequired = 0;
    }
    return $shippingBackRequired;
}

# e.g. my $$illreqattr = $illrequest->_backend_capability( "getIllrequestattributes", [ $illrequest, ["", ""]] );
sub getIllrequestattributes {    # does work
    my ( $self, $args ) = @_;
    my $result;
    my ( $request, $interesting_fields ) = ( $args->[0], $args->[1] );

    my $fieldResults = $request->illrequestattributes->search( { type => { '-in' => $interesting_fields } } );
    my $illreqattr   = { map { ( $_->type => $_->value ) } ( $fieldResults->as_list ) };
    foreach my $type ( keys %{$illreqattr} ) {
        $result->{$type} = $illreqattr->{$type};
    }
    return $result;
}

sub getIllrequestDateDue {
    my ( $self, $request ) = @_;
    my $result;

    my $fieldResults = $request->illrequestattributes->search( { type => "duedate" } );
    my $illreqattr   = { map { ( $_->type => $_->value ) } ( $fieldResults->as_list ) };
    foreach my $type ( keys %{$illreqattr} ) {
        $result->{$type} = $illreqattr->{$type};
    }
    return $result->{duedate};
}

sub itemCheckedOut {
    my ( $self, $request ) = @_;
    $request->status('CHK')->store;
}

sub itemCheckedIn {
    my ( $self, $request ) = @_;
    $request->status('RET')->store;

    # if it is an article, then use this action to transfer the status to completed
    if ( $request->medium() eq 'copy' ) {
        my $params = {};
        $params->{request}        = $request;
        $params->{other}          = {};
        $params->{other}->{stage} = 'commit';
        $self->sendeZurueck($params);
    }
}

sub itemLost {
    my ( $self, $request ) = @_;
    if ( $request->status() eq 'REQ' ) {    # ILL receipt booking required before item can be set to lost
        my $illrequest_id = $request->illrequest_id();
        my $orderid       = $request->orderid();
        warn "ERROR when setting lost status of an ILL item. The receipt of the ILL request having order ID:$orderid has to be executed by you before this can be done.";
        print
"Content-Type: text/html\n\n<html><body><h4>ERROR when setting lost status of an ILL item. Please execute the receipt of the ILL request having order ID <a href=\"/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=$illrequest_id\" target=\"_blank\" >$orderid</a> prior to this item update.</h4></body></html>";
        exit;
    } elsif ( $request->status() eq 'RECVD' || $request->status() eq 'RECVDUPD' ) {
        $request->status('LOSTBCO')->store;    # item lost after receipt but before checkout
    } else {
        $request->status('LOSTACO')->store;    # item lost after checkout
    }
}

sub isReserveFeeAcceptable {
    my ( $self, $request ) = @_;
    my $ret = 0;                               # an additional hold fee is not acceptable for the SLNP backend (maybe configurable in the future)

    return $ret;
}

# function that defines for the backend the sequence of action buttons in the GUI
# e.g. my $sortActionIsImplemented = $illrequest->_backend_capability( "sortAction", ["", ""] );
# e.g. foreach my $actionId (sort { $illrequest->_backend_capability( "sortAction", [$a, $b] )} keys %available_actions_hash) { ...
sub sortAction {
    my ( $self, $statusId_A_B ) = @_;
    my $ret = 0;

    my $statusPrio = {
        'REQ'       => 1,
        'RECVD'     => 2,
        'RECVDUPD'  => 3,
        'CHK'       => 4,
        'RET'       => 5,
        'SNTBCK'    => 6,
        'NEGFLAG'   => 7,
        'CNCLDFU'   => 8,
        'LOSTHOWTO' => 9,
        'LOSTBCO'   => 10,
        'LOSTACO'   => 11,
        'LOST'      => 12,
        'COMP'      => 13,
    };

    if ( defined $statusId_A_B && defined $statusId_A_B->[0] && defined $statusId_A_B->[1] ) {

        # pseudo arguments '' for checking if this backend function is implemented
        if ( $statusId_A_B->[0] eq '' && $statusId_A_B->[1] eq '' ) {
            $ret = 1;
        } else {
            my $statusPrioA = defined $statusPrio->{ $statusId_A_B->[0] } ? $statusPrio->{ $statusId_A_B->[0] } : 0;
            my $statusPrioB = defined $statusPrio->{ $statusId_A_B->[1] } ? $statusPrio->{ $statusId_A_B->[1] } : 0;
            $ret = ( $statusPrioA == $statusPrioB ? 0 : ( $statusPrioA + 0 < $statusPrioB + 0 ? -1 : 1 ) );
        }
    }

    return $ret;
}

=head3 get_item_type

    my $item_type = $self->get_item_type( $medium );

Given the calculated I<illrequest.medium> value passed to the I<create> method,
this helper will return the right item type for the request, given the local
settings.

=cut

sub get_item_type {
    my ( $self, $medium ) = @_;

    SLNP::Exception::BadParameter->throw( param => 'medium', value => $medium )
      unless $medium eq 'copy' or $medium eq 'loan';

    my $item_type;
    my $item_types = $self->{configuration}->{item_types};

    if ($item_types) {

        # Use the configuration if possible
        $item_type =
          ( $medium eq 'copy' )
          ? $self->{configuration}->{item_types}->{copy} // 'CR'
          : $self->{configuration}->{item_types}->{loan} // 'BK';
    }
    else {
        # No configuration, default values
        $item_type = ( $medium eq 'copy' ) ? 'CR' : 'BK';
    }

    $self->{logger}->error("Configured item type for '$medium' is not valid: $item_type")
      unless Koha::ItemTypes->find($item_type);

    return $item_type;
}

=head3 get_fee

    my $fee = $self->get_fee({ patron => $patron });

Given a I<Koha::Patron> object, it returns the configured request fee.

=cut

sub get_fee {
    my ( $self, $args ) = @_;

    my $patron = $args->{patron};
    SLNP::Exception::BadParameter->throw( param => 'patron', value => $patron )
      unless $patron and ref($patron) eq 'Koha::Patron';

    my $configuration = $self->{configuration};

    my $default_fee = ( exists $configuration->{default_fee} )
      ? $configuration->{default_fee} // 0    # explicit undef means 'no charge'
      : 0;

    my $fee = ( exists $configuration->{category_fee} and exists $configuration->{category_fee}->{ $patron->categorycode } )
      ? $configuration->{category_fee}->{ $patron->categorycode } // 0    # explicit undef means 'no charge'
      : $default_fee;

    return $fee;
}

=head3 charge_ill_fee

    $self->charge_ill_fee({ patron => $patron });

Given a I<Koha::Patron> object, it charges the corresponding fee.

=cut

sub charge_ill_fee {
    my ( $self, $args ) = @_;

    my $patron = $args->{patron};
    SLNP::Exception::BadParameter->throw( param => 'patron', value => $patron )
      unless $patron and ref($patron) eq 'Koha::Patron';

    my $fee        = $self->get_fee( { patron => $patron } );
    my $debit_type = $self->{configuration}->{fee_debit_type} // 'ILL';

    if ( $fee > 0 ) {
        try {
            $patron->account->add_debit(
                {   amount    => $fee,
                    interface => 'intranet',
                    type      => $debit_type,
                  ( $args->{item_id} ? ( item_id => $args->{item_id} ) : () )
                }
            );
        }
        catch {
            if ( $_->isa('Koha::Exceptions::Account::UnrecognisedType') ) {
                SLNP::Exception::BadConfig->throw(
                    param => 'fee_debit_type',
                    value => $debit_type,
                );

                $_->rethrow;
            }

        };
    }

    return $fee;
}

=head3 get_item_from_request

    $self->get_item_from_request({ request => $request });

Given a I<Koha::Illrequest> object, retrieve the linked I<Koha::Item> object.

=cut

sub get_item_from_request {
    my ( $self, $args ) = @_;

    my $request = $args->{request};
    SLNP::Exception::BadParameter->throw( param => 'patron', value => $request )
      unless $request and ref($request) eq 'Koha::Illrequest';

    my $item_id_attributes = $request->illrequestattributes->search({ type => 'item_id' });

    SLNP::Exception::UnknownItemId->throw("Request not linked to an item when it should")
      unless $item_id_attributes->count > 0;

    my $item_id = $item_id_attributes->next->value;
    my $item = Koha::Items->find( $item_id );

    SLNP::Exception::UnknownItemId->throw("Request not linked to an item when it should")
      unless $item;

    return $item;
}

1;
