# Mediabox v2.0

Mediabox is a modular, menu-driven Docker media server installer using whiptail. It expands on the original [mediabox](https://github.com/tom472/mediabox) with service selection, modular architecture, and a polished terminal UI.


## Attribution

- Original script and project inspiration by **Tom Morgan** ([tom472](https://github.com/tom472)).
- Original upstream project: https://github.com/tom472/mediabox

Current maintained project URL: https://github.com/mediaboxstack/Mediabox

---

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
* [Tdarr-Node distributed worker for Tdarr](https://docs.tdarr.io/docs/welcome/what/)
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

## Using Mediabox v2.0

### 8) Clone Mediabox v2.0
```bash
git clone https://github.com/mediaboxstack/Mediabox.git
cd Mediabox
```

### 9) Run the installer
```bash
./mediabox.sh
```

### Optional: run in debug mode
```bash
./mediabox.sh --debug
```

Debug mode increases troubleshooting visibility and writes additional debug entries.

---

## Legacy Migration Prep (safe archive path)

If you are migrating from a legacy Mediabox install (commonly `~/mediabox`) to a fresh clone of this repo, use the prep script first.

### Download and run

```bash
wget https://raw.githubusercontent.com/mediaboxstack/Mediabox/main/legacy-migration-prep.sh
chmod +x legacy-migration-prep.sh
./legacy-migration-prep.sh
```

### Common usage

```bash
# default legacy path: ~/mediabox
./legacy-migration-prep.sh

# custom legacy path
./legacy-migration-prep.sh /path/to/legacy/install

# checks only (no stop, no rename)
./legacy-migration-prep.sh --check-only
```

### What the script does

- Detects legacy install path (`~/mediabox` by default, or a custom positional path)
- Runs compatibility checks (Docker, Compose command, daemon access, writable parent directory, core tools)
- Verifies the target path is not the current Mediabox Git repo location (legacy safety check)
- Detects known services from:
  - `config/`, `appdata/`, and `data/` subdirectories
  - compose service names
  - running containers scoped by compose project label
- Stops the old stack with Compose (`down`) when compose command + file are available
- Safely archives the old install by renaming:
  - `<install_dir>` → `<install_dir>.backup-<timestamp>`
- Prints the backup path to use in import steps

### What the script does NOT do

- Does **not** delete data
- Does **not** run any `docker prune`
- Does **not** move media folders
- Does **not** clone repositories

### Recommended migration flow

1. Run `legacy-migration-prep.sh`.
2. Review compatibility check results and resolve any failures.
3. Let the script stop the old stack and archive the old directory.
4. Clone a fresh copy of this repo in your new target location.
5. Import your legacy config/app database data from the printed backup path.

### Installer log file

Mediabox v2.0 now writes a central log file at:

```bash
./install.log
```

The log includes:
- installer decisions (for example, selected actions/services)
- failures and error messages
- docker compose command output (`up`, `pull`, `down`, etc.)

---

## Main Menu

```
┌──────────────────────────────────┐
│      Mediabox v2.0 Installer     │
│                                  │
│  1. New Install                  │
│  2. Re-pull + relaunch containers│
│  3. Update media directories     │
│  4. Update service credentials   │
│  5. Relaunch containers only     │
│  6. Reconfigure Services         │
│  7. Status                       │
│  8. Reset                        │
│  9. Exit                         │
└──────────────────────────────────┘
```

- **New Install** - Full guided setup: select services, configure paths, deploy
- **Re-pull + relaunch containers** - Re-pull latest images for installed services and relaunch the stack
- **Update media directories** - Re-run media path prompts, regenerate `.env`, and relaunch with updated paths
- **Update service credentials** - Update managed credentials (PIA and/or daemon credentials where applicable) and refresh services
- **Relaunch containers only** - Restart existing containers without reconfiguring
- **Reconfigure Services** - Add or remove services from your running stack
- **Status** - View running containers and port mappings
- **Reset** - Stop everything and clean up generated files
- **Exit**

---

## What You'll Be Asked During New Install

1. **Media directory paths** — where your downloads, TV, movies, music, and misc files live (defaults provided)
2. **Which services to install** — a categorized checklist; select any combination, all services, or a preset stack (`Default Plex Stack` / `Default Jellyfin Stack`)
3. **PIA VPN credentials** — only if DelugeVPN is selected
4. **VPN server selection** — choose from bundled PIA OpenVPN configs
5. **Plex release type** — `public`, `latest`, or `plexpass` (only if Plex is selected)
6. **Plex GPU Transcoding** — optional GPU acceleration: none (software only), Intel GPU (Arc/QSV), or NVIDIA GPU (NVENC) (only if Plex is selected)
7. **Daemon credentials** — username/password for Deluge daemon and NZBGet access, and initial qBittorrent WebUI password bootstrap when not already configured (only if applicable services are selected)

### Preset Stacks

Mediabox v2.0 supports multiple configuration profiles in the installer:

- **Full (everything)**: selects all available service modules
- **Standard Plex stack**: preselected Plex-focused stack
- **Standard Jellyfin stack**: preselected Jellyfin-focused stack
- **Minimal (Plex only)**: installs only Plex
- **Minimal (Jellyfin only)**: installs only Jellyfin
- **Custom**: opens the full checklist to choose services manually

Preset module lists used by the standard profiles:

- **DEFAULT_PLEX**: `plex sonarr radarr prowlarr delugevpn overseerr tautulli homer watchtower portainer`
- **DEFAULT_JELLYFIN**: `jellyfin sonarr radarr prowlarr delugevpn overseerr homer watchtower portainer`

`tautulli` is intentionally included only in the Plex preset, since it is Plex-focused.

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
mediabox.sh           # Main entry point (menu system)
lib/
  common.sh           # Whiptail wrappers, logging, prerequisites
  config.sh           # System detection, config prompting, .env generation
  services.sh         # Module discovery, selection UI, dependency resolution
  compose.sh          # Docker-compose assembly & management
  postinstall.sh      # Post-deploy configuration hooks
modules/              # Primary service modules (+ optional variant fragments such as Plex GPU compose variants)
ovpn/                 # Bundled PIA OpenVPN configuration files
homer_assets/         # Homer dashboard templates and icons
```

Each service is a self-contained module in `modules/` (files identified by a `# module:` metadata header). Some additional files are variant compose fragments (for example, Plex GPU variants) used conditionally during compose assembly. During install, selected modules are merged into a single `docker-compose.yml` via `yq`.

---

## Notes

- After install, access the Homer dashboard at `http://<your-ip>`. The dashboard displays only the services you selected during install, organized into categories: Get It (downloaders), Manage It (library managers), Monitor It (monitoring), and Watch It (media servers).
- Portainer is available at `https://<your-ip>:9443` — set a password on first login
- qBittorrentVPN WebUI credentials are stored in `qbittorrentvpn/qBittorrent/config/qBittorrent.conf` (`WebUI\\Password_PBKDF2` or legacy `WebUI\\Password_ha1`).
- The `.env` file holds all your configuration. A timestamped backup is saved before any reset.
- To add or remove services later, use **Reconfigure Services** from the main menu. The Homer dashboard automatically updates to reflect your new selection.
- Cancelling any prompt safely returns you to the main menu

---

## Disclaimer

THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## License

MIT License

Copyright (c) 2026 Mediabox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
