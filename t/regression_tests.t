#!/usr/bin/perl

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

use Test::More tests => 1;
use Test::MockModule;

use DDP;
use FindBin qw($Bin);
use lib     qw($Bin);

BEGIN {
    my $lib = "$Bin/..";

    unshift( @INC, $lib );
    unshift( @INC, "$lib/Koha/Plugin/Com/Theke/SLNP/lib" );
    unshift( @INC, '/kohadevbox/koha/t/lib/' );
}

use Koha::Database;

use Koha::SearchEngine::Search;
use Koha::SearchEngine::Elasticsearch::Search;

require SLNP::Commands::Bestellung;

use t::lib::TestBuilder;
use t::lib::Mocks;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'AFL test cases' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    my $item_type = $builder->build_object( { class => 'Koha::ItemTypes', value => { notforloan => 0 } } );
    my $item      = $builder->build_sample_item( { notforloan => -1, itype => $item_type->itemtype } );
    my $patron    = $builder->build_object( { class => 'Koha::Patrons' } );

    # for mocking config
    my $configuration = {
        lending => {
            control_borrowernumber   => $patron->id,
            denied_notforloan_values => [ 1, 2, 3 ],
            item_age                 => { check => 0 },
        }
    };

    # for mocking results
    my $count;
    my $err;
    my $search_result;
    my $biblionumber;
    my $too_many;

    # mock we have an ES server
    t::lib::Mocks::mock_preference( 'SearchEngine', 'Elasticsearch' );
    t::lib::Mocks::mock_config( 'elasticsearch', { server => 'a_server', index_name => 'some' } );

    my $mock_plugin = Test::MockModule->new('Koha::Plugin::Com::Theke::SLNP');
    $mock_plugin->mock( 'configuration', sub { return $configuration; } );

    my $search_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Search');
    $search_mock->mock( 'simple_search_compat', sub { return ( $err, $search_result, $count ); } );
    $search_mock->mock( 'extract_biblionumber', sub { return $biblionumber; } );

    my $circ_mock = Test::MockModule->new('C4::Circulation');
    $circ_mock->mock( 'TooMany', sub { return $too_many; } );

    $count        = 1;
    $biblionumber = $item->biblionumber;

    my $result = SLNP::Commands::Bestellung::SLNPFLBestellung(
        { req_valid => 1 },                             # $cmd
        { BsTyp     => 'AFL', TitelId => '123456' },    # $params
    );

    is_deeply(
        $result,
        {
            req_valid => 1,
            rsp_para  => [
                { resp_pnam => 'PFLNummer', resp_pval => undef },
                {
                    resp_pnam => 'OKMsg',
                    resp_pval => 'Bestellung wird bearbeitet',
                }
            ]
        },
        'Request is successfull'
    );

    $configuration->{lending}->{denied_notforloan_values} = [ -1, 1, 2, 3 ];

    $result = SLNP::Commands::Bestellung::SLNPFLBestellung(
        { req_valid => 1 },                             # $cmd
        { BsTyp     => 'AFL', TitelId => '123456' },    # $params
    );

    is_deeply(
        $result,
        {
            req_valid => 0,
            err_type  => 'NO_AVAILABLE_ITEMS',
            err_text  => 'Es existieren keine bestellbaren Exemplare',
        },
        'Request denied (itype in deny-list)'
    );

    $item_type->notforloan(1)->store();

    $configuration->{lending}->{denied_notforloan_values} = [ 1, 2, 3 ];

    $result = SLNP::Commands::Bestellung::SLNPFLBestellung(
        { req_valid => 1 },                             # $cmd
        { BsTyp     => 'AFL', TitelId => '123456' },    # $params
    );

    is_deeply(
        $result,
        {
            req_valid => 0,
            err_type  => 'NO_AVAILABLE_ITEMS',
            err_text  => 'Es existieren keine bestellbaren Exemplare',
        },
        'Request denied (itype marked as NFL)'
    );

    $item_type->notforloan(undef)->store();
    $configuration->{lending}->{control_borrowernumber} = undef;

    $result = SLNP::Commands::Bestellung::SLNPFLBestellung(
        { req_valid => 1 },                             # $cmd
        { BsTyp     => 'AFL', TitelId => '123456' },    # $params
    );

    is_deeply(
        $result,
        {
            req_valid => 0,
            err_type  => 'INTERNAL_SERVER_ERROR',
            err_text  => 'Internal server error',
            warn      => "Configuration missing mandatory configuration entry 'control_borrowernumber'",
        },
        'Error on bad control_borrowernumber'
    );

    $configuration->{lending}->{control_borrowernumber} = $patron->id;
    $too_many = 1;

    $result = SLNP::Commands::Bestellung::SLNPFLBestellung(
        { req_valid => 1 },                             # $cmd
        { BsTyp     => 'AFL', TitelId => '123456' },    # $params
    );

    is_deeply(
        $result,
        {
            req_valid => 0,
            err_type  => 'NO_AVAILABLE_ITEMS',
            err_text  => 'Es existieren keine bestellbaren Exemplare',
        },
        'TooMany() blocks lending'
    );

    $schema->storage->txn_rollback;
};