#!/bin/bash

# log <INFO|WARN|ERROR> <message>: same format and UOS_LOG_* switches as uos-console-journal.py
log() {
    local level=$1 line="" color=32 tag="$1 "
    shift
    [ ${#level} -eq 4 ] && tag=" $level "
    [ "$level" = WARN ] && color=33
    [ "$level" = ERROR ] && color=31
    [[ ${UOS_LOG_TIMESTAMP,,} =~ ^(false|0|no|off)$ ]] || line+="$(date +%Y-%m-%dT%H:%M:%S) "
    if [[ ${UOS_LOG_COLOR,,} =~ ^(false|0|no|off)$ ]]; then
        line+="[$tag]"
    else
        line+=$(printf '[\e[%sm%s\e[0m]' "$color" "$tag")
    fi
    [[ ${UOS_LOG_SOURCE,,} =~ ^(false|0|no|off)$ ]] || line+=" entrypoint:"
    echo "$line $*"
}

# Persist UOS_UUID env var
if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID+1}" ]; then
        log INFO "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    else
        log INFO "No UOS_UUID present, generating..."
        UUID=$(cat /proc/sys/kernel/random/uuid)

        # Spoof a v5 UUID
        UOS_UUID=$(echo $UUID | sed s/./5/15)
        log INFO "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    fi
fi

ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" == "amd64" ]; then
    FIRMWARE_PLATFORM=linux-x64
elif [ "$ARCH" == "arm64" ]; then
    FIRMWARE_PLATFORM=arm64
else
    log ERROR "FIRMWARE_PLATFORM not found for $ARCH"
    exit 1
fi

log INFO "Setting FIRMWARE_PLATFORM to $FIRMWARE_PLATFORM"
log INFO "Setting PRODUCT_NAME to $PRODUCT_NAME"
log INFO "Setting APP_MODEL to $APP_MODEL"
log INFO "Setting APP_VERSION to $APP_VERSION"

# Read version from package.json and write version string
echo "$FIRMWARE_PLATFORM" > /usr/lib/platform
echo "$PRODUCT_NAME" > /usr/lib/product_name
echo "$APP_MODEL" > /usr/lib/app_model
# Protect Server is mounting /usr/lib/version
if [ "$APP_MODEL" != "PROTECT_SERVER" ]; then
    echo "$APP_MODEL.0000000.$APP_VERSION.0000000.000000.0000" > /usr/lib/version
fi

# Create eth0 alias to tap0 (requires NET_ADMIN cap & macvlan kernel module loaded on host)
if [ ! -d "/sys/devices/virtual/net/eth0" ] && [ -d "/sys/devices/virtual/net/tap0" ]; then
    ip link add name eth0 link tap0 type macvlan
    ip link set eth0 up
fi

# /var/log is a volume: make sure the per-service log dirs exist with the right owner
install -d -o nginx -g nginx /var/log/nginx
install -d -o mongodb -g mongodb /var/log/mongodb
[ "$APP_MODEL" == "UOSSERVER" ] && install -d -o rabbitmq -g rabbitmq /var/log/rabbitmq

# Volume contents are often created or restored with the wrong owner (host user, podman
# migration, see upstream issue lemker/unifi-os-server#53) and the services then fail to start.
# fix_owner <dir> <user:group>: chown only the entries under <dir> that are not <user:group>.
fix_owner() {
    [ -d "$1" ] || return 0
    local n
    n=$(find "$1" ! \( -user "${2%:*}" -group "${2#*:}" \) -exec chown -h "$2" {} + -print | wc -l)
    [ "$n" -gt 0 ] && log WARN "Fixed ownership of $n entries under $1 -> $2"
}
fix_owner /var/lib/mongodb mongodb:mongodb
fix_owner /var/log/mongodb mongodb:mongodb
fix_owner /var/log/rabbitmq rabbitmq:rabbitmq
fix_owner /data/postgresql postgres:postgres
fix_owner /data/uid uid:uid
fix_owner /srv/uid uid:uid
fix_owner /data/ulp-go ulp-go:ulp-go
fix_owner /srv/ulp-go ulp-go:ulp-go
fix_owner /data/ucs-agent ucs-agent:ucs-agent
fix_owner /data/ucs-user-assets unifi-credential-server:unifi-credential-server
fix_owner /data/unifi-directory unifi-directory:unifi-directory
fix_owner /data/unifi-identity-update ucs-update:ucs-update
fix_owner /var/log/unifi_package-identity-update ucs-update:ucs-update

# PostgreSQL refuses to start unless its data dir is 0700
for d in /data/postgresql/*/*/data; do
    if [ -d "$d" ] && [ "$(stat -c %a "$d")" != 700 ]; then
        chmod 700 "$d" && log WARN "Fixed mode of $d -> 700"
    fi
done

# Creating alias for mongodb service so that Network 10.6.77 and up doesn't fail
if [[ "$APP_MODEL" == "UOSSERVER" && ! -e /etc/systemd/system/unifi-mongodb.service && ! -L /etc/systemd/system/unifi-mongodb.service ]]; then
    ln -s /lib/systemd/system/mongodb.service /etc/systemd/system/unifi-mongodb.service
fi

# Apply Synology patches
SYS_VENDOR="/sys/class/dmi/id/sys_vendor"
if { [ -f "$SYS_VENDOR" ] && grep -q "Synology" "$SYS_VENDOR"; } \
    || [ "${HARDWARE_PLATFORM:-}" = "synology" ]; then

    if [ -n "${HARDWARE_PLATFORM+1}" ]; then
        log INFO "Setting HARDWARE_PLATFORM to $HARDWARE_PLATFORM"
    else
        log INFO "Synology hardware found, applying patches..."
    fi

    # Set postgresql overrides
    mkdir -p /etc/systemd/system/postgresql@14-main.service.d
    {
        echo "[Service]"
        echo "PIDFile="
    } > /etc/systemd/system/postgresql@14-main.service.d/override.conf

    # Set rabbitmq overrides
    mkdir -p /etc/systemd/system/rabbitmq-server.service.d
    {
        echo "[Service]"
        echo "Type=simple"
    } > /etc/systemd/system/rabbitmq-server.service.d/override.conf

    # Set ulp-go overrides
    mkdir -p /etc/systemd/system/ulp-go.service.d
    {
        echo "[Service]"
        echo "Type=simple"
    } > /etc/systemd/system/ulp-go.service.d/override.conf

    log INFO "Synology patches applied!"
fi

# Set UOS_SYSTEM_IP
UNIFI_SYSTEM_PROPERTIES="/var/lib/unifi/system.properties"
if [ -n "${UOS_SYSTEM_IP+1}" ]; then
    log INFO "Setting UOS_SYSTEM_IP to $UOS_SYSTEM_IP"
    if [ ! -f "$UNIFI_SYSTEM_PROPERTIES" ]; then
        echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
    else
        if grep -q "^system_ip=.*" "$UNIFI_SYSTEM_PROPERTIES"; then
            sed -i 's/^system_ip=.*/system_ip='"$UOS_SYSTEM_IP"'/' "$UNIFI_SYSTEM_PROPERTIES"
        else
            echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
        fi
    fi
fi

# Where unifi-core finds the discovery client. The image points it at the client inside the
# container; the bridge compose file points it at the sidecar on the host network (README, Networking).
if [ -n "${UOS_DISCOVERY_CLIENT_URL:-}" ]; then
    log INFO "Setting discovery client URL to $UOS_DISCOVERY_CLIENT_URL"
    sed -i "s|\"discoveryClientUrl\":\"[^\"]*\"|\"discoveryClientUrl\":\"$UOS_DISCOVERY_CLIENT_URL\"|" /etc/default/unifi-core_advanced*
fi

# systemd needs /run on tmpfs and UniFi needs exec on /run and /tmp; an unprivileged container
# cannot mount these itself, Docker must (tmpfs section of docker-compose.yaml).
# With CAP_SYS_ADMIN (privileged) systemd mounts them on its own, so skip the check.
if ! (((0x$(awk '/^CapEff/ {print $2}' /proc/self/status) >> 21) & 1)); then
    for want in /run:exec /tmp:exec /var/opt/unifi/tmp; do
        dir=${want%:*}
        if [ "$(findmnt -no FSTYPE -T "$dir" 2> /dev/null)" != "tmpfs" ]; then
            log WARN "$dir is not on tmpfs, add '$want' to the tmpfs section of docker-compose.yaml"
        elif [[ $want == *:exec && $(findmnt -no OPTIONS -T "$dir") == *noexec* ]]; then
            log WARN "$dir is mounted noexec, use '$want' in the tmpfs section of docker-compose.yaml"
        fi
    done
fi

# Options for the console log stream (UOS_LOG_*, see README): systemd units do not see the container environment
env | grep '^UOS_LOG_' > /etc/default/uos-log

# Start systemd. notice: keeps its info chatter (version banner, "Detected virtualization",
# "Set hostname", "Started X" in the journal) off the console; [  OK  ] lines and failures stay.
exec /sbin/init --log-level=notice
