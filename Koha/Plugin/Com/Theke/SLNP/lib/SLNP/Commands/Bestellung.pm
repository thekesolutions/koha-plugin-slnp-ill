package SLNP::Commands::Bestellung;

# Copyright 2018-2019 (C) LMSCLoud GmbH
#           2021 Theke Solutions
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use utf8;

use C4::Context;

use C4::Circulation;
use C4::Reserves;

use Koha::Database;

use Koha::Biblios;
use Koha::DateUtils qw(dt_from_string);
use Koha::Illrequests;
use Koha::Plugin::Com::Theke::SLNP;
use Koha::SearchEngine::Search;

use List::MoreUtils qw(any uniq);
use Scalar::Util    qw(blessed);
use Try::Tiny;

use SLNP::Exceptions;

=head1 NAME

SLNP::Commands::Bestellung - Class for handling Bestellung (AFL/PFL) commands

=head1 API

=head2 Methods

=cut

=head3 SLNPFLBestellung

Main command to be run from the server.

=cut

sub SLNPFLBestellung {
    my ( $cmd, $params ) = @_;

    my $configuration = Koha::Plugin::Com::Theke::SLNP->new->configuration;

    if ( $cmd->{'req_valid'} == 1 ) {

        if ( $params->{BsTyp} eq 'AFL' ) {

            # 2.1 Check PPN number (TitelId)
            if ( $params->{TitelId} ) {

                return request_accepted( $cmd, $params->{ExternReferenz} )
                    if $params->{TitelId} eq '999999999' && defined $params->{BsTyp2} && $params->{BsTyp2} eq 'F';

                # Local title => checks and handling
                my $searcher = Koha::SearchEngine::Search->new( { index => $Koha::SearchEngine::BIBLIOS_INDEX } );
                my ( $err, $result, $count ) =
                    $searcher->simple_search_compat( 'Control-number:' . $params->{TitelId}, 0, 1 );

                if ($count) {    # We have the record, next checks
                                 # 2.2  Check if is a copy
                    if ( defined $params->{BsTyp2} && $params->{BsTyp2} eq 'C' ) {    # Is a copy => accept request
                                                                                      # FIXME: What about 'V'
                        request_accepted( $cmd, $params->{ExternReferenz} );
                    } else {

                        # pick the first record in the resultset
                        my $record    = $result->[0];
                        my $biblio_id = $searcher->extract_biblionumber($record);

                        my $biblio = Koha::Biblios->find($biblio_id);
                        my $items  = $biblio->items;

                        # 2.3 Does the record have items?
                        if ( $items->count > 0 ) {                                    # There are items, next checks

                            # 2.4 Are all items unavailable for ILL?
                            my $denied_notforloan_values = $configuration->{lending}->{denied_notforloan_values};

                            my $query = {
                                -or => [
                                    (
                                        $denied_notforloan_values
                                        ? { notforloan => { -in => $denied_notforloan_values } }
                                        : ()
                                    ),
                                    { itemlost  => { ">" => 0 } },    # is lost
                                    { withdrawn => { ">" => 0 } },    # is withdrawn
                                    {
                                        -and => [
                                            { restricted => { "!=" => undef } },
                                            { restricted => 1 }
                                        ]
                                    },                                # is restricted
                                ]
                            };

                            my $filtered_items = $items->search( { '-not' => $query } );

                            # 2.5 Are items new acquisitions?
                            if ( exists $configuration->{lending}->{item_age}->{check}
                                && $configuration->{lending}->{item_age}->{check} eq 'true' )
                            {
                                my $min_days_age = $configuration->{lending}->{item_age}->{days} // 0;
                                my $dtf          = Koha::Database->new->schema->storage->datetime_parser;
                                $filtered_items = $filtered_items->search(
                                    {
                                        dateaccessioned => {
                                            "<=" =>
                                                $dtf->format_date( dt_from_string->subtract( days => $min_days_age ) )
                                        }
                                    }
                                );
                            }

                            if ( $filtered_items->count > 0 ) {    # Candidate items, next checks
                                if ( $configuration->{lending}->{control_borrowernumber} ) {
                                    my $control_patron =
                                        Koha::Patrons->find( $configuration->{lending}->{control_borrowernumber} );

                                    if ($control_patron) {

                                        # 2.6 Can any item be checked out to the ILL library?
                                        my @loanable_items;

                                        while ( my $item = $filtered_items->next ) {

                                            # is itype notforloan?
                                            my $itype = $item->itemtype;
                                            my $too_many;

                                            if ( C4::Context->preference('Version') ge '23.110000' ) {
                                                $too_many = C4::Circulation::TooMany( $control_patron, $item );
                                            }
                                            else {
                                                $too_many = C4::Circulation::TooMany( $control_patron->unblessed, $item );
                                            }

                                            unless (
                                                $too_many
                                                || $itype    # this makes itype mandatory to be defined
                                                && $itype->notforloan
                                                )
                                            {
                                                push @loanable_items, $item;
                                            }
                                        }

                                        # 2.7 Are all loanable items checked out?
                                        if (@loanable_items) {
                                            if ( any { !defined $_->onloan } @loanable_items ) {
                                                request_accepted( $cmd, $params->{ExternReferenz} );
                                            } else {

                                                # 2.8 Does the library allow hold requests?
                                                if ( exists $configuration->{lending}->{accepts_hold_requests}
                                                    && $configuration->{lending}->{accepts_hold_requests} eq 'true' )
                                                {
                                                    my $reservable_item;
                                                    foreach my $item (@loanable_items) {

                                                        my $status = C4::Reserves::CanItemBeReserved(
                                                            $control_patron, $item,
                                                            $control_patron->branchcode
                                                        );

                                                        # use Data::Printer colored => 1;
                                                        # p($status);

                                                        if ( $status->{status} eq 'OK' ) {
                                                            $reservable_item = 1;
                                                            last;
                                                        }
                                                    }

                                                    if ($reservable_item) {
                                                        request_rejected(
                                                            $cmd, 'NO_AVAILABLE_ITEMS',
                                                            "Exemplar ausgeliehen, Vormerkung ist möglich"
                                                        );
                                                    } else {
                                                        request_rejected(
                                                            $cmd, 'NO_AVAILABLE_ITEMS',
                                                            "Es existieren keine bestellbaren Exemplare"
                                                        );
                                                    }
                                                } else {
                                                    request_rejected(
                                                        $cmd, 'NO_AVAILABLE_ITEMS',
                                                        "Es existieren keine bestellbaren Exemplare"
                                                    );
                                                }
                                            }
                                        } else {

                                            # no items left, deny
                                            request_rejected(
                                                $cmd, 'NO_AVAILABLE_ITEMS',
                                                "Es existieren keine bestellbaren Exemplare"
                                            );
                                        }
                                    } else {
                                        request_rejected(
                                            $cmd, 'INTERNAL_SERVER_ERROR',
                                            "Internal server error",
                                            "Configuration invalid value for configuration entry 'control_borrowernumber' ("
                                                . $configuration->{lending}->{control_borrowernumber} . ")"
                                        );
                                    }
                                } else {    # bad configuration
                                    request_rejected(
                                        $cmd, 'INTERNAL_SERVER_ERROR',
                                        "Internal server error",
                                        "Configuration missing mandatory configuration entry 'control_borrowernumber'"
                                    );
                                }
                            } else {    # no items left, deny
                                request_rejected(
                                    $cmd, 'NO_AVAILABLE_ITEMS',
                                    "Es existieren keine bestellbaren Exemplare"
                                );
                            }
                        } else {    # no items, deny
                            request_rejected(
                                $cmd, 'NO_AVAILABLE_ITEMS',
                                "Es existieren keine bestellbaren Exemplare"
                            );
                        }
                    }

                    # FIXME: we need to be able to determine if it comes from the union catalog
                } else {
                    request_rejected( $cmd, 'RECORD_NOT_FOUND', "Es existieren keine Exemplare" );
                }
            } else {    # No PPN number => accept request. Processing takes place on the portal
                request_accepted( $cmd, $params->{ExternReferenz} );
            }
        } else {

            my $illrequest      = Koha::Illrequest->new();
            my $slnp_illbackend = $illrequest->load_backend("SLNP");    # this is still $illrequest

            my $args = { stage => 'commit' };

            if (
                ( defined $params->{AufsatzAutor} && length( $params->{AufsatzAutor} ) )
                || ( defined $params->{AufsatzTitel}
                    && length( $params->{AufsatzTitel} ) )
                )
            {
                # FIXME: We shouldn't use 'medium' https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=21833#c4
                $args->{medium} = 'copy';
            } else {

                # FIXME: We shouldn't use 'medium' https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=21833#c4
                $args->{medium} = 'loan';
            }
            $args->{orderid} = $params->{BestellId};

            # fields for table illrequestattributes
            my $attribute_mapping = attribute_mapping();
            foreach my $attribute ( keys %{$attribute_mapping} ) {
                if ( defined $params->{$attribute}
                    && length( $params->{$attribute} ) )
                {
                    $args->{attributes}->{ $attribute_mapping->{$attribute} } =
                        $params->{$attribute};
                }
            }

            $args->{attributes}->{type} = ( $args->{medium} eq 'copy' ) ? 'Kopie' : 'Leihe';

            # Deal with AusgabeOrt => pickup_location translation
            my $default_pickup_location     = $configuration->{default_ill_branch} // 'CPL';
            my $pickup_location_description = $args->{attributes}->{pickup_location_description};
            my $pickup_location =
                (       $pickup_location_description
                    and $configuration->{pickup_location_mapping}->{$pickup_location_description} )
                ? $configuration->{pickup_location_mapping}->{$pickup_location_description}
                : $default_pickup_location;

            # fields for table illrequests
            $args->{branchcode} = $pickup_location;
            $args->{attributes}->{pickup_location} = $pickup_location;

            my $backend_result;

            try {
                Koha::Database->new->schema->txn_do(
                    sub {
                        $backend_result = $slnp_illbackend->backend_create($args);

                        if (   $backend_result->{error} ne '0'
                            || !defined $backend_result->{value}
                            || !defined $backend_result->{value}->{request}
                            || !$backend_result->{value}->{request}->illrequest_id() )
                        {
                            # short-circuit, force rollback
                            SLNP::Exception->throw("Error creating the illrequest object");
                        }

                        my $prefix = $configuration->{pfl_number_prefix} // '';

                        $cmd->{'rsp_para'}->[0] = {
                            'resp_pnam' => 'PFLNummer',
                            'resp_pval' => $prefix . $backend_result->{value}->{request}->illrequest_id()
                        };

                        $cmd->{'rsp_para'}->[1] = {
                            'resp_pnam' => 'OKMsg',
                            'resp_pval' => 'ILL request successfully inserted.'
                        };
                    }
                );
            } catch {
                $cmd->{'req_valid'} = 0;

                if ( blessed $_ ) {    # An exception
                    if ( $_->isa('SLNP::Exception::PatronNotFound') ) {
                        $cmd->{'err_type'} = 'PATRON_NOT_FOUND';
                        $cmd->{'err_text'} =
                            "No patron found having cardnumber '" . scalar $params->{BenutzerNummer} . "'.";
                    } elsif ( $_->isa('SLNP::Exception::MissingParameter') ) {
                        $cmd->{err_type} = 'SLNP_MAND_PARAM_LACKING';
                        $cmd->{err_text} = 'Mandatory parameter missing: ' . $_->param;
                    } elsif ( $_->isa('SLNP::Exception::BadConfig') ) {
                        $cmd->{err_type} = 'INTERNAL_SERVER_ERROR';
                        $cmd->{err_text} = 'Internal server error';
                        $cmd->{warn} =
                            'Configuration problem with mandatory parameter ' . $_->param . ' (' . $_->value . ')';
                    } elsif ( $_->isa('SLNP::Exception') ) {
                        $cmd->{err_type} = 'INTERNAL_SERVER_ERROR';
                        $cmd->{err_text} = 'Internal server error';
                        $cmd->{warn}     = "Uncaught exception: $_";
                    } else {
                        $cmd->{'err_type'} = 'ILLREQUEST_NOT_CREATED';
                        $cmd->{'err_text'} =
                              "The Koha illrequest for the title '"
                            . scalar $params->{Titel}
                            . "' could not be created. ($_)";
                    }
                } else {
                    $cmd->{'err_type'} = 'ILLREQUEST_NOT_CREATED';
                    $cmd->{'err_text'} =
                          "The Koha illrequest for the title '"
                        . scalar $params->{Titel}
                        . "' could not be created. ("
                        . scalar $backend_result->{status} . ' '
                        . scalar $backend_result->{message} . ")";
                }
            };
        }
    }

    return $cmd;
}

=head3 attribute_mapping

Simple SLNP -> Koha ILL request attribute mapping.

=cut

sub attribute_mapping {
    return {
        AufsatzAutor   => 'article_author',
        AufsatzTitel   => 'article_title',
        AusgabeOrt     => 'pickup_location_description',
        Band           => 'volume',
        Bemerkung      => 'notes',
        BenutzerNummer => 'cardnumber',
        BestellId      => 'zflorderid',
        EJahr          => 'year',
        Info           => 'info',
        Isbn           => 'isbn',
        Issn           => 'issn',
        Seitenangabe   => 'pages',
        Signatur       => 'shelfmark',
        Titel          => 'title',
        Verfasser      => 'author',
        Verlag         => 'publisher',
        Auflage        => 'issue',                         # copy case
        Heft           => 'issue',                         # loan case
    };
}

=head3 request_accepted

    request_accepted( $cmd, $pflnummer );

Helper method that makes I<$cmd> carry the right information for a successful request.

=cut

sub request_accepted {
    my ( $cmd, $pflnummer ) = @_;

    $cmd->{rsp_para}->[0] = {
        resp_pnam => 'PFLNummer',
        resp_pval => $pflnummer,
    };

    $cmd->{rsp_para}->[1] = {
        resp_pnam => 'OKMsg',
        resp_pval => 'Bestellung wird bearbeitet',
    };

    return $cmd;
}

=head3 request_rejected

    request_rejected( $cmd, $type, $text );

Helper method that makes I<$cmd> carry the right information for a rejected request.

=cut

sub request_rejected {
    my ( $cmd, $type, $text, $warn ) = @_;

    $cmd->{req_valid} = 0;
    $cmd->{err_type}  = $type;
    $cmd->{err_text}  = $text;

    $cmd->{warn} = $warn
        if $warn;

    return $cmd;
}

1;
