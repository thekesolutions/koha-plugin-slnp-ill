#!/bin/bash

# slnp-server - Manage the SLNP server
#
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

set -e

. /lib/lsb/init-functions

# Read configuration variable file if it is present
[ -r /etc/default/koha-common ] && . /etc/default/koha-common

# include helper functions
if [ -f "/usr/share/koha/bin/koha-functions.sh" ]; then
    . "/usr/share/koha/bin/koha-functions.sh"
else
    echo "Error: /usr/share/koha/bin/koha-functions.sh not present." 1>&2
    exit 1
fi

usage()
{
    local scriptname=$(basename $0)

    cat <<EOF
$scriptname

This script lets you manage the SLNP server for your Koha instance.

Usage:
$scriptname [--start|--stop|--restart] instance
$scriptname -h|--help

    --start               Start the SLNP server for the specified instance
    --stop                Stop the SLNP server for the specified instance
    --restart             Restart the SLNP server for the specified instance
    --status              Show the status of the SLNP server for the specified instance
    --verbose|-v          Display progress and actions messages
    --help|-h             Display this help message

EOF
}

is_slnp_running()
{
    local name=$1

    if daemon --name="${name}-koha-slnp-server" \
            --pidfiles="/var/run/koha/$name/" \
            --user="$name-koha.$name-koha" \
            --running ; then
        return 0
    else
        return 1
    fi
}

start_slnp()
{
    local name=$1

    if ! is_slnp_running $name; then

        _check_and_fix_perms ${name}

        DAEMONOPTS="--name=${name}-koha-slnp-server \
                    --pidfiles=/var/run/koha/${name}/ \
                    --errlog=/var/log/koha/${name}/slnp-server-error.log \
                    --output=/var/log/koha/${name}/slnp-server-output.log \
                    --verbose=1 \
                    --respawn \
                    --delay=30 \
                    --user=${name}-koha.${name}-koha"

        [ "$verbose" != "no" ] && \
            log_daemon_msg "Starting SLNP server for ${name}"

        if daemon $DAEMONOPTS -- "${PLUGIN_BASE_PATH}/${SLNP_DAEMON}" ${name}; then
            ([ "$verbose" != "no" ] && \
                log_end_msg 0) || return 0
        else
            ([ "$verbose" != "no" ] && \
                log_end_msg 1) || return 1
        fi
    else
        if [ "$verbose" != "no" ]; then
            log_daemon_msg "Error: SLNP server already running for ${name}"
            log_end_msg 1
        else
            return 1
        fi
    fi
}

stop_slnp()
{
    local name=$1

    if is_slnp_running $name; then

        DAEMONOPTS="--name=${name}-koha-slnp-server \
                    --pidfiles=/var/run/koha/${name}/ \
                    --errlog=/var/log/koha/${name}/slnp-server-error.log \
                    --output=/var/log/koha/${name}/slnp-server-output.log \
                    --verbose=1 \
                    --respawn \
                    --delay=30 \
                    --user=${name}-koha.${name}-koha"

        [ "$verbose" != "no" ] && \
            log_daemon_msg "Stopping SLNP server for ${name}"

        if daemon $DAEMONOPTS --stop -- "${PLUGIN_BASE_PATH}/${SLNP_DAEMON}" ${name}; then
            ([ "$verbose" != "no" ] && \
                log_end_msg 0) || return 0
        else
            ([ "$verbose" != "no" ] && \
                log_end_msg 1) || return 1
        fi
    else
        if [ "$verbose" != "no" ]; then
            log_daemon_msg "Error: SLNP server not running for ${name}"
            log_end_msg 1
        else
            return 1
        fi
    fi
}

restart_slnp()
{
    local name=$1

    if is_slnp_running ${name}; then
        local noLF="-n"
        [ "$verbose" != "no" ] && noLF=""
        echo $noLF `stop_slnp ${name}`
        echo $noLF `start_slnp ${name}`
    else
        if [ "$verbose" != "no" ]; then
            log_daemon_msg "Error: SLNP server not running for ${name}"
            log_end_msg 1
        else
            return 1
        fi
    fi
}

slnp_status()
{
    local name=$1

    if is_slnp_running ${name}; then
        log_daemon_msg "SLNP server running for ${name}"
        log_end_msg 0
    else
        log_daemon_msg "SLNP server not running for ${name}"
        log_end_msg 3
    fi
}

_check_and_fix_perms()
{
    local name=$1

    local files="/var/log/koha/${name}/slnp-server-output.log \
                 /var/log/koha/${name}/slnp-server-error.log"

    for file in ${files}
    do
        if [ ! -e "${file}" ]; then
            touch ${file}
        fi
        chown "${name}-koha":"${name}-koha" ${file}
    done
}

set_action()
{
    if [ "$op" = "" ]; then
        op=$1
    else
        die "Error: only one action can be specified."
    fi
}

op=""
verbose="no"

export PLUGIN_BUNDLE_PATH="Koha/Plugin/Com/Theke/SLNP"
export SLNP_DAEMON="${PLUGIN_BUNDLE_PATH}/scripts/slnp-server.pl"

# Read command line parameters
while [ $# -gt 0 ]; do

    case "$1" in
        -h|--help)
            usage ; exit 0 ;;
        -v|--verbose)
            verbose="yes"
            shift ;;
        --start)
            set_action "start"
            shift ;;
        --stop)
            set_action "stop"
            shift ;;
        --restart)
            set_action "restart"
            shift ;;
        --status)
            set_action "status"
            shift ;;
        -*)
            die "Error: invalid option switch ($1)" ;;
        *)
            # We expect the remaining stuff are the instance names
            break ;;
    esac

done

if [ $# -gt 0 ]; then
    # We have at least one instance name
    for name in "$@"; do

        if is_instance $name; then

            if [ "$PLUGIN_BASE_PATH" == "" ]; then
                PLUGIN_BASE_PATH="/var/lib/koha/${name}/plugins"
            fi

            # Make sure everything we need is on PERL5LIB
            export PERL5LIB=${PLUGIN_BASE_PATH}:${PLUGIN_BASE_PATH}/${PLUGIN_BUNDLE_PATH}/lib:$PERL5LIB

            case $op in
                "start")
                    start_slnp $name
                    ;;
                "stop")
                    stop_slnp $name
                    ;;
                "restart")
                    restart_slnp $name
                    ;;
                "status")
                    slnp_status $name
            esac

        else
            if [ "$verbose" != "no" ]; then
                log_daemon_msg "Error: Invalid instance name $name"
                log_end_msg 1
            fi
        fi

    done
else
    if [ "$verbose" != "no" ]; then
        warn "Error: you must provide at least one instance name"
    fi
fi

exit 0
