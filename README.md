# UniFi OS Server

<a href="https://github.com/mordilloSan/unifi-os-server/actions/workflows/build-image.yaml"><img src="https://img.shields.io/github/actions/workflow/status/mordilloSan/unifi-os-server/build-image.yaml?logo=githubactions&logoColor=white&label=Actions"></a>

Run [UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) directly in Docker or Kubernetes.

> The **UniFi OS Server is the new standard for self-hosting UniFi**, replacing the legacy UniFi Network Server. While the Network Server provided basic hosting functionality, it lacked support for key UniFi OS features like Organizations, IdP Integration, or Site Magic SD-WAN. With a fully unified operating system, UniFi OS Server now delivers the same management experience as UniFi-native–including CloudKeys, Cloud Gateways, and Official UniFi Hosting–and is fully compatible with Site Manager for centralized, multi-site control.
>
> <https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi>

# Installation

## Docker Compose

See [docker-compose.yaml](https://github.com/mordilloSan/unifi-os-server/blob/main/docker-compose.yaml)

## Kubernetes

See [kubernetes](https://github.com/mordilloSan/unifi-os-server/tree/main/kubernetes)

Deployment example uses [ingress-nginx](https://github.com/kubernetes/ingress-nginx) for the ingress and [longhorn](https://github.com/longhorn/longhorn) for storage.

Your ingress controller must be modified to accept extra ports. For example, `ingress-nginx` Helm values:

```yaml
tcp:
  5005: "unifi/unifi-os-server-rtp-svc:5005" # Optional
  9543: "unifi/unifi-os-server-id-hub-svc:9543" # Optional
  6789: "unifi/unifi-os-server-mobile-speedtest-svc:6789" # Optional
  8080: "unifi/unifi-os-server-communication-svc:8080"
  8444: "unifi/unifi-os-server-hotspot-secured-svc:8444" # Optional
  28082: "unifi/unifi-os-server-support-files:28082" # Optional
  5671: "unifi/unifi-os-server-aqmps-svc:5671" # Optional
  8880: "unifi/unifi-os-server-hotspot-redirect-0-svc:8880" # Optional
  8881: "unifi/unifi-os-server-hotspot-redirect-1-svc:8881" # Optional
  8882: "unifi/unifi-os-server-hotspot-redirect-2-svc:8882" # Optional
udp:
  3478: "unifi/unifi-os-server-stun-svc:3478"
  5514: "unifi/unifi-os-server-syslog-svc:5514" # Optional
  10003: "unifi/unifi-os-server-discovery-svc:10003"
```

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

The compose file runs the container on Docker's default bridge network and publishes the ports listed above. That is the right default for most setups. Two UniFi features need the container to be on your LAN instead of behind Docker's NAT, and this is what changes between the three ways to run it:

| | Bridge (default) | Host network | macvlan |
|----|----|----|----|
| Web UI | `https://<host>:11443` | `https://<host>`, the container's 443 with nothing mapped | `https://<container IP>` |
| Adoption with `set-inform`, DHCP option 43 or a DNS record named `unifi` | Yes | Yes | Yes |
| Devices finding the controller by L2 broadcast | No | Yes | Yes |
| *Discover devices* scan in the UI | No, the scan returns nothing | Yes | Yes |
| LAN IP the console reports | the container's, `172.17.x.x` | the host's | the container's own LAN address |
| Reachable from the LAN | the published ports only | every port the container opens, on every host interface | every port, on the container's IP |

## Why

UniFi's own installer runs `uos-discovery-client` on the host, outside the container, and points UniFi OS at it through the name `host.docker.internal`. That client is what reads the network interfaces and scans the LAN for devices. This image runs the same client inside the container and points UniFi OS at it on `127.0.0.1:11002`, a one-line change in the [Dockerfile](Dockerfile). The upstream image keeps UniFi's setting, so UniFi OS there calls the Docker host, where nothing listens, and logs `Failed to fetch network interfaces from discovery agent` every 3 seconds.

The client can only see and scan the network the container is on. On the bridge network that is Docker's `172.17.0.0/16`, so a scan finds nothing and the console reports its container address as its LAN IP. UniFi OS Server only uses that address to identify itself to other consoles in a console group. Adoption, STUN and Remote Management do not use it, and Direct Remote Connection is a gateway feature that UniFi OS Server does not have, so mapping the container's port 443 to the host's 443 changes nothing here.

## Host network

[docker-compose.host.yaml](docker-compose.host.yaml) switches the compose file to host networking:

```bash
docker compose -f docker-compose.yaml -f docker-compose.host.yaml up -d
```

Before you do:

- The container opens its ports directly on the host: 80 and 443 for the UI, then 5005, 5671, 6789, 8080, 8444, 8880 to 8882, 9543, 11084, 28082, 3478/udp, 5514/udp and 10003/udp from the table above, plus whatever the installed applications add. Anything else on the host using one of those has to move. `docker exec unifi-os-server ss -tulnp` lists what is open.
- Services bound to `127.0.0.1` inside the container, PostgreSQL 5432, MongoDB 27117, RabbitMQ 5672, epmd 4369, SNMP 161 and the discovery client 11002, now bind the host's loopback. They stay unreachable from the LAN, but they collide with a PostgreSQL or MongoDB already running on the host.
- `ports:` is ignored in this mode, the override clears it, and `hostname:` is not allowed.
- `UOS_SYSTEM_IP` stays the host's address.

## macvlan

macvlan gives the container its own address on your LAN, like a separate machine. Add a network with your LAN's details and attach the service to it:

```yaml
services:
  unifi-os-server:
    networks:
      lan:
        ipv4_address: 192.168.1.50 # a free address on your LAN
    ports: !reset []
    environment:
      - UOS_SYSTEM_IP=192.168.1.50

networks:
  lan:
    driver: macvlan
    driver_opts:
      parent: eth0 # the host interface on your LAN
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
```

Two limits come from macvlan itself: the host cannot talk to the container over that interface unless you add a macvlan shim interface on the host, and the host's NIC must accept promiscuous mode, which some hypervisors and NAS units block.

# Frequently Asked Questions

## What is the difference between images?

The `uosserver` image is UniFi's, extracted from the installation binary. The `unifi-os-server` image adds what Docker and Kubernetes need: the entrypoint fixes the ownership of the volumes and warns about missing tmpfs mounts, UniFi OS reaches the discovery client inside the container, the container has a healthcheck, and the application logs are streamed to `docker logs`.

## Does automatic device discovery work?

Only when the container is on your LAN, see [Networking](#networking). On the default bridge network, adopt devices with `set-inform` (see `UOS_SYSTEM_IP`), with DHCP option 43, or with a DNS record named `unifi` pointing at the host: devices try `http://unifi:8080/inform` on their own.

## Why does the container need specific settings for cgroup and tmpfs?

The underlying structure of UniFi OS Server runs every component as systemd services which requires access to the host `cgroup`. The entrypoint prints a `WARNING` in the container logs when one of the tmpfs mounts is missing or mounted `noexec`.

## Why is the container unhealthy?

The UniFi OS (`system.log`, `errors.log`), Network application (`server.log`) and PostgreSQL logs are copied into the journal under the identifiers `unifi-core`, `unifi` and `postgres`, so `docker exec unifi-os-server journalctl -f -t unifi` works. With `tty: true` (see [docker-compose.yaml](docker-compose.yaml)) `docker logs` shows the systemd boot status followed by the journal at notice level and up, those application logs plus systemd warnings and errors, as `2026-09-24T08:15:54 [ WARN ] unifi-core: Failed to fetch network interfaces`. The `UOS_LOG_*` variables switch the time, the source and the colors off. The `logging` section of the compose file caps that at three 10 MB files. The healthcheck reports failed systemd units, whether UniFi OS answers on `/api/ping` and the state of the main services:

```bash
docker inspect --format '{{json .State.Health.Log}}' unifi-os-server | jq -r '.[-1].Output'
```

## The services fail with permission errors on my volumes

The entrypoint fixes the ownership of the MongoDB, PostgreSQL, RabbitMQ and UniFi agent directories on every start and logs what it changed, so restart the container and check `docker logs`.