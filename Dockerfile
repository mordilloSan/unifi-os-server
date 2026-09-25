FROM ghcr.io/mordillosan/uosserver:c9603dec9010-multiarch

LABEL org.opencontainers.image.source="https://github.com/mordilloSan/unifi-os-server"

ENV container="docker"
ENV APP_VERSION="5.1.42"
ENV APP_MODEL="UOSSERVER"
ENV PRODUCT_NAME="UniFi OS Server"

STOPSIGNAL SIGRTMIN+3

COPY uos-entrypoint.sh uos-healthcheck.sh uos-journal-pump.sh uos-console-journal.py uos-failure-dump.sh /root/
COPY uos-console-journal.service uos-journal-pump@.service /etc/systemd/system/

RUN ["chmod", "+x", "/root/uos-entrypoint.sh", "/root/uos-healthcheck.sh", "/root/uos-journal-pump.sh", "/root/uos-console-journal.py", "/root/uos-failure-dump.sh"]
# Application logs go into the journal; with tty: true the journal is streamed to docker logs. No login prompt.
RUN systemctl enable uos-console-journal.service uos-journal-pump@unifi-core.service uos-journal-pump@unifi.service uos-journal-pump@postgres.service \
    && systemctl mask console-getty.service
# When one of the main services fails, copy the output of that run to docker logs (ExecStopPost hook)
RUN for u in unifi-core unifi mongodb postgresql@ rabbitmq-server nginx; do \
        mkdir -p /etc/systemd/system/$u.service.d \
        && printf '[Service]\nExecStopPost=+/root/uos-failure-dump.sh %%n\n' > /etc/systemd/system/$u.service.d/uos-failure-dump.conf; \
    done
# UniFi's own install runs uos-discovery-client on the host and points unifi-core at it through
# host.docker.internal. Here the client runs inside the container, on 127.0.0.1:11002, so point
# unifi-core there (this is what the app's default.yaml already says). grep fails the build if
# UniFi changes the file so the drift is noticed.
RUN sed -i 's|host\.docker\.internal:11002|127.0.0.1:11002|g' /etc/default/unifi-core_advanced* \
    && grep -q '127.0.0.1:11002' /etc/default/unifi-core_advanced

ENTRYPOINT ["/root/uos-entrypoint.sh"]
HEALTHCHECK --interval=60s --timeout=15s --start-period=5m --retries=3 CMD ["/root/uos-healthcheck.sh"]
