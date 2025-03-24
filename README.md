# homelab-configs

This repository contains configuration files for setting up and managing a homelab environment using Docker Compose.

## Docker Compose Configurations

### compose-bw

This configuration sets up the following services:
- **vaultwarden**: A Bitwarden-compatible server written in Rust.
- **reverse-proxy**: A simple and powerful reverse proxy manager using Nginx Proxy Manager.
- **cloudflared**: A tunneling daemon for Cloudflare's Argo Tunnel.

#### Networks
- `proxy-net`: A bridge network for the services.

#### Services
- `vaultwarden`
  - **Container Name**: `vaultwarden`
    - The name of the container.
  - **Volumes**: `./vw-data/:/data/`
    - Mounts the local directory `./vw-data/` to the container's `/data/` directory.
  - **Ports**: `8080:80`
    - Maps port 80 in the container to port 8080 on the host.
  - **Image**: `vaultwarden/server:latest`
    - The Docker image to use for the container.
  - **Networks**: `proxy-net`
    - Connects the container to the `proxy-net` network.

- `reverse-proxy`
  - **Container Name**: `reverse-proxy`
    - The name of the container.
  - **Image**: `jc21/nginx-proxy-manager:latest`
    - The Docker image to use for the container.
  - **Ports**: `80:80`, `81:81`, `443:443`
    - Maps ports 80, 81, and 443 in the container to the same ports on the host.
  - **Volumes**: `./data:/data`, `./letsencrypt:/etc/letsencrypt`
    - Mounts the local directories `./data` and `./letsencrypt` to the container's `/data` and `/etc/letsencrypt` directories, respectively.
  - **Networks**: `proxy-net`
    - Connects the container to the `proxy-net` network.

- `cloudflared`
  - **Container Name**: `cloudflared`
    - The name of the container.
  - **Image**: `cloudflare/cloudflared:latest`
    - The Docker image to use for the container.
  - **Command**: `tunnel --no-autoupdate run`
    - The command to run in the container.
  - **Environment**: `TUNNEL_TOKEN= # Your tunnel token`
    - Sets the `TUNNEL_TOKEN` environment variable in the container.
  - **Networks**: `proxy-net`
    - Connects the container to the `proxy-net` network.

### compose-stack-torrenting

This configuration sets up the following services:
- **qbittorrent**: A BitTorrent client.
- **sonarr**: A PVR for Usenet and BitTorrent users.
- **prowlarr**: An indexer manager/proxy for Sonarr, Radarr, and other applications.

#### Networks
- `torrent_network`: A bridge network for the services.

#### Services
- `qbittorrent`
  - **Container Name**: `qbittorrent`
    - The name of the container.
  - **Image**: `lscr.io/linuxserver/qbittorrent:latest`
    - The Docker image to use for the container.
  - **Environment**: `PUID=1000`, `PGID=1000`, `TZ=Etc/UTC`, `WEBUI_PORT=8080`, `DOCKER_MODS=ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest`
    - Sets environment variables in the container:
      - `PUID=1000`: The user ID to run the container as.
      - `PGID=1000`: The group ID to run the container as.
      - `TZ=Etc/UTC`: The timezone to use in the container.
      - `WEBUI_PORT=8080`: The port for the web UI.
      - `DOCKER_MODS=ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest`: Docker mods to apply.
  - **Volumes**: `/nas:/downloads`, `/home/jorn/qbit/config:/config`, `./qbittorrent.conf:/config/qBittorrent/qBittorrent.conf`
    - Mounts the local directories `/nas`, `/home/jorn/qbit/config`, and `./qbittorrent.conf` to the container's `/downloads`, `/config`, and `/config/qBittorrent/qBittorrent.conf` directories, respectively.
  - **Ports**: `8080:8080`, `6881:6881`, `6881:6881/udp`
    - Maps ports 8080, 6881, and 6881/udp in the container to the same ports on the host.
  - **Networks**: `torrent_network`
    - Connects the container to the `torrent_network` network.

- `sonarr`
  - **Container Name**: `sonarr`
    - The name of the container.
  - **Image**: `lscr.io/linuxserver/sonarr:latest`
    - The Docker image to use for the container.
  - **Environment**: `PUID=1000`, `PGID=1000`, `TZ=Etc/UTC`
    - Sets environment variables in the container:
      - `PUID=1000`: The user ID to run the container as.
      - `PGID=1000`: The group ID to run the container as.
      - `TZ=Etc/UTC`: The timezone to use in the container.
  - **Volumes**: `/home/jorn/sonarr/data:/config`, `/media-mount/Series/:/downloads`
    - Mounts the local directories `/home/jorn/sonarr/data` and `/media-mount/Series/` to the container's `/config` and `/downloads` directories, respectively.
  - **Ports**: `8989:8989`
    - Maps port 8989 in the container to port 8989 on the host.
  - **Networks**: `torrent_network`
    - Connects the container to the `torrent_network` network.

- `prowlarr`
  - **Container Name**: `prowlarr`
    - The name of the container.
  - **Image**: `lscr.io/linuxserver/prowlarr:latest`
    - The Docker image to use for the container.
  - **Environment**: `PUID=1000`, `PGID=1000`, `TZ=Etc/UTC`
    - Sets environment variables in the container:
      - `PUID=1000`: The user ID to run the container as.
      - `PGID=1000`: The group ID to run the container as.
      - `TZ=Etc/UTC`: The timezone to use in the container.
  - **Volumes**: `/home/jorn/prowlarr/config:/config`
    - Mounts the local directory `/home/jorn/prowlarr/config` to the container's `/config` directory.
  - **Ports**: `9696:9696`
    - Maps port 9696 in the container to port 9696 on the host.
  - **Networks**: `torrent_network`
    - Connects the container to the `torrent_network` network.

## Configuration Files

### .gitignore

Specifies files and directories to be ignored by Git.

### qbittorrent.config

Configuration file for qBittorrent.

### wireguard.sample.conf

Sample configuration file for WireGuard VPN.