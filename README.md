# pi-mesh-node

A portable Reticulum mesh node and SDR receiver based on the Raspberry Pi Zero 2W.
Serves a browser-based interface over a local WiFi hotspot — no internet connection
required once deployed.

Tested on: **Raspberry Pi OS Bookworm Lite 32-bit**

---

## Features

- **Landing page** — clock, quick notepad, links to all tools, shutdown button
- **SDR waterfall** — real-time spectrum display from an RTL-SDR dongle
- **Reticulum terminal** — live LXMF messaging and announce monitor
- **RNS live map** — dartboard visualiser of mesh nodes by hop distance
- **CLI terminal** — browser-based shell (xterm.js PTY)
- **RNode noise graph** — LoRa interface noise floor monitor

---

## Hardware

| Item | Notes |
|------|-------|
| Raspberry Pi Zero 2W | Main compute board |
| RNode LoRa device | Heltec LoRa32 v3 or RAK4631 on `/dev/ttyACM0` |
| RTL-SDR dongle | NESDR SMArt v5 or similar (Realtek RTL2832U) |
| Waveshare 4-port USB hub HAT | Connects RNode + RTL-SDR + ethernet adapter |
| RTL8152 USB ethernet adapter | For SSH during setup (optional after hotspot works) |
| DS3231 RTC module | I2C real-time clock, keeps time without NTP |

---

## Port map

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 80   | HTTP | landing-server | Landing page, notes, shutdown |
| 8080 | HTTP | sdr-ws (Rust) | SDR waterfall page |
| 8081 | WS   | sdr-ws (Rust) | Binary spectrum frames |
| 8082 | HTTP | rns-web (Python) | LXMF + announces page |
| 8083 | WS   | rns-web (Python) | Live LXMF + announce events |
| 8084 | HTTP | rns-web (Python) | Combined iframe view |
| 8085 | WS   | rns-web (Python) | PTY terminal (xterm.js) |
| 8086 | HTTP | rns-map (Python) | Live RNS dartboard map |

---

## Architecture

```
RNode (LoRa)    RTL-SDR dongle
     |                |
   rnsd           sdr-ws (Rust binary)
     |            http://pi:8080  ws://pi:8081
     |
  rns-web.py  ←── shared RNS instance
  http://pi:8082   ws://pi:8083
  http://pi:8084   ws://pi:8085 (terminal)
     |
  rns-map/rns_map.py  ←── shared RNS instance
  http://pi:8086
     |
  landing-server.py
  http://pi:80
```

**Two-machine workflow:** The Rust SDR binary (`sdr-ws`) is cross-compiled on a
desktop Linux machine, then copied to the Pi. The Pi itself never needs a Rust
toolchain. All other software runs as Python.

---

## Repository structure

```
pi-mesh-node/
  landing-server.py     Landing page HTTP server
  landing.html          Landing page UI
  notes.html            Notes app UI
  rns-web.py            Reticulum/LXMF web bridge + terminal server
  rns-index.html        LXMF + announces browser UI
  sdr-ws/
    Cargo.toml          Rust dependencies
    src/
      main.rs           RTL-SDR spectrum server (cross-compile on desktop)
      index.html        SDR waterfall UI (compiled into binary)
  services/
    landing.service     systemd unit for landing-server.py
    rnsd.service        systemd unit for Reticulum daemon
    rns-web.service     systemd unit for rns-web.py
    rns-map.service     systemd unit for rns-map (separate repo)
    sdr-ws.service      systemd unit for Rust SDR binary
  setup-desktop.sh      Desktop: install Rust toolchain + cross-compile sdr-ws
  setup-deploy.sh       Desktop: transfer built files to Pi
  setup-pi-1.sh         Pi: system setup + RTL-SDR + hotspot (reboot after)
  setup-pi-2.sh         Pi: Python venv + services + RTC (reboot after)
  setup-pi-3.sh         Pi: verification checks
  README.md
  .gitignore
```

**rns-map is a separate repository** cloned during setup:
`https://github.com/fotografm/rns-map`

---

## Installation

### Overview

1. Flash Pi with Raspberry Pi OS Bookworm Lite 32-bit
2. Run `setup-pi-1.sh` on the Pi → reboot
3. Run `setup-desktop.sh` on the desktop to cross-compile `sdr-ws`
4. Run `setup-deploy.sh` on the desktop to transfer files to the Pi
5. Run `setup-pi-2.sh` on the Pi → reboot
6. Run `setup-pi-3.sh` on the Pi to verify everything

---

### Step 1 — Flash the Pi

Use **Raspberry Pi Imager** with these settings:

- OS: **Raspberry Pi OS Bookworm Lite (32-bit)**
- Hostname: `raspi20`
- Username: `user`
- WiFi: your home network (for initial SSH access)
- SSH: enabled (password authentication)

> **Do not use Trixie (Debian 13)** — headless WiFi/SSH via Imager is broken
> for Trixie. Bookworm only.

---

### Step 2 — First Pi setup

SSH into the Pi, clone this repo, and run part 1:

```bash
git clone https://github.com/fotografm/pi-mesh-node.git ~
bash ~/setup-pi-1.sh
```

This installs system dependencies, configures RTL-SDR udev rules, sets up the
WiFi hotspot, and configures the DS3231 RTC. You will be prompted for a hotspot
SSID and password.

**Reboot after this step:**

```bash
sudo reboot
```

---

### Step 3 — Cross-compile sdr-ws on desktop

On your **desktop Linux machine** (Ubuntu 22.04 or later), clone the repo and
build the Rust binary:

```bash
git clone https://github.com/fotografm/pi-mesh-node.git ~/pi-mesh-node
bash ~/pi-mesh-node/setup-desktop.sh
```

This installs the Rust ARM musl cross-compilation toolchain and builds
`sdr-ws` for the Pi Zero 2W. The binary appears at:

```
~/pi-mesh-node/sdr-ws/target/arm-unknown-linux-musleabihf/release/sdr-ws
```

> **Why cross-compile?** The Pi Zero 2W has 512 MB RAM and a slow CPU. Compiling
> Rust natively on the Pi would take 30+ minutes and may run out of memory.
> Cross-compilation on a desktop takes under 2 minutes.

---

### Step 4 — Deploy files to Pi

From the desktop, transfer all files to the Pi:

```bash
bash ~/pi-mesh-node/setup-deploy.sh
```

Edit `PI_IP` at the top of `setup-deploy.sh` to match your Pi's IP address before running.

---

### Step 5 — Second Pi setup

SSH back into the Pi after the first reboot and run part 2:

```bash
bash ~/setup-pi-2.sh
```

This creates the Python venv, installs Reticulum/LXMF dependencies, writes the
Reticulum config, downloads xterm.js, installs all systemd services, and clones
the rns-map repo.

**Reboot after this step:**

```bash
sudo reboot
```

---

### Step 6 — Verify

After the second reboot, run the verification script:

```bash
bash ~/setup-pi-3.sh
```

This checks all services are running, all ports are listening, the RTL-SDR
dongle is detected, and the LXMF identity has been created.

---

## Accessing the interface

Connect your phone or laptop to the Pi's WiFi hotspot, then open:

| URL | Description |
|-----|-------------|
| `http://10.42.0.1` | Landing page |
| `http://10.42.0.1:8080` | SDR waterfall |
| `http://10.42.0.1:8082` | LXMF + announces |
| `http://10.42.0.1:8084` | Combined view (SDR + LXMF) |
| `http://10.42.0.1:8086` | RNS live map |

Or substitute the Pi's IP address if accessing over your home network.

---

## Common pitfalls

**RTL-SDR dongle not detected**
The DVB kernel modules must be blacklisted or they claim the dongle before
`sdr-ws` can open it. `setup-pi-1.sh` handles this, but it requires a reboot
to take effect. Check with `lsusb | grep 0bda`.

**sdr-ws crashes immediately**
The dongle may already be claimed by a DVB module. Check with
`lsmod | grep dvb` — if anything shows, the blacklist did not take effect.
Reboot and try again.

**Permission denied on /dev/ttyACM0**
Your user is not in the `dialout` group. Fix with:
```bash
sudo usermod -aG dialout user
```
Then log out and back in.

**All nodes appear on ring 1 of the RNS map**
This means hop counts are not being read correctly. Check that rnsd is running
and that rns-map started after rnsd (`journalctl -u rns-map -n 20`).

**Landing page not loading (port 80)**
Port 80 requires root or a special capability to bind. The landing service
runs as `user` — this works on Raspberry Pi OS but may fail on other distros.
Check with `journalctl -u landing -n 20`.

**LXMF identity warning**
`~/lxmf-storage/identity` is your permanent mesh address. If you lose it you
lose your address. Back it up:
```bash
scp user@<pi-ip>:~/lxmf-storage/identity ~/backup-lxmf-identity
```

---

## Service management

```bash
sudo systemctl status landing rnsd rns-web rns-map sdr-ws
sudo systemctl restart <service>
journalctl -u <service> -f
```

---

## Dependencies

### Python venv (`~/rns-web-venv`)

| Package   | Version  |
|-----------|----------|
| rns       | 1.1.3    |
| LXMF      | 0.9.3    |
| websockets | 16.0    |
| msgpack   | 1.1.2    |
| peewee    | <4.0.0   |

### Rust (`sdr-ws`)

| Crate            | Version |
|------------------|---------|
| rtl-sdr-rs       | 0.1     |
| rustfft          | 6       |
| tokio            | 1       |
| tokio-tungstenite | 0.27   |
| futures-util     | 0.3     |
| num-complex      | 0.4     |
| serde / serde_json | 1     |

---

## Licence

MIT
