FROM ghcr.io/mordillosan/uosserver:c9603dec9010-multiarch

LABEL org.opencontainers.image.source="https://github.com/mordilloSan/unifi-os-server"

ENV container="docker"
ENV APP_VERSION="5.1.42"
ENV APP_MODEL="UOSSERVER"
ENV PRODUCT_NAME="UniFi OS Server"

STOPSIGNAL SIGRTMIN+3

COPY uos-entrypoint.sh uos-healthcheck.sh uos-journal-pump.sh uos-console-journal.py /root/
COPY uos-console-journal.service uos-journal-pump@.service /etc/systemd/system/

RUN ["chmod", "+x", "/root/uos-entrypoint.sh", "/root/uos-healthcheck.sh", "/root/uos-journal-pump.sh", "/root/uos-console-journal.py"]
# Application logs go into the journal; with tty: true the journal is streamed to docker logs. No login prompt.
RUN systemctl enable uos-console-journal.service uos-journal-pump@unifi-core.service uos-journal-pump@unifi.service uos-journal-pump@postgres.service \
    && systemctl mask console-getty.service
ENTRYPOINT ["/root/uos-entrypoint.sh"]
HEALTHCHECK --interval=60s --timeout=15s --start-period=5m --retries=3 CMD ["/root/uos-healthcheck.sh"]
