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

use Koha::Database;
use Koha::Illrequests;
use Koha::Plugin::Com::Theke::SLNP;

use Scalar::Util qw(blessed);
use Try::Tiny;

use SLNP::Exceptions;

sub SLNPFLBestellung {
    my ( $cmd, $params ) = @_;

    my $configuration = Koha::Plugin::Com::Theke::SLNP->new->configuration;

    if ( $cmd->{'req_valid'} == 1 ) {

        my $illrequest      = Koha::Illrequest->new();
        my $slnp_illbackend = $illrequest->load_backend("SLNP");    # this is still $illrequest

        my $args = { stage => 'commit' };

        if (
            (
                defined $params->{AufsatzAutor}
                && length( $params->{AufsatzAutor} )
            )
            || ( defined $params->{AufsatzTitel}
                && length( $params->{AufsatzTitel} ) )
          )
        {
            # FIXME: We shouldn't use 'medium' https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=21833#c4
            $args->{medium} = 'copy';
        }
        else {
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
        my $default_pickup_location = $configuration->{default_ill_branch} // 'CPL';
        my $pickup_location_description = $args->{attributes}->{pickup_location_description};
        my $pickup_location = ( $pickup_location_description and $configuration->{pickup_location_mapping}->{$pickup_location_description} )
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
                        || !$backend_result->{value}->{request}->illrequest_id()
                      )
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
        }
        catch {
            $cmd->{'req_valid'} = 0;

            if ( blessed $_ ) { # An exception
                if ( $_->isa('SLNP::Exception::PatronNotFound') ) {
                    $cmd->{'err_type'} = 'PATRON_NOT_FOUND';
                    $cmd->{'err_text'} = "No patron found having cardnumber '"
                    . scalar $params->{BenutzerNummer} . "'.";
                }
                elsif ( $_->isa('SLNP::Exception::MissingParameter') ) {
                    $cmd->{err_type} = 'SLNP_MAND_PARAM_LACKING';
                    $cmd->{err_text} = 'Mandatory parameter missing: ' . $_->param;
                }
                elsif ( $_->isa('SLNP::Exception::BadConfig') ) {
                    $cmd->{err_type} = 'INTERNAL_SERVER_ERROR';
                    $cmd->{err_text} = 'Internal server error';
                    $cmd->{warn} =
                         'Configuration problem with mandatory parameter '
                        . $_->param
                        . ' (' . $_->value . ')';
                }
                elsif ( $_->isa('SLNP::Exception') ) {
                    $cmd->{err_type} = 'INTERNAL_SERVER_ERROR';
                    $cmd->{err_text} = 'Internal server error';
                    $cmd->{warn} = "Uncaught exception: $_";
                }
                else {
                    $cmd->{'err_type'} = 'ILLREQUEST_NOT_CREATED';
                    $cmd->{'err_text'} =
                        "The Koha illrequest for the title '"
                    . scalar $params->{Titel}
                    . "' could not be created. ($_)";
                }
            }
            else {
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
        Auflage        => 'issue', # copy case
        Heft           => 'issue', # loan case
    };
}

1;
