#!/bin/bash
# ExecStopPost hook, wired in the Dockerfile for the main services: when a service run ends in
# failure, copy that run's output from the journal to the console, which is docker logs with
# tty: true. systemd provides SERVICE_RESULT, EXIT_CODE, EXIT_STATUS and INVOCATION_ID.
[ "$SERVICE_RESULT" = success ] && exit 0
[ -c /dev/console ] || exit 0
[ -f /etc/default/uos-log ] && . /etc/default/uos-log

line=""
[[ ${UOS_LOG_TIMESTAMP,,} =~ ^(false|0|no|off)$ ]] || line+="$(date +%Y-%m-%dT%H:%M:%S) "
if [[ ${UOS_LOG_COLOR,,} =~ ^(false|0|no|off)$ ]]; then
    line+="[ERROR ]"
else
    line+=$'[\e[31mERROR \e[0m]'
fi
[[ ${UOS_LOG_SOURCE,,} =~ ^(false|0|no|off)$ ]] || line+=" systemd:"
{
    echo "$line $1 failed ($SERVICE_RESULT, $EXIT_CODE $EXIT_STATUS), output of that run:"
    journalctl --quiet --no-pager --output=cat "_SYSTEMD_INVOCATION_ID=$INVOCATION_ID" | tail -n 30 | sed 's/^/    /'
} > /dev/console
