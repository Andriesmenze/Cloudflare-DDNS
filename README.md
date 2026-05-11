# Cloudflare DDNS

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%203.0-blue.svg)](LICENSE)
[![Docker Image](https://ghcr.io/badge/ghcr.io/vandermerkprojects/cloudflare-ddns-container:latest)](https://ghcr.io/vandermerkprojects/cloudflare-ddns-container)

A lightweight Docker container that keeps your Cloudflare DNS records in sync with your dynamic public IP address — for both IPv4 (`A`) and IPv6 (`AAAA` ) records.

Ideal for self-hosted services at home or anywhere with a dynamic ISP address.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Docker Compose](#docker-compose)
- [Configuration](#configuration)
  - [cloudflare-ddns-config.yaml](#cloudflare-ddns-configyaml)
  - [dns-records.json](#dns-recordsjson)
  - [Environment Variables](#environment-variables)
- [Volume Permissions](#volume-permissions)
- [Building from Source](#building-from-source)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- Automatically detects your public **IPv4** and **IPv6** addresses
- Updates Cloudflare DNS records only when the IP actually changes
- Dual-source IP detection — Cloudflare trace endpoint with ipify fallback
- Per-record **alternate API tokens** for multi-zone setups
- **Dry-run mode** to test configuration without making changes
- Log rotation with configurable size and file-count limits
- Graceful shutdown on `SIGTERM` / `SIGINT`
- Runs as a **non-root user** inside the container

> **IPv6 note:** `AAAA` record updates require the container to run with `--network host` and the host to have a global IPv6 address.

---

## Quick Start

**1. Pull the image**

```bash
docker pull ghcr.io/vandermerkprojects/cloudflare-ddns-container:latest
```

**2. Start the container**

```bash
docker run -d \
  --name cloudflare-ddns \
  --network host \
  --restart unless-stopped \
  -v /your/config/path:/config \
  -v /your/log/path:/var/log/cloudflare-ddns \
  ghcr.io/vandermerkprojects/cloudflare-ddns-container:latest
```

**3. Edit the generated config files**

On the first run the container copies default config templates to your `/config` volume:

- `/config/cloudflare-ddns-config.yaml` — main settings
- `/config/dns-records.json` — which DNS records to manage

Fill in your Cloudflare API token and zone/record details, then restart the container.

---

## Docker Compose

```yaml
services:
  cloudflare-ddns:
    image: ghcr.io/vandermerkprojects/cloudflare-ddns-container:latest
    container_name: cloudflare-ddns
    restart: unless-stopped
    network_mode: host
    environment:
      TZ: Europe/Amsterdam
      # CLOUDFLARE_API_TOKEN: your_token_here  # optional: override config file
    volumes:
      - ./config:/config
      - ./logs:/var/log/cloudflare-ddns
```

---

## Configuration

### cloudflare-ddns-config.yaml

```yaml
# Cloudflare API token — see https://developers.cloudflare.com/fundamentals/api/get-started/create-token/
# Required permission: Zone › DNS › Edit
API_TOKEN: "YOUR_CLOUDFLARE_API_TOKEN"

# How often to check for IP changes (seconds)
SLEEP_INTERVAL: 900

# Log file path inside the container
LOG_FILE: "/var/log/cloudflare-ddns/update_dns.log"

# Set to "true" to simulate updates without changing any DNS records
DRY_RUN: "false"

# Enable automatic log rotation
LOG_ROTATION: "true"

# Maximum log file size before rotation (MB)
LOG_ROTATION_SIZE: 10

# Delete old rotated log files when the count exceeds LOG_FILES_AMOUNT
REMOVE_OLD_LOGS: "true"

# Number of rotated log files to keep
LOG_FILES_AMOUNT: 10
```

### dns-records.json

```json
{
  "RECORDS_CONFIG": [
    {
      "zone_id": "YOUR_ZONE_ID",
      "record_type": "A",
      "subdomain": "",
      "proxied": true,
      "ttl": 1,
      "alternate_api_token": ""
    },
    {
      "zone_id": "YOUR_ZONE_ID",
      "record_type": "AAAA",
      "subdomain": "www",
      "proxied": true,
      "ttl": 1,
      "alternate_api_token": ""
    }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `zone_id` | string | ✅ | Cloudflare Zone ID — found in the domain's **Overview** page. [Docs](https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/) |
| `record_type` | string | ✅ | `A` for IPv4, `AAAA` for IPv6 |
| `subdomain` | string | | Subdomain prefix (e.g. `www`). Leave empty for the root domain |
| `proxied` | boolean | | Route traffic through Cloudflare's proxy. Default: `true` |
| `ttl` | number | | DNS TTL in seconds. `1` = automatic. Range: 60–86400 (30+ for Enterprise). Default: `1` |
| `alternate_api_token` | string | | Per-record API token override. Leave empty to use the global token |

### Environment Variables

All settings in `cloudflare-ddns-config.yaml` can be overridden with environment variables:

| Environment Variable | Config Key | Description |
|----------------------|------------|-------------|
| `CLOUDFLARE_API_TOKEN` | `API_TOKEN` | Cloudflare API token |
| `SLEEP_INT` | `SLEEP_INTERVAL` | Check interval in seconds |
| `LOG_FILE_LOCATION` | `LOG_FILE` | Log file path |
| `DRY_RUN_MODE` | `DRY_RUN` | `true` to simulate without updating |
| `ENABLE_LOG_ROTATION` | `LOG_ROTATION` | Enable log rotation |
| `MAX_LOG_SIZE` | `LOG_ROTATION_SIZE` | Max log size in MB before rotation |
| `DELETE_OLD_LOGS` | `REMOVE_OLD_LOGS` | Auto-delete old rotated logs |
| `NUMBER_OF_LOG_FILES_TO_KEEP` | `LOG_FILES_AMOUNT` | How many rotated logs to keep |

---

## Volume Permissions

The container runs as user `ddns` (UID `1000`). If you use bind mounts, ensure the host directories are writable by UID `1000`:

```bash
sudo chown -R 1000:1000 ./config ./logs
```

Named Docker volumes are managed automatically and require no extra setup.

---

## Building from Source

For architectures not covered by the pre-built images:

```bash
git clone https://github.com/vandermerkprojects/cloudflare-ddns-container.git
cd cloudflare-ddns-container
docker buildx build --platform linux/amd64,linux/arm64 -t cloudflare-ddns .
```

---

## Troubleshooting

**Container starts but DNS records are never updated**
- Confirm your API token has `Zone › DNS › Edit` permission.
- Run with `DRY_RUN_MODE=true` and check the logs to verify the script is finding the right records.

**AAAA records are skipped**
- Verify the host has a global IPv6 address: `ip -6 addr show scope global`
- Make sure the container uses `network_mode: host`.

**Permission denied writing to config/log volumes**
- See [Volume Permissions](#volume-permissions) above.

**API token validation fails on every run**
- Tokens with an expiry date will cause the container to exit when they expire. Use tokens without an expiry or rotate them before they expire.

---

## Contributing

Contributions, bug reports, and feature requests are welcome.  
Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

---

## License

[GPL-3.0](LICENSE) © Andriesmenze
