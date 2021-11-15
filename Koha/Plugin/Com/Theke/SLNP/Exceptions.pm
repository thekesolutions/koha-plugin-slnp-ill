package Koha::Plugin::Com::Theke::SLNP::Exceptions;

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

use Exception::Class (
  'SLNP::Ill',
  'SLNP::Ill::InconsistentStatus'   => { isa => 'SLNP::Ill', fields => ['expected_status'] },
  'SLNP::Ill::MissingParameter'     => { isa => 'SLNP::Ill', fields => ['param'] },
  'SLNP::Ill::UnknownItemId'        => { isa => 'SLNP::Ill', fields => ['item_id'] },
  'SLNP::Ill::UnknownBiblioId'      => { isa => 'SLNP::Ill', fields => ['biblio_id'] }
);

1;

