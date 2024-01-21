# Cloudflare Dynamic DNS Updater

## Overview

This lightweight image runs a script that is designed to update DNS records on Cloudflare based on changes in your public IP address.  
It's particularly useful for maintaining DNS records for services hosted at home or any environment with a dynamic IP address.

## Features

- **Dynamic IP Detection**: Automatically detects changes in the public IPv4 and IPv6 addresses.
- **Cloudflare API Integration**: Utilizes the Cloudflare API to update DNS records.
- **Flexible Configuration**: Easy-to-configure YAML file for the main config and JSON for specifying DNS records.
- **Logging and Debugging**: Detailed logging for troubleshooting and debugging.

> [!NOTE]
> For IPv6, the container needs to be on the host network, and records get updated to the public IPv6 address of the container host.  

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
ghcr.io/andriesmenze/cloudflare-ddns
```
3. Edit the cloudflare-ddns-config.yaml and dns-records.json file in the config folder and restart the container

**For other architectures:**
1. Clone the repository:
```bash
git clone https://github.com/Andriesmenze/Cloudflare-DDNS.git
```
2. Navigate to the project directory:
```bash
cd Cloudflare-DDNS
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

**Environment Variables**  
Most settings can also be set/overrriden with the following environment variables.  
- **CLOUDFLARE_API_TOKEN**  
  This setting is used to specify the Cloudflare API token that the script will use to authenticate with the Cloudflare API when there is no alternate api token specified for the record.  
  The API token is required for making requests to Cloudflare's services.  
- **SLEEP_INT**  
  The sleep interval determines how often the script checks for changes in the public IP address and updates DNS records if necessary.  
  It's the time (in seconds) that the script waits before running again.  
- **LOG_FILE_LOCATION**  
  This setting specifies the file path where the script will write its log messages.  
  All the log entries, including information, warnings, and errors, will be recorded in this file.  
- **DRY_RUN_MODE**  
  Dry run mode is a feature that allows you to test the behavior without actually making changes to the Cloudflare DNS records.  
  When set to "true," the script will log the changes it would make, but it won't apply them.  
  This is useful for verifying settings without affecting the DNS records.  

**Docker Compose Example**
```Dockerfile
version: '3'
services:
  cloudflare-ddns:
    image: ghcr.io/andriesmenze/cloudflare-ddns:latest
    volumes:
      - /your/path/or/volume:/config
      - /your/path/or/volume:/var/log/cloudflare-ddns
    network_mode: host
```

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
Can be true or false, when not specified it defaults to true.  

**ttl**  
Time To Live (TTL) of the DNS record in seconds, when not specified it defaults to 1.  
Setting to 1 means 'automatic'. The value must be between 60 and 86400, with the minimum reduced to 30 for Enterprise zones.  

**alternate_api_token**  
Alternate api token for the DNS record, when not specified the API Token from the cloudflare-ddns-config.yaml or ENV variable is used.  

```json
{
  "RECORDS_CONFIG": [
    {
      "zone_id": "ZONE_ID_1",
      "record_type": "A",
      "subdomain": "",
      "proxied": "true",
      "ttl": "1",
      "alternate_api_token": "ALTERNATE_CLOUDFLARE_API_TOKEN"
    },
    {
      "zone_id": "ZONE_ID_2",
      "record_type": "AAAA",
      "subdomain": "",
      "proxied": "false",
      "ttl": "1",
      "alternate_api_token": "ALTERNATE_CLOUDFLARE_API_TOKEN"
    },
    {
      "zone_id": "ZONE_ID_2",
      "record_type": "AAAA",
      "subdomain": "www",
      "proxied": "true",
      "ttl": "1",
      "alternate_api_token": "ALTERNATE_CLOUDFLARE_API_TOKEN"
    }
  ]
}
```
## Contributions
Contributions are welcome! If you encounter issues or have suggestions, please open an issue or submit a pull request.

## License
This project is licensed under the GPL-3.0 license.
