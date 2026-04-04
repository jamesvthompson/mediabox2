# Mediabox2

Mediabox2 is a modular, menu-driven Docker media server installer using whiptail. An upgrade of [mediabox](https://github.com/jamesvthompson/mediabox) with service selection, modular architecture, and a polished terminal UI.

## Components

* [CouchPotato movie library manager](https://couchpota.to/)
* [Deluge torrent client (using VPN)](http://deluge-torrent.org/)
* [Dozzle realtime log viewer](https://github.com/amir20/dozzle)
* [Duplicati Backup Software](https://www.duplicati.com/)
* [Emby Open Media Solution](https://emby.media/)
* [FileBrowser Web-Based File Manager](https://github.com/filebrowser/filebrowser)
* [FlareSolverr proxy server to bypass Cloudflare protection](https://github.com/FlareSolverr/FlareSolverr)
* [Glances system monitoring](https://nicolargo.github.io/glances/)
* [Headphones automated music downloader](https://github.com/linuxserver/docker-headphones)
* [Homer - Server Home Page](https://github.com/bastienwirtz/homer)
* [Jackett Tracker API and Proxy](https://github.com/Jackett/Jackett)
* [Jellyfin Free Software Media System](https://github.com/jellyfin/jellyfin)
* [Lidarr Music collection manager](https://lidarr.audio/)
* [Maintainerr library management system](https://maintainerr.info/)
* [MeTube Web GUI for youtube-dl](https://github.com/alexta69/metube)
* [MinIO cloud storage](https://www.minio.io/)
* [NetData System Monitoring](https://github.com/netdata/netdata)
* [NZBGet Usenet Downloader](https://nzbget.net/)
* [NZBHydra2 Meta Search](https://github.com/theotherp/nzbhydra2)
* [Ombi media assistant](http://www.ombi.io/)
* [Overseerr Media Library Request Management](https://github.com/sct/overseerr)
* [Plex media server](https://www.plex.tv/)
* [Portainer Docker Container manager](https://portainer.io/)
* [Prowlarr indexer manager/proxy](https://github.com/Prowlarr/Prowlarr)
* [Radarr movie library manager](https://radarr.video/)
* [Requestrr Chatbot for Sonarr/Radarr/Ombi](https://github.com/darkalfx/requestrr)
* [SickChill TV library manager](https://github.com/SickChill/SickChill)
* [Sonarr TV library manager](https://sonarr.tv/)
* [Speedtest Tracker](https://github.com/henrywhitaker3/Speedtest-Tracker)
* [SQLiteBrowser DB browser for SQLite](https://sqlitebrowser.org/)
* [Tautulli Plex Media Server monitor](https://github.com/tautulli/tautulli)
* [Tdarr Distributed Transcoding System](https://tdarr.io)
* [TubeSync - YouTube PVR](https://github.com/meeb/tubesync)
* [Watchtower Automatic container updater](https://github.com/containrrr/watchtower)

## Prerequisites

* [Ubuntu 24.04 LTS](https://www.ubuntu.com/)
* [VPN account from Private Internet Access](https://www.privateinternetaccess.com/) (only required if using DelugeVPN)
* [Git](https://git-scm.com/)
* [Docker](https://www.docker.com/) with Compose plugin
* whiptail (included in most Ubuntu installations)
* **Do not run as root**

> `yq` (YAML processor) is auto-installed by the script if not present.

---

## Installation (Ubuntu 24.04 LTS)

### 1) Update and upgrade packages
```bash
sudo apt update && sudo apt full-upgrade
```

### 2) Install prerequisites
```bash
sudo apt install -y curl git bridge-utils whiptail
```

### 3) Remove old Docker (OK if nothing to remove)
```bash
sudo apt remove -y docker docker-engine docker.io containerd runc
sudo snap remove docker
```

### 4) Install Docker CE (official method)
```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Verify:
```bash
docker --version
docker compose version
```

### 5) Add your user to the Docker group
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### 6) DelugeVPN kernel module (only needed if using DelugeVPN)
```bash
sudo /sbin/modprobe iptable_mangle
echo iptable_mangle | sudo tee -a /etc/modules
```

### 7) Reboot (recommended after adding Docker group)
```bash
sudo reboot
```

---

## Using Mediabox2

### 8) Clone Mediabox2
```bash
git clone https://github.com/jamesvthompson/mediabox2.git
cd mediabox2
```

### 9) Run the installer
```bash
./mediabox2.sh
```

---

## Main Menu

```
┌─────────────────────────────────┐
│        Mediabox2 Installer      │
│                                 │
│  1. New Install                 │
│  2. Update Existing Install     │
│  3. Relaunch Existing Stack     │
│  4. Reconfigure Services        │
│  5. Status                      │
│  6. Reset                       │
│  7. Exit                        │
└─────────────────────────────────┘
```

- **New Install** - Full guided setup: select services, configure paths, deploy
- **Update Existing Install** - Pull latest images and restart containers
- **Relaunch Existing Stack** - Restart existing containers without reconfiguring
- **Reconfigure Services** - Add or remove services from your running stack
- **Status** - View running containers and port mappings
- **Reset** - Stop everything and clean up generated files
- **Exit**

---

## What You'll Be Asked During New Install

1. **Media directory paths** — where your downloads, TV, movies, music, and misc files live (defaults provided)
2. **Which services to install** — a categorized checklist; select any combination or all
3. **PIA VPN credentials** — only if DelugeVPN is selected
4. **VPN server selection** — choose from bundled PIA OpenVPN configs
5. **Plex release type** — `public`, `latest`, or `plexpass` (only if Plex is selected)
6. **Daemon credentials** — username/password for Deluge daemon and NZBGet access (only if either is selected)

---

## Available Services

| Category | Services |
|---|---|
| Media Servers | Plex, Jellyfin, Emby |
| Content Automation | Radarr, Sonarr, Lidarr, CouchPotato, SickChill, Headphones |
| Indexers | Jackett, Prowlarr, NZBHydra2 |
| Download Clients | DelugeVPN, NZBGet, MeTube, TubeSync |
| Request Management | Ombi, Overseerr, Requestrr |
| Media Processing | Tdarr, Tdarr-Node, FlareSolverr |
| System & Monitoring | Portainer, Watchtower, Netdata, Glances, Speedtest, Dozzle, Tautulli |
| Utilities | FileBrowser, MinIO, Duplicati, SQLite Browser, Homer, Maintainerr |

---

## Architecture

```
mediabox2.sh          # Main entry point (menu system)
lib/
  common.sh           # Whiptail wrappers, logging, prerequisites
  config.sh           # System detection, config prompting, .env generation
  services.sh         # Module discovery, selection UI, dependency resolution
  compose.sh          # Docker-compose assembly & management
  postinstall.sh      # Post-deploy configuration hooks
modules/              # 35 YAML files — one per service (compose fragments + metadata)
ovpn/                 # Bundled PIA OpenVPN configuration files
homer_assets/         # Homer dashboard templates and icons
```

Each service is a self-contained module in `modules/`. During install, selected modules are merged into a single `docker-compose.yml` via `yq`.

---

## Notes

- After install, access the Homer dashboard at `http://<your-ip>` for links to all services
- Portainer is available at `https://<your-ip>:9443` — set a password on first login
- The `.env` file holds all your configuration. A timestamped backup is saved before any reset.
- To add or remove services later, use **Reconfigure Services** from the main menu

---

## Disclaimer

THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## License

MIT License — Copyright (c) 2017 Tom Morgan
