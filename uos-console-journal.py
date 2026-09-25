#!/usr/bin/env python3
"""Stream the journal to the console, which is docker logs when tty: true is set, systemd style:

    2026-09-24T08:15:54 [ WARN ] unifi-core: Failed to fetch network interfaces

Set UOS_LOG_TIMESTAMP, UOS_LOG_SOURCE or UOS_LOG_COLOR to false to drop a part. UOS_LOG_LEVEL is the
lowest journal priority shown, notice by default: warnings, errors and systemd state changes; info
adds everything the applications log. Only the daemon facility (systemd and unit output) is read, so
the sudo/cron/pam audit lines stay out.
Run by uos-console-journal.service.
"""
import json
import os
import re
import subprocess
from datetime import datetime


def enabled(name):
    return os.environ.get(name, "true").lower() not in ("false", "0", "no", "off")


TIMESTAMP, SOURCE, COLOR = enabled("UOS_LOG_TIMESTAMP"), enabled("UOS_LOG_SOURCE"), enabled("UOS_LOG_COLOR")
LEVEL = os.environ.get("UOS_LOG_LEVEL", "notice").lower()
if LEVEL not in ("emerg", "alert", "crit", "err", "warning", "notice", "info", "debug", *"01234567"):
    LEVEL = "notice"
# Logged on every boot in a container and carrying no information (README, "Which errors at startup
# are normal?"). Dropped from the console stream unless UOS_LOG_LEVEL asks for info or debug; the
# journal and the log files keep them.
NOISE_RE = re.compile("|".join([
    r": Consumed [0-9.]+m?s CPU time\.?$",                          # systemd bookkeeping
    r"initialization took [0-9]+ms$",                                # Spring Boot startup timing
    r"Application degradation: .* not supported$",                  # hardware monitoring, absent here
    r"MessageBox: Invalid token$",                                   # stale token, reconnects 10 s later
    r"Connection to MessageBox closed",
    r"Failed to retrieve anonymous network application ID",         # every boot, nothing waits on it
    r"Cannot publish s2s-vpn-sites request - sites list is empty",  # no SD-WAN sites
]))
QUIET = LEVEL not in ("info", "debug", "6", "7")

# Level word at the start of a message, "word:" in any case or an UPPERCASE word:
# unifi-core "warn: ...", Network app "<thread> WARN  logger - ...", PostgreSQL "[pid] LOG:  ...".
# Anything else takes its level from the journal priority.
LEVEL_RE = re.compile(r"^(?P<prefix><[^>]+> |\[\d+\] )?(?:(?P<colon>[A-Za-z]+):|(?P<upper>[A-Z]+))\s+")
LEVELS = {"debug": "DEBUG", "info": "INFO", "log": "INFO", "notice": "INFO",
          "warn": "WARN", "warning": "WARN",
          "error": "ERROR", "err": "ERROR", "fatal": "ERROR", "panic": "ERROR", "crit": "ERROR"}
PRIORITY_LEVELS = {"0": "ERROR", "1": "ERROR", "2": "ERROR", "3": "ERROR", "4": "WARN", "5": "INFO", "6": "INFO", "7": "DEBUG"}
COLORS = {"INFO": "32", "WARN": "33", "ERROR": "31"}


def tag(level):
    text = f"{level:^6}"
    if COLOR and level in COLORS:
        text = f"\x1b[{COLORS[level]}m{text}\x1b[0m"
    return f"[{text}]"


def format_entry(entry):
    message = entry.get("MESSAGE", "")
    if isinstance(message, list):  # non UTF-8 payloads arrive as byte arrays
        message = bytes(message).decode(errors="replace")
    elif message is None:  # journalctl -o json replaces fields over 4 KB with null
        message = "(message over 4 KB, see journalctl -t " + str(entry.get("SYSLOG_IDENTIFIER", "")) + ")"
    elif not isinstance(message, str):
        message = str(message)
    level = PRIORITY_LEVELS.get(entry.get("PRIORITY"), "INFO")
    match = LEVEL_RE.match(message)
    word = (match.group("colon") or match.group("upper")).lower() if match else None
    if word in LEVELS:
        level = LEVELS[word]
        message = (match.group("prefix") or "") + message[match.end():]
    parts = []
    if TIMESTAMP:
        parts.append(datetime.fromtimestamp(int(entry["__REALTIME_TIMESTAMP"]) / 1e6).strftime("%Y-%m-%dT%H:%M:%S"))
    parts.append(tag(level))
    if SOURCE and entry.get("SYSLOG_IDENTIFIER"):
        parts.append(entry["SYSLOG_IDENTIFIER"] + ":")
    parts.append(message)
    return " ".join(parts)


def main():
    journal = subprocess.Popen(
        ["journalctl", "--follow", "--lines=0", "--quiet", "--output=json", "--priority=" + LEVEL, "SYSLOG_FACILITY=3"],
        stdout=subprocess.PIPE, text=True)
    for line in journal.stdout:
        entry = json.loads(line)
        if QUIET and isinstance(entry.get("MESSAGE"), str) and NOISE_RE.search(entry["MESSAGE"]):
            continue
        print(format_entry(entry), flush=True)


if __name__ == "__main__":
    main()
