#!/usr/bin/env perl

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

use Koha::Plugin::Com::Theke::SLNP;
use SLNP::Server;

my $plugin = Koha::Plugin::Com::Theke::SLNP->new;
my $configuration = $plugin->configuration;

my $port = $configuration->{server}->{port} // 9001;
my $ipv  = $configuration->{server}->{ipv}  // '*';
my $host = $configuration->{server}->{host} // '127.0.0.1';

my $instance  = $ARGV[0] // 'kohadev';
my $user      = "$instance-koha";
my $group     = "$instance-koha";
my $log_file  = "/var/log/koha/$instance/slnp-server.log";
my $log_level = $configuration->{server}->{log_level} // 3;
my $pid_file  = "/var/run/koha/$instance/slnp-server.pid";

SLNP::Server->run(
    port      => $port,
    ipv       => $ipv,
    host      => $host,
    user      => $user,
    group     => $group,
    log_file  => $log_file,
    log_level => $log_level,
    pid_file  => $pid_file,
);

1;
