# Mediabox2

A modular, menu-driven Docker media server installer using whiptail.

Upgrade of [mediabox](https://github.com/jamesvthompson/mediabox) with service selection, modular architecture, and a polished terminal UI.

## Quick Start

```bash
./mediabox2.sh
```

## Main Menu

- **New Install** - Full guided setup with service selection
- **Update Existing Install** - Pull latest images and restart
- **Relaunch Existing Stack** - Restart existing containers
- **Reconfigure Services** - Add/remove services from your stack
- **Status** - View running containers and ports
- **Reset** - Stop everything and clean up
- **Exit**

## Available Services (35 modules)

| Category | Services |
|----------|----------|
| Media Servers | Plex, Jellyfin, Emby |
| Content Automation | Radarr, Sonarr, Lidarr, CouchPotato, SickChill, Headphones |
| Indexers | Jackett, Prowlarr, NZBHydra2 |
| Download Clients | DelugeVPN, NZBGet, MeTube, TubeSync |
| Request Management | Ombi, Overseerr, Requestrr |
| Media Processing | Tdarr, Tdarr-Node, FlareSolverr |
| System & Monitoring | Portainer, Watchtower, Netdata, Glances, Speedtest, Dozzle, Tautulli |
| Utilities | FileBrowser, MinIO, Duplicati, SQLite Browser, Homer, Maintainerr |

## Prerequisites

- Linux (Ubuntu 24.04 LTS recommended)
- Docker with Compose plugin
- whiptail
- yq (auto-installed if missing)
- **Do not run as root**

## Architecture

```
mediabox2.sh          # Main entry point (menu system)
lib/
  common.sh           # Whiptail wrappers, logging, prerequisites
  config.sh           # System detection, config prompting, .env generation
  services.sh         # Module discovery, selection UI, dependencies
  compose.sh          # Docker-compose assembly & management
  postinstall.sh      # Post-deploy configuration hooks
modules/              # One YAML file per service (compose fragments)
ovpn/                 # PIA OpenVPN configuration files
homer_assets/         # Homer dashboard templates
```

Each service is defined as a self-contained module in `modules/`. During install, selected modules are merged into a single `docker-compose.yml` using `yq`.

## VPN Support

PIA (Private Internet Access) VPN integration for DelugeVPN. OpenVPN configs bundled in `ovpn/`. Only prompted when DelugeVPN is selected.
