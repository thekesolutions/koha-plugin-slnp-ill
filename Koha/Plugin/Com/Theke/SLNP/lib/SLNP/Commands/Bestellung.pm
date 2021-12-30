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

use Try::Tiny;

use SLNP::Exceptions;

sub doSLNPFLBestellung {
    my $cmd = shift;
    my ($params) = @_;

    my $configuration = Koha::Plugin::Com::Theke::SLNP->new->configuration;

    if ( $cmd->{'req_valid'} == 1 ) {

        my $illrequest = Koha::Illrequest->new();
        my $slnp_illbackend = $illrequest->load_backend("SLNP");  # this is still $illrequest

        my $args;
        $args->{stage} = 'commit';

        # fields for table illrequests
        $args->{branchcode} = $configuration->{default_ill_branch} // 'CPL';
        if (
            (
                defined $params->{AufsatzAutor}
                && length( $params->{AufsatzAutor} )
            )
            || ( defined $params->{AufsatzTitel}
                && length( $params->{AufsatzTitel} ) )
          )
        {
            $args->{medium} = 'Article';
        }
        else {
            $args->{medium} = 'Book';
        }
        $args->{orderid} = $params->{BestellId};

        # fields for table illrequestattributes
        $args->{attributes} = {
            'zflorderid' => $params->{BestellId},
            'cardnumber' => $params->{BenutzerNummer}
            ,    # backend->create() will search for borrowers.borrowernumber
            'author'    => $params->{Verfasser},
            'title'     => $params->{Titel},
            'isbn'      => $params->{Isbn},
            'issn'      => $params->{Issn},
            'publisher' => $params->{Verlag},
            'publyear'  => $params->{EJahr},
            'issue'     => $params->{Auflage}, # FIXME: duplicate mapping, see sub attribute_mapping
            'shelfmark' => $params->{Signatur},
            'info'      => $params->{Info},
            'notes'     => $params->{Bemerkung}
        };

        my $attribute_mapping = attribute_mapping();
        foreach my $attribute ( keys %{$attribute_mapping} ) {
            if ( defined $params->{$attribute}
                && length( $params->{$attribute} ) )
            {
                $args->{attributes}->{ $attribute_mapping->{$attribute} } =
                  $params->{$attribute};
            }
        }

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
                        SLNP::Exception->throw();
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
            if ( $backend_result->{status} eq "invalid_borrower" ) {
                $cmd->{'err_type'} = 'PATRON_NOT_FOUND';
                $cmd->{'err_text'} = "No patron found having cardnumber '"
                  . scalar $params->{BenutzerNummer} . "'.";
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
        AufsatzAutor => 'article_author',
        AufsatzTitel => 'article_title',
        Heft         => 'issue', # FIXME: duplicate mapping
        Seitenangabe => 'article_pages',
        AusgabeOrt   => 'pickUpLocation',
    };
}

1;
