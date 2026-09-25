# UniFi OS Server

<a href="https://github.com/mordilloSan/unifi-os-server/actions/workflows/build-image.yaml"><img src="https://img.shields.io/github/actions/workflow/status/mordilloSan/unifi-os-server/build-image.yaml?logo=githubactions&logoColor=white&label=Actions"></a>

Run [UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) directly in Docker.

> The **UniFi OS Server is the new standard for self-hosting UniFi**, replacing the legacy UniFi Network Server. While the Network Server provided basic hosting functionality, it lacked support for key UniFi OS features like Organizations, IdP Integration, or Site Magic SD-WAN. With a fully unified operating system, UniFi OS Server now delivers the same management experience as UniFi-native–including CloudKeys, Cloud Gateways, and Official UniFi Hosting–and is fully compatible with Site Manager for centralized, multi-site control.
>
> <https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi>

# Installation

## Docker Compose

Two complete files, pick one: [docker-compose.yaml](https://github.com/mordilloSan/unifi-os-server/blob/main/docker-compose.yaml) gives the container its own address on your LAN (macvlan) plus a bridge network, [docker-compose.host.yaml](https://github.com/mordilloSan/unifi-os-server/blob/main/docker-compose.host.yaml) puts it on the host network. [Networking](#networking) explains the difference.

## Tags

Releases are named after the UniFi OS Server version they ship plus an image revision, for example `v5.1.42-1`. Each release publishes four tags:

| Tag | Meaning |
|----|----|
| `latest` | the newest release |
| `v5.1.42-1` | this exact build, never changes |
| `v5.1.42` | the newest build of UniFi OS Server 5.1.42, moves when the image itself is fixed |
| `v5.1` | the newest build of the 5.1 line |

# Parameters

## Environment Variables

| Environment | Description |
|----|----|
| UOS_SYSTEM_IP | Hostname or IP for UniFi OS Server |
| HARDWARE_PLATFORM | Manually set hardware platform |
| UOS_LOG_LEVEL | `docker logs`: lowest journal priority shown. Default `notice`: warnings, errors and systemd state changes, minus the known startup noise listed in the FAQ. `info` adds everything the applications log, noise included |
| UOS_LOG_TIMESTAMP | `docker logs`: prefix lines with the time (default `true`) |
| UOS_LOG_SOURCE | `docker logs`: prefix lines with the source, e.g. `unifi-core:` (default `true`) |
| UOS_LOG_COLOR | `docker logs`: color the `[ WARN ]` level tag (default `true`) |

### UOS_SYSTEM_IP

Set UniFi OS Server hostname (recommended) or IP address for inform. To adopt device:

1. SSH into device with username/password: `ubnt`/`ubnt`
2. Set inform address:

   ```bash
   set-inform http://$UOS_SYSTEM_IP:8080/inform
   ```

### HARDWARE_PLATFORM

Overrides your detected hardware platform. Accepted values are: `synology`.

## Ports

| Protocol | Port | Direction | Usage |
|----|----|----|----|
| TCP | 11443 | Ingress | UniFi OS Server GUI/API |
| TCP | 5005 | Ingress | RTP (Real-time Transport Protocol) control protocol |
| TCP | 9543 | Ingress | UniFi Identity Hub |
| TCP | 6789 | Ingress | UniFi mobile speed test |
| TCP | 8080 | Ingress | Device and application communication |
| TCP | 8444 | Ingress | Secure Portal for Hotspot |
| UDP | 3478 | Both | STUN for device adoption and communication *(also required for Remote Management)* |
| UDP | 5514 | Ingress | Remote syslog capture |
| UDP | 10003 | Ingress | Device discovery during adoption |
| TCP | 28082 | Ingress | Device support files download |
| TCP | 5671 | Ingress | AQMPS |
| TCP | 8880 | Ingress | Hotspot portal redirection (HTTP) |
| TCP | 8881 | Ingress | Hotspot portal redirection (HTTP) |
| TCP | 8882 | Ingress | Hotspot portal redirection (HTTP) |

# Networking

UniFi needs the container on your LAN: devices announce themselves by broadcast, the console scans for them by broadcast, and both stop at Docker's NAT. So neither compose file uses Docker's default bridge with published ports. Pick one:

| | `docker-compose.yaml`: macvlan + bridge | `docker-compose.host.yaml`: host network |
|----|----|----|
| The container is | a machine on your LAN with its own address | the host itself |
| Web UI | `https://<container address>` | `https://<host>` |
| Devices adopt by themselves, *Discover devices* in the UI | Yes | Yes |
| Open on the LAN | the container's ports, on its own address | every port the container opens, on every host interface |
| The host can reach the container | over the bridge network, by name or bridge address | yes |
| Other containers can reach it | on the bridge network, by name | on the host's address |
| Needs | a free LAN address, a NIC that accepts promiscuous mode | free host ports: 80, 443, 8080 and the rest |

Both work because the discovery client, which UniFi's installer runs on the host, runs inside this image and is what UniFi OS talks to. On the LAN it sees your devices; on Docker's default bridge it would only see Docker's network.

## macvlan + bridge

[docker-compose.yaml](docker-compose.yaml) has three values to fill in: the container's LAN address, used twice, the host interface on the LAN, and your subnet and gateway. Reserve the address in your DHCP server.

- On the LAN the container answers directly: UI on 443, informs on 8080, STUN on 3478. Nothing is published. Uncomment the `ports` block to also reach the UI through the host's address on 11443.
- The bridge network, `default`, is for the host and for other containers on it, such as a reverse proxy pointing at `unifi-os-server:443`. macvlan itself does not let the host talk to the container; the bridge is what makes that possible.
- `UOS_SYSTEM_IP` must be the container's address, so that devices are told to inform there and not on the bridge address.
- The host's NIC must accept promiscuous mode. Physical servers do; some hypervisors and NAS units need it enabled.
- Moving from a bridge deployment: same volumes, new file, and the Network application re-points adopted devices to the new address by itself.

## Host network

[docker-compose.host.yaml](docker-compose.host.yaml) has no network to configure, but read this first:

- The container opens its ports directly on the host: 80 and 443 for the UI, then 5005, 5671, 6789, 8080, 8444, 8880 to 8882, 9543, 11084, 28082, 3478/udp, 5514/udp, 10001/udp and 10003/udp, plus whatever the installed applications add. Anything else on the host using one of those has to move. `docker exec unifi-os-server ss -tulnp` lists what is open.
- Services bound to `127.0.0.1` inside the container, PostgreSQL 5432, MongoDB 27117, RabbitMQ 5672, epmd 4369 and the discovery client 11002, now bind the host's loopback. They stay unreachable from the LAN, but they collide with a PostgreSQL or MongoDB already running on the host. snmpd listens on all interfaces on 161/udp with the community `public`, read-only, system group only; in host mode that is reachable from your LAN unless you firewall it.
- `ports:` and `hostname:` are not usable in this mode, which is why the file has neither.
- `UOS_SYSTEM_IP` is the host's address.

## About the LAN IP UniFi OS reports

UniFi OS takes the first interface with an IPv4 address from the list, in alphabetical order. With macvlan plus bridge the two interfaces are `eth0` and `eth1` and Docker does not guarantee which network gets which, so the reported address may be the bridge one; on the host network it is often a `br-…` or `docker0` bridge rather than your NIC. UniFi OS Server only uses that address to identify itself to other consoles in a console group. Adoption, STUN and Remote Management do not use it, and Direct Remote Connection is a gateway feature that UniFi OS Server does not have.

# Frequently Asked Questions

## What is the difference between images?

The `uosserver` image is UniFi's, extracted from the installation binary. The `unifi-os-server` image adds what Docker needs: the entrypoint fixes the ownership of the volumes and warns about missing tmpfs mounts, UniFi OS reaches the discovery client inside the container, the container has a healthcheck, and the application logs are streamed to `docker logs`.

## Does automatic device discovery work?

Yes, with either compose file, because both put the container on your LAN. See [Networking](#networking). If you run the container on Docker's default bridge with published ports instead, devices have to be told where the controller is: `set-inform` (see `UOS_SYSTEM_IP`), DHCP option 43, or a DNS record named `unifi` pointing at the host, since devices try `http://unifi:8080/inform` on their own.

## Which errors at startup are normal?

Every boot logs a few errors that come from UniFi's own components and fix themselves. The ones marked *hidden* are dropped from `docker logs` by default and shown with `UOS_LOG_LEVEL=info`; the journal and the log files always keep them.

- *Hidden.* `MessageBox: Invalid token` from unifi-core, and `Connection to MessageBox closed` from the Network application. The Network application reconnects with a stale token from the previous boot, is refused, and subscribes again 10 seconds later.
- *Hidden.* `Failed to retrieve anonymous network application ID` from unifi-core, after six retries. An internal call for the diagnostics ID that fails on every boot; nothing waits on it.
- *Hidden.* `Cannot publish s2s-vpn-sites request - sites list is empty`, the `Application degradation` warnings and the `component[...] initialization took` warnings from the Network application. SD-WAN sites you do not have, hardware monitoring that does not exist in a container, and Spring Boot's startup timing.
- Until the site is set up: `Country Code is not configured` and `Cannot notify listeners on saving 'apgroup' document` from the Network application. They stop once the site has its settings.
- Until the console is linked to a UniFi account: `Remote access is disabled` from unifi-core and `Cannot send sdwan-get-last-configs-to-apply HTTP Cloud Event` from the Network application. The SD-WAN task asks unifi-core to reach the cloud, which it cannot without remote access.

## Why does the container need specific settings for cgroup and tmpfs?

The underlying structure of UniFi OS Server runs every component as systemd services which requires access to the host `cgroup`. The entrypoint prints a `WARNING` in the container logs when one of the tmpfs mounts is missing or mounted `noexec`.

## Why is the container unhealthy?

The UniFi OS (`system.log`, `errors.log`), Network application (`server.log`) and PostgreSQL logs are copied into the journal under the identifiers `unifi-core`, `unifi` and `postgres`, so `docker exec unifi-os-server journalctl -f -t unifi` works. With `tty: true` (see [docker-compose.yaml](docker-compose.yaml)) `docker logs` shows the systemd boot status followed by the journal at notice level and up: warnings and errors of those applications plus systemd state changes, as `2026-09-24T08:15:54 [ WARN ] unifi-core: Failed to fetch network interfaces`. `UOS_LOG_LEVEL=info` adds everything the applications log; the other `UOS_LOG_*` variables switch the time, the source and the colors off. The `logging` section of the compose file caps that at three 10 MB files. When one of the main services exits with an error, the output of that run is copied to `docker logs` right after systemd's `Failed to start` line. The healthcheck reports failed systemd units, whether UniFi OS answers on `/api/ping` and the state of the main services:

```bash
docker inspect --format '{{json .State.Health.Log}}' unifi-os-server | jq -r '.[-1].Output'
```

## The services fail with permission errors on my volumes

The entrypoint fixes the ownership of the MongoDB, PostgreSQL, RabbitMQ and UniFi agent directories on every start and logs what it changed, so restart the container and check `docker logs`.