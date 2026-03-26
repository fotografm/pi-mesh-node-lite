# pi-mesh-node-lite

A lightweight Reticulum/LXMF mesh node running on a Raspberry Pi Zero 2W, serving a browser-based interface via a dedicated WiFi hotspot.

## Features

- **LXMF Chat** — send and receive messages with other Reticulum/LXMF nodes on the mesh
- **Live Announces** — displays nearby mesh nodes with hop count and time-ago
- **Unread indicators** — pulsing envelope and blue dot notification on incoming messages
- **Auto-announce** — broadcasts presence every 15 minutes; manual announce button
- **Hash deduplication** — merges multiple LXMF addresses from the same MeshChat node into a single conversation
- **Node name sanitisation** — strips binary garbage from announce display names
- **Landing page** — served on port 80 with clock, quick notes widget, and shutdown button
- **Keep-style notes** — multi-note app with search and highlighted results

## Hardware

- Raspberry Pi Zero 2W
- RAK4631 RNode (LoRa 869.525 MHz, SF10, 250 kHz BW)
- Waveshare 4-port USB hub HAT
- DS3231 RTC module (I2C)
- USB ethernet adapter (optional, for setup)

## Ports

| Port | Service |
|------|---------|
| 80   | Landing page |
| 8082 | LXMF/Announces browser UI |
| 8083 | WebSocket — live events |

## Stack

- **Python 3** — `rns==1.1.3`, `LXMF==0.9.3`, `websockets==16.0`, `msgpack==1.1.2`
- **Reticulum Network Stack** — transport and LXMF messaging
- Vanilla HTML/JS — no framework dependencies

## Setup

See `SETUP.md` for complete step-by-step instructions covering fresh Bookworm Lite install through to running services.

Scripts:
- `setup-pi-1.sh` — run before first reboot
- `setup-pi-2.sh` — run after first reboot
- `setup-pi-3.sh` — verification checks
- `setup-deploy.sh` — deploy updated files from desktop to Pi

## License

MIT
