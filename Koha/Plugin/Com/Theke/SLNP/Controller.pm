package Koha::Plugin::Com::Theke::SLNP::Controller;

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

use utf8;

use Try::Tiny;

use CGI;
use Encode;

use Koha::Database;
use Koha::Plugin::Com::Theke::SLNP;

use Mojo::Base 'Mojolicious::Controller';

=head1 Koha::Plugin::Com::Theke::SLNP::Controller

A class implementing the controller methods for the SLNP plugin API

=head2 Class methods

=head3 get_print_slip

Given an ILL request id and a letter code, this method returns the HTML required to
generate a print slip for an ILL request.

=cut

sub get_print_slip {
    my $c = shift->openapi->valid_input or return;

    my $illrequest_id = $c->validation->param('illrequest_id');
    my $print_slip_id = $c->validation->param('print_slip_id');

    try {

        my $plugin = Koha::Plugin::Com::Theke::SLNP->new();

        $plugin->{cgi} = CGI->new; # required by C4::Auth::gettemplate and friends
        my $template = $plugin->get_template({ file => 'print_slip.tt' });

        my $req = Koha::Illrequests->find( $illrequest_id );

        unless ($req) {
            return $c->render(
                status  => 404,
                openapi => { error => 'Object not found' }
            );
        }

        my $illrequestattributes = {};
        my $attributes = $req->illrequestattributes;
        while ( my $attribute = $attributes->next ) {
            $illrequestattributes->{$attribute->type} = $attribute->value;
        }

        # Koha::Illrequest->get_notice with hardcoded letter_code
        my $title     = $req->illrequestattributes->find({ type => 'title' });
        my $author    = $req->illrequestattributes->find({ type => 'author' });
        my $metahash  = $req->metadata;
        my @metaarray = ();

        while (my($key, $value) = each %{$metahash}) {
            push @metaarray, "- $key: $value" if $value;
        }

        my $metastring = join("\n", @metaarray);

        my $item_id_attr = $req->illrequestattributes->find({ type => 'itemId' });
        my $item_id = ($item_id_attr) ? $item_id_attr->value : '';

        my $slip = C4::Letters::GetPreparedLetter(
            module                 => 'ill',
            letter_code            => $print_slip_id,
            branchcode             => $req->branchcode,
            message_transport_type => 'print',
            lang                   => $req->patron->lang,
            tables                 => {
                # illrequests => $req->illrequest_id, # FIXME: should be used in 20.11+
                borrowers   => $req->borrowernumber,
                biblio      => $req->biblio_id,
                item        => $item_id,
                branches    => $req->branchcode,
            },
            substitute  => {
                illrequestattributes => $illrequestattributes,
                illrequest           => $req->unblessed, # FIXME: should be removed in 20.11+
                ill_bib_title        => $title ? $title->value : '',
                ill_bib_author       => $author ? $author->value : '',
                ill_full_metadata    => $metastring
            }
        );
        # / Koha::Illrequest->get_notice

        $template->param(
            slip  => $slip->{content},
            title => $slip->{title},
        );

        return $c->render(
            status => 200,
            data   => Encode::encode('UTF-8', $template->output())
        );
    }
    catch {
        return $c->unhandled_slnp_exception($_);
    };
}

=head3 unhandled_slnp_exception

Helper method for rendering unhandled exceptions correctly

=cut

sub unhandled_slnp_exception {
    my ( $self, $exception ) = @_;

    warn "[slnp-api] Unhandled exception: $exception";

    return $self->render(
        status  => 500,
        openapi => {
            error => "Unhandled Koha exception: $exception"
        }
    );
}

1;
