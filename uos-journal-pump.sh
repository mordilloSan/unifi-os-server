#!/bin/bash
# Pumps one application log source into the journal, minus its own timestamp and stack frames, so
# that journalctl and the console show every source in one format. Run by uos-journal-pump@.service.
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
# Kept in the files but out of the journal: stack frames ("    at ...", "... 13 common frames
# omitted"), the "Error: message" line Node prints under each logged error (it repeats the
# message), and unifi-core errors without a [module] tag, which come from system.log and are
# already in errors.log with the tag.
tail -q -F -n0 "${files[@]}" | sed -u \
    -e "$strip" \
    -e '/^[[:space:]]\+at /d' \
    -e '/^[[:space:]]*\.\.\. [0-9]\+ .*\(omitted\|more\)$/d' \
    -e '/^[A-Za-z]*Error:/d' \
    -e '/^error: [^[]/d'
