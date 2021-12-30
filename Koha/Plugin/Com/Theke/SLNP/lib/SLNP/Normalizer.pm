package SLNP::Normalizer;

# Copyright 2020 Theke Solutions
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

use SLNP::Exceptions;

=head1 SLNP::Normalizer

String normalizer class.

=head2 Synopsis

    use SLNP::Normalizer;

    my $normalizer = SLNP::Normalizer->new({ string => $THE_string });
    my $normalized_string = $normalizer
                              ->trim
                              ->ltrim
                              ->rtrim
                              ->remove_all_spaces
                              ->get_string;

=head2 Class methods

=head3 new

    my $normalizer = SLNP::Normalizer->new({ string => $string });

Constructor. Throws an I<SLNP::Exception::MissingParameter> exception if
the I<string> parameter is missing.

=cut

sub new {
    my ( $class, $args ) = @_;

    SLNP::Exception::MissingParameter->throw( param => 'string' )
      unless defined $args->{string};

    my $self = bless( { _original_string => $args->{string}, string => $args->{string} }, $class );

    return $self;
}

=head3 get_string

Retrieve the processed string.

=cut

sub get_string {
    my ($self) = @_;

    return $self->{string};
}

=head3 get_original_string

Retrieve the original string.

=cut

sub get_original_string {
    my ($self) = @_;

    return $self->{_original_string};
}

=head3 ltrim

Trim leading spaces

=cut

sub ltrim {
    my ($self) = @_;

    $self->{string} =~ s/^\s*//;

    return $self;
}

=head3 rtrim

Trim trailing spaces

=cut

sub rtrim {
    my ($self) = @_;

    $self->{string} =~ s/\s*$//;

    return $self;
}

=head3 trim

Trim leading and trailing spaces

=cut

sub trim {
    my ($self) = @_;

    $self->ltrim->rtrim;

    return $self;
}

=head3 remove_all_spaces

Remove all spaces.

=cut

sub remove_all_spaces {
    my ($self) = @_;

    $self->{string} =~ s/\s//g;

    return $self;
}

=head3 available_normalizers

Returns an arrayref of the valid normalizer names. To be used
to validate configuration.

=cut

sub available_normalizers {
    return [
        'ltrim',
        'rtrim',
        'trim',
        'remove_all_spaces',
    ];
}

1;
