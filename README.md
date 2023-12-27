# Cloudflare Dynamic DNS Updater

## Overview

This script is designed to update DNS records on Cloudflare dynamically based on changes in your public IP address.
It's particularly useful for maintaining DNS records for services hosted at home or any environment with a dynamic IP address.

## Features

- **Dynamic IP Detection**: Automatically detects changes in the public IPv4 and IPv6 addresses.
- **Cloudflare API Integration**: Utilizes the Cloudflare API to update DNS records.
- **Flexible Configuration**: Easy-to-configure YAML file for specifying DNS records and other settings.
- **Logging and Debugging**: Detailed logging for troubleshooting and debugging.

## Setup

1. Clone the repository:
```bash
    git clone https://github.com/yourusername/cloudflare-dynamic-dns.git
```
2. Navigate to the project directory:
```bash
    cd cloudflare-dynamic-dns
```
3. Build the image:
```bash
    docker buildx build -t cloudflare-ddns .
```
4. Start the container and mount the config an log folder to a docker volume or a folder on the host:
```bash
    docker run \
    -v /your/path/or/volume:/config \
    -v /your/path/or/volume:/var/log/cloudflare-ddns \
    --network host \
    docker.io/library/cloudflare-ddns
```
5. Edit the cloudflare-ddns-config.yaml and dns-records.json file in the config folder and restart the container

### Cloudflare DDNS Configuration (`cloudflare-ddns-config.yaml`)
```yaml
# File: cloudflare-ddns-config.yaml

# Cloudflare API Token
# For more information visit https://developers.cloudflare.com/fundamentals/api/get-started/create-token/
# Can also be set with the ENV Variable CLOUDFLARE_API_TOKEN
API_TOKEN: "YOUR_CLOUDFLARE_API_TOKEN"

# Sleep Interval in seconds
# Can also be set with the ENV Variable SLEEP_INT
SLEEP_INTERVAL: 900 

# Log file location
# Can also be set with the ENV Variable LOG_FILE_LOCATION
LOG_FILE: "/var/log/cloudflare-ddns/update_dns.log"
```

### DNS Records Configuration (dns-records.json)
```json
{
  "ZONE_CONFIGS": [
    {
      "zone_id": "ZONE_ID_1",
      "record_type": "A",
      "record_name": "example.com",
      "subdomain": "",
      "proxied": "true"
    },
    {
      "zone_id": "ZONE_ID_2",
      "record_type": "AAAA",
      "record_name": "example.org",
      "subdomain": "",
      "proxied": "false"
    },
    {
      "zone_id": "ZONE_ID_2",
      "record_type": "AAAA",
      "record_name": "example.org",
      "subdomain": "www",
      "proxied": "true"
    }
  ]
}
```
