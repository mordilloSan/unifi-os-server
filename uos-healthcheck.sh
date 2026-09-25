#!/bin/bash
# Docker healthcheck: unhealthy if UniFi OS does not answer on /api/ping or a systemd unit has
# failed, and say which. Read it with: docker inspect --format '{{json .State.Health}}' <container>
rc=0

states=""
for u in unifi-core nginx postgresql@14-main mongodb rabbitmq-server unifi; do
    state=$(systemctl is-active "$u" 2> /dev/null)
    states+="$u=${state:-unknown} "
done

failed=$(systemctl list-units --state=failed --plain --no-legend 2> /dev/null | awk '{print $1}' | paste -sd' ')
if [ -n "$failed" ]; then
    echo "failed units: $failed"
    rc=1
fi

if curl -fs -m 5 -o /dev/null http://127.0.0.1/api/ping; then
    ping="/api/ping ok"
else
    ping="no response on /api/ping"
    rc=1
fi
echo "$ping: $states"
exit "$rc"
