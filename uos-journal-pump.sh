#!/bin/bash
# Pumps one application log source into the journal, minus its own timestamp, so that journalctl
# and the console show every source in one format. Run by uos-journal-pump@.service.
case $1 in
    unifi-core)
        files=(/data/unifi-core/logs/system.log /data/unifi-core/logs/errors.log)
        strip='s/^[0-9T:.+-]* - //'
        ;;
    unifi)
        files=(/data/unifi/logs/server.log)
        strip='s/^\[[^]]*\] //'
        ;;
    postgres)
        files=(/var/log/postgresql/postgresql-14-main.log)
        strip='s/^[0-9-]* [0-9:.]* [A-Z]* //'
        ;;
    *)
        echo "unknown log source: $1" >&2
        exit 1
        ;;
esac
tail -q -F -n0 "${files[@]}" | sed -u "$strip"
