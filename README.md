# Cloudflare Dynamic DNS Updater

## Overview

This lightweight image runs a script that is designed to update DNS records on Cloudflare based on changes in your public IP address.  
It's particularly useful for maintaining DNS records for services hosted at home or any environment with a dynamic IP address.

## Features

- **Dynamic IP Detection**: Automatically detects changes in the public IPv4 and IPv6 addresses.
- **Cloudflare API Integration**: Utilizes the Cloudflare API to update DNS records.
- **Flexible Configuration**: Easy-to-configure YAML file for the main config and JSON for specifying DNS records.
- **Logging and Debugging**: Detailed logging for troubleshooting and debugging.

## Setup

**For linux/amd64 and linux/arm64:**
1. Pull the image from Github:
```bash
docker pull ghcr.io/andriesmenze/cloudflare-ddns:latest
```
2. Start the container and mount the config an log folder to a docker volume or a folder on the host:
```bash
docker run \
-v /your/path/or/volume:/config \
-v /your/path/or/volume:/var/log/cloudflare-ddns \
--network host \
docker.io/library/cloudflare-ddns
```
3. Edit the cloudflare-ddns-config.yaml and dns-records.json file in the config folder and restart the container

**For other architectures:**
1. Clone the repository:
```bash
git clone https://github.com/Andriesmenze/Cloudflare-DDNS.git
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

## Cloudflare DDNS Configuration (`cloudflare-ddns-config.yaml`)
```yaml
# File: cloudflare-ddns-config.yaml

# Cloudflare API Token
# For more information visit https://developers.cloudflare.com/fundamentals/api/get-started/create-token/
# Can also be set/overridden with the ENV Variable CLOUDFLARE_API_TOKEN
API_TOKEN: "YOUR_CLOUDFLARE_API_TOKEN"

# Sleep Interval in seconds
# Can also be set/overridden with the ENV Variable SLEEP_INT
SLEEP_INTERVAL: 900 

# Log file location
# Can also be set/overridden with the ENV Variable LOG_FILE_LOCATION
LOG_FILE: "/var/log/cloudflare-ddns/update_dns.log"

# Dry run mode (true or false)
# Can also be set/overridden with the ENV Variable DRY_RUN_MODE
DRY_RUN: "false"
```

## DNS Records Configuration (`dns-records.json`)

**zone_id**  
https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/  

**record_type**  
Can be A for IPV4 or AAAA for IPV6.  

**subdomain**  
The subdomain is the optional part of your domain that comes before the main domain.  
If you're configuring a record for the root domain, you can leave this field empty.  

**proxied**  
Whether the record is being proxied through Cloudflare to receive the performance and security benefits of Cloudflare.  
Can be true or false, When not specified it defaults to true.  

**ttl**  
Time To Live (TTL) of the DNS record in seconds, When not specified it defaults to 1.  
Setting to 1 means 'automatic'. The value must be between 60 and 86400, with the minimum reduced to 30 for Enterprise zones.  

```json
{
  "ZONE_CONFIGS": [
    {
      "zone_id": "ZONE_ID_1",
      "record_type": "A",
      "subdomain": "",
      "proxied": "true",
      "ttl": "1"
    },
    {
      "zone_id": "ZONE_ID_2",
      "record_type": "AAAA",
      "subdomain": "",
      "proxied": "false",
      "ttl": "1"
    },
    {
      "zone_id": "ZONE_ID_2",
      "record_type": "AAAA",
      "subdomain": "www",
      "proxied": "true",
      "ttl": "1"
    }
  ]
}
```
## Contributions
Contributions are welcome! If you encounter issues or have suggestions, please open an issue or submit a pull request.

## License
This project is licensed under the GPL-3.0 license.
