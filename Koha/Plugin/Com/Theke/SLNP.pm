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

use List::MoreUtils qw(any);
use Module::Metadata;
use Mojo::JSON qw(decode_json encode_json);
use YAML;

use Koha::Biblioitems;
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

sub intranet_head {
    my ( $self ) = @_;

    return q{
        <script>
            $(document).ready(function(){
               $('#ill-toolbar-btn-edit-action').hide();
            });
        </script>
    };
}

1;

