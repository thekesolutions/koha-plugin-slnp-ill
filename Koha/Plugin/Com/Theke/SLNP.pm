package Koha::Plugin::Com::Theke::SLNP;

# Copyright 2021 Theke Solutions
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use Encode qw(decode_utf8);
use List::MoreUtils qw(any);
use Module::Metadata;
use Mojo::JSON qw(decode_json encode_json);
use Try::Tiny;
use YAML;

use C4::Circulation qw(AddReturn);

use Koha::Illrequests;
use Koha::Items;

BEGIN {
    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
    $path =~ s!\.pm$!/lib!;
    unshift @INC, $path;
}

our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'SLNP ILL connector plugin for Koha',
    author          => 'Theke Solutions',
    date_authored   => '2018-09-10',
    date_updated    => "1980-06-18",
    minimum_version => '20.1100000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'SLNP ILL connector plugin for Koha'
};

=head1 Koha::Plugin::Com::Theke::SLNP

SLNP ILL connector plugin for Koha

=head2 Plugin methods

=head3 new

Constructor:

    my $plugin = Koha::Plugin::Com::Theke::SLNP->new;

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 configure

Plugin configuration method

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'configure.tt' });

    unless ( scalar $cgi->param('save') ) {

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            configuration => $self->retrieve_data('configuration'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                configuration => scalar $cgi->param('configuration'),
            }
        );
        $template->param(
            configuration => $self->retrieve_data('configuration'),
        );
        $self->output_html( $template->output() );
    }
}

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

sub configuration {
    my ($self) = @_;

    my $configuration;
    eval { $configuration = YAML::Load( $self->retrieve_data('configuration') // '' . "\n\n" ); };
    die($@) if $@;

    return $configuration;
}

=head3 api_routes

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_namespace

Method that returns the namespace for the plugin API to be put on

=cut

sub api_namespace {
    my ( $self ) = @_;

    return 'slnp';
}

=head3 intranet_js

Method that returns JS to be injected to the staff interface.

=cut

sub intranet_js {
    my ( $self ) = @_;

    unless ( $self->{_intranet_js} ) {
        my $js = decode_utf8($self->mbf_read('intranet.js'));
        $self->{_intranet_js} =  '<script>' . $js . '</script>}';
    }

    return $self->{_intranet_js};
}

=head3 opac_js

Method that returns JS to be injected to the OPAC interface.

=cut

sub opac_js {
    my ( $self ) = @_;

    unless ( $self->{_opac_js} ) {
        my $js = decode_utf8($self->mbf_read('opac.js'));
        my $portal_url = $self->configuration->{portal_url} // 'https://your.portal.url';
        $js =~ s/\{\{portal_url\}\}/$portal_url/eg;
        $self->{_opac_js} =  '<script>' . $js . '</script>}';
    }

    return $self->{_opac_js};
}

=head3 after_circ_action

After circulation hook.

=cut

sub after_circ_action {
    my ($self, $params) = @_;

    if ( $params->{action} eq 'checkout' ) {
        my $checkout  = $params->{payload}->{checkout};

        my $biblio_id = $checkout->item->biblionumber;
        my $patron_id = $checkout->borrowernumber;

        my $req = $self->get_recvd_ill_req({ biblio_id => $biblio_id, patron_id => $patron_id });

        if ( $req ) { # Yay

            $req->status('CHK')->store; # TODO: Koha could do better
            my $type = $req->illrequestattributes->search({ type => 'type' })->next;
            my $THE_type = ($type) ? $type->value : 'Leihe';

            unless ( $THE_type eq 'Leihe' ) {
                # This is Kopie
                try {
                    my $item = $checkout->item;
                    AddReturn( $item->barcode );
                    $req->status('RET')->store; # TODO: Koha could do better
                    $req->status('COMP')->store; # TODO: Koha could do better
                    # cleanup
                    my $biblio = $item->biblio;
                    $biblio->items->delete;
                    $biblio->delete;
                }
                catch {
                    warn "Error attempting to return: $_";
                }
            }
        }
    }
}

=head2 Internal methods

=head3 get_recvd_ill_req

    my $req = $self->get_recvd_ill_req({ biblio_id => $biblio_id, patron_id => $patron_id });

Returns the related I<Koha::Illrequest> object if found.

=cut

sub get_recvd_ill_req {
    my ( $self, $params ) = @_;

    my $biblio_id = $params->{biblio_id};
    my $patron_id = $params->{patron_id};

    my $reqs = Koha::Illrequests->search(
        {   biblio_id      => $biblio_id,
            borrowernumber => $patron_id,
            status         => 'RECVD'
        }
    );

    if ( $reqs->count > 1 ) {
        warn "slnp_plugin_warn: more than one RECVD ILL request for biblio_id ($biblio_id) and patron_id ($patron_id) <.<";
    }

    return unless $reqs->count > 0;

    my $req = $reqs->next;

    return $req;
}

1;
