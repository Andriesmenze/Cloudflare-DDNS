#!/bin/bash

# Source the configuration files
EXAMPLE_CONFIG="/app/cloudflare-ddns-config.yaml"
CONFIG="/config/cloudflare-ddns-config.yaml"

# Set Log file location and rotation settings
LOG_FILE="${LOG_FILE_LOCATION:-$(yq eval '.LOG_FILE' "$CONFIG")}"
LOG_ROTATION="${ENABLE_LOG_ROTATION:-$(yq eval '.LOG_ROTATION' "$CONFIG")}"
LOG_ROTATION_SIZE="${MAX_LOG_SIZE:-$(yq eval '.LOG_ROTATION_SIZE' "$CONFIG")}"
REMOVE_OLD_LOGS="${DELETE_OLD_LOGS:-$(yq eval '.REMOVE_OLD_LOGS' "$CONFIG")}"
LOG_FILES_AMOUNT="${NUMBER_OF_LOG_FILES_TO_KEEP:-$(yq eval '.LOG_FILES_AMOUNT' "$CONFIG")}"

# Check if LOG_FILE is not specified/invalid and set default
if [ -z "$LOG_FILE" ] || [ "$LOG_FILE" = "null" ]; then
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [info] Log file location not specified, defaulting to /var/log/cloudflare-ddns/update_dns.log"
    LOG_FILE="/var/log/cloudflare-ddns/update_dns.log"
elif [ ! -d "$(dirname "$LOG_FILE")" ]; then
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [warning] Invalid path for LOG_FILE. defaulting to /var/log/cloudflare-ddns/update_dns.log."
    LOG_FILE="/var/log/cloudflare-ddns/update_dns.log"
fi

# Function to log startup messages before log_message is defined
startup_log() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] $1"
    
    # Print log entry to console
    echo "$log_entry"
    
    # Log to file
    echo "$log_entry" >> "$LOG_FILE" 2>&1
}

# Check if log config values not specified/invalid and set defaults
if [ -z "$LOG_ROTATION" ] || [ "$LOG_ROTATION" = "null" ]; then
    startup_log "[info] LOG_ROTATION option not specified, defaulting to true"
    LOG_ROTATION="true"
elif [[ ! "$DRY_RUN" =~ ^[Tt]rue$|^[Ff]alse$ ]]; then
    startup_log "[warning] Invalid value for LOG_ROTATION. defaulting to true."
    LOG_ROTATION="true"
fi
if [[ "$LOG_ROTATION" == *"true"* ]]; then
    if [ -z "$LOG_ROTATION_SIZE" ] || [ "$LOG_ROTATION_SIZE" = "null" ]; then
        startup_log "[info] LOG_ROTATION_SIZE not specified, defaulting to 10MB"
        LOG_ROTATION_SIZE=10
    elif ! [[ "$LOG_ROTATION_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        startup_log "[warning] LOG_ROTATION_SIZE invalid, defaulting to 10MB"
        LOG_ROTATION_SIZE=10
    fi
fi
if [ -z "$REMOVE_OLD_LOGS" ] || [ "$REMOVE_OLD_LOGS" = "null" ]; then
    startup_log "[info] REMOVE_OLD_LOGS option not specified, defaulting to true"
    REMOVE_OLD_LOGS="true"
elif [[ ! "$REMOVE_OLD_LOGS" =~ ^[Tt]rue$|^[Ff]alse$ ]]; then
    startup_log "[warning] Invalid value for REMOVE_OLD_LOGS. defaulting to true."
    REMOVE_OLD_LOGS="true"
fi
if [[ "$REMOVE_OLD_LOGS" == *"true"* ]]; then
    if [ -z "$LOG_FILES_AMOUNT" ] || [ "$LOG_FILES_AMOUNT" = "null" ]; then
        startup_log "[info] LOG_FILES_AMOUNT not specified, defaulting to 10"
        LOG_FILES_AMOUNT=10
    elif ! [[ "$LOG_FILES_AMOUNT" =~ ^[1-9][0-9]*$ ]]; then
        startup_log "[warning] LOG_FILES_AMOUNT invalid, defaulting to 10"
        LOG_FILES_AMOUNT=10
    fi
fi

# Function to log messages and echo to the console
log_message() {
    local max_log_size
    max_log_size=$((LOG_ROTATION_SIZE * 1048576))
    local timestamp
    local log_file_size
    local previous_file
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] $1"
    
    # Print log entry to console
    echo "$log_entry"
    
    # Log to file
    echo "$log_entry" >> "$LOG_FILE" 2>&1
    
    if [[ "${LOG_ROTATION,,}" == "true" ]]; then
        # Rotate log file if it exceeds a certain size
        log_file_size=$(du -b "$LOG_FILE" | cut -f1)
        if [ "$log_file_size" -gt "$max_log_size" ]; then
            previous_file="$LOG_FILE.$(date +%Y%m%d%H%M%S)"
            mv "$LOG_FILE" "$previous_file"
            echo "[info] Log file rotated. Old log file: $previous_file" >> "$LOG_FILE" 2>&1
        fi
    fi
    
    if [[ "${REMOVE_OLD_LOGS,,}" == "true" ]]; then
        # Remove old log files if there are more than LOG_FILES_AMOUNT
        log_files_count=$(find "$(dirname "$LOG_FILE")" -maxdepth 1 -type f -name "$(basename "$LOG_FILE").*" 2>/dev/null | wc -l)

        if [ "$log_files_count" -gt "$LOG_FILES_AMOUNT" ]; then
            mapfile -t old_files < <(find "$(dirname "$LOG_FILE")" -maxdepth 1 -type f -name "$(basename "$LOG_FILE").*" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2- | tail -n +$((LOG_FILES_AMOUNT + 1)))

            # Check if old_files array is non-empty before attempting removal
            if [[ "${#old_files[@]}" -gt 0 ]]; then
                rm "${old_files[@]}"
                echo "[info] Removed old log files. Count: $log_files_count, Keeping: $LOG_FILES_AMOUNT" >> "$LOG_FILE" 2>&1
            fi
        fi
    fi
}

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    log_message "[error] curl is not installed." >&2
    exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    log_message "[error] yq is not installed." >&2
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_message "[error] jq is not installed." >&2
    exit 1
fi

# Check if awk is installed
if ! command -v awk &> /dev/null; then
    log_message "[error] awk is not installed." >&2
    exit 1
fi

# Convert YAML to JSON using awk, tr, and sed
yaml_to_json() {
    local yaml_file=$1
    local json

    json=$(awk '
        BEGIN {
            FS=": ";
            print "{"
        }
        !/^[[:space:]]*#/ && NF {
            gsub(/^ +| +$/, "", $1);
            gsub(/^ +| +$/, "", $2);

            if ($2 == "") {
                printf("\"%s\": {", $1);
            } else {
                gsub(/^"|"$/, "", $2);
                printf("\"%s\": \"%s\",", $1, $2);
            }
        }
        END {
            if (NR > 0) {
                sub(/,$/, "");
                print "\n}"
            } else {
                print "}"
            }
        }
    ' "$yaml_file" | tr -d '\n' | sed 's/,\s*}$/}/')

    echo "$json"
}

# Function to get the current public IP address
get_public_ip() {
    local version=$1
    local ip_ipify
    local ip_cloudflare

    case "$version" in
        "v4")
            ip_ipify=$(curl -s https://api.ipify.org?format=text)
            ip_cloudflare=$(curl -s https://1.1.1.1/cdn-cgi/trace | grep "ip=" | cut -d'=' -f2)
            ;;
        "v6")
            ip_ipify=$(curl -s https://api64.ipify.org?format=text)
            ip_cloudflare=$(curl -s 'https://[2606:4700:4700::1111]/cdn-cgi/trace' | grep "ip=" | cut -d'=' -f2)
            ;;
        *)
            # Log invalid ip version
            log_message "[error] Invalid ip version."
            ;;
    esac

    # Check if both responses are not empty
    if [ -n "$ip_ipify" ] && [ -n "$ip_cloudflare" ]; then
        # Check if the IP addresses are the same
        if [ "$ip_ipify" = "$ip_cloudflare" ]; then
            echo "$ip_cloudflare"
        else
            # Log and use Cloudflare's IP address when they are different
            echo "$ip_cloudflare"
        fi
    elif [ -n "$ip_cloudflare" ]; then
        # Use IP address from Cloudflare when api.ipify.org's response is empty
        echo "$ip_cloudflare".
    elif [ -n "$ip_ipify" ]; then
        # Use IP address from api.ipify.org when Cloudflare's response is empty
        echo "$ip_ipify"
    else
        # Log and return error when both responses are empty
        log_message "[error] Unable to retrieve public IP address."
    fi
}

# Function to test Cloudflare API token
test_api_token() {
    local response
    local TOKEN=$1
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $TOKEN")

    # Check for errors in the response
    if [[ $(echo "$response" | jq -r '.errors | length') -gt 0 ]]; then
        echo "[error] Error testing API token: $response"
    else
        echo "[info] The Cloudflare API token is valid."
    fi
}

# Function to get Zone name
get_zone_name() {
    local response    

    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json")

    if [[ $(echo "$response" | jq -r '.errors | length') -gt 0 ]]; then
        echo "[error] Failed to get zone name for $zone_id: $response"
    else
        jq -r '.result.name' <<< "$response"
    fi
}

# Function to get DNS record
get_dns_record_value() {
    local full_record_name="${subdomain:+"$subdomain."}$zone_name"
    local response

    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$record_type&name=$full_record_name" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json")

    if [[ $(echo "$response" | jq -r '.errors | length') -gt 0 ]]; then
        echo "[error] Failed to get value for DNS record $full_record_name type $record_type in zone $zone_name: $response"
    else
        jq -r '.result[] | "\(.content) \(.id) "' <<< "$response"
    fi
}

# Function to update DNS record
update_dns_record() {
    local new_ip=$1
    local full_record_name="${subdomain:+"$subdomain."}$zone_name"
    local response

    if [[ "${DRY_RUN,,}" == "true" ]]; then
        log_message "Dry run mode: Simulating DNS record update for ${subdomain:+"$subdomain."}$zone_name type $record_type in zone $zone_name."
        return  # Exit the function without making actual updates
    fi

    response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{
            "content": "'$new_ip'",
            "name": "'$full_record_name'",
            "proxied": '$proxied',
            "type": "'$record_type'",
            "ttl": "'$ttl'"
        }')

    # Check for errors in the response
    if [[ $(echo "$response" | jq -r '.errors | length') -gt 0 ]]; then
        echo "[error] Error updating DNS record for ${subdomain:+"$subdomain."}$zone_name type $record_type in Zone $zone_name: $response"
    else
        echo "[info] DNS record updated successfully for ${subdomain:+"$subdomain."}$zone_name type $record_type in Zone $zone_name."
    fi
}

check_and_update_record() {
    # Check if the public IPv4 is different from the current DNS record value
    local public_ip=$1
    output1=""
    output2=""
    if [ "$public_ip" != "$record_content" ]; then
        output1="[info] Current value is different from Public IP, updating DNS Record for record ${subdomain:+"$subdomain."}$zone_name type $record_type in zone $zone_name"
        # Check if proxied is not set and assign a default value of true
        if [ -z "$proxied" ] || [ "$proxied" = "null" ]; then
            log_message "[info] proxied not set for ${subdomain:+"$subdomain."}$zone_name type $record_type in Zone $zone_name, defaulting to true."
            proxied="true"
        fi
        # Check if ttl is not set and assign a default value of 1
        if [ -z "$ttl" ] || [ "$ttl" = "null" ]; then
            log_message "[info] ttl not set for ${subdomain:+"$subdomain."}$zone_name type $record_type in Zone $zone_name, defaulting to 1(Auto)."
            ttl="1"
        fi
        output2=$(update_dns_record "$public_ip")
    else
        output1="[info] Public IP is the same as current value, skipping update for ${subdomain:+"$subdomain."}$zone_name in Zone $zone_name."
    fi
}

# Signal handler function
cleanup() {
    log_message "[info] Received termination signal, exiting."
    exit 0
}

# Register the cleanup function to handle termination signals
trap cleanup SIGTERM SIGINT

# Create config files if they don't exist
if [ ! -f /config/cloudflare-ddns-config.yaml ]; then
    cp /app/cloudflare-ddns-config.yaml /config/cloudflare-ddns-config.yaml
fi
if [ ! -f /config/dns-records.json ]; then
    cp /app/dns-records.json /config/dns-records.json
fi

# Source settings from the configuration file and/or ENV
API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(yq eval '.API_TOKEN' "$CONFIG")}"
SLEEP_INTERVAL="${SLEEP_INT:-$(yq eval '.SLEEP_INTERVAL' "$CONFIG")}"
DRY_RUN="${DRY_RUN_MODE:-$(yq eval '.DRY_RUN' "$CONFIG")}"

# Load the JSON file into a variable
DNS_RECORDS_JSON=$(cat /config/dns-records.json)

# Check if RECORDS_CONFIG key exists in JSON
if jq -e '.RECORDS_CONFIG' <<< "$DNS_RECORDS_JSON" >/dev/null; then
    # Convert JSON array to Bash array
    IFS=$'\n' read -d '' -ra RECORDS_CONFIG < <(echo "$DNS_RECORDS_JSON" | jq -c '.RECORDS_CONFIG[]')
    
    # Check if the array is not empty
    if [ ${#RECORDS_CONFIG[@]} -eq 0 ]; then
        log_message "[error] No records found in the RECORDS_CONFIG array in dns-records.json, exiting."
        exit 1
    fi
else
    log_message "[error] RECORDS_CONFIG key not found in dns-records.json, exiting."
    exit 1
fi

# Converting config files to json
example_config_json=$(yaml_to_json "$EXAMPLE_CONFIG")
config_json=$(yaml_to_json "$CONFIG")

# Extracting the keys from the json files
keys_example_config_json=$(echo "$example_config_json" | jq -r 'keys_unsorted | .[]')
keys_config_json=$(echo "$config_json" | jq -r 'keys_unsorted | .[]')

# Use diff to find missing keys in config_json
missing_keys=$(comm -23 <(echo "$keys_example_config_json" | sort) <(echo "$keys_config_json" | sort))

# Comparing the config files for missing settings
if [ -n "$missing_keys" ]; then
    formatted_missing_keys=$(echo "$missing_keys" | tr '\n' ',' | sed 's/,$//;s/,/, /g')
    log_message "[warning] Missing settings found in the config file."
    log_message "[warning] Missing settings: $formatted_missing_keys"
else
    log_message "[info] No missing settings found in the config file."
fi

# Check if config values not specified/invalid and set defaults
if [ -z "$DRY_RUN" ] || [ "$DRY_RUN" = "null" ]; then
    log_message "[info] Dry run option not specified, defaulting to false"
    DRY_RUN="false"
elif [[ ! "$DRY_RUN" =~ ^[Tt]rue$|^[Ff]alse$ ]]; then
    log_message "[warning] Invalid value for DRY_RUN. defaulting to false."
    DRY_RUN="false"
fi
if [ -z "$SLEEP_INTERVAL" ] || [ "$SLEEP_INTERVAL" = "null" ]; then
    log_message "[info] Sleep interval not specified, defaulting to 900 seconds"
    SLEEP_INTERVAL="900"
elif ! [[ "$SLEEP_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    log_message "[warning] Invalid value for SLEEP_INTERVAL. defaulting to 900."
    SLEEP_INTERVAL="900"
fi

# Check if the container has an IPv6 address
local_ipv6_address=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | cut -d'/' -f1)
if [ -z "$local_ipv6_address" ]; then
    if grep -q '"record_type": "AAAA"' dns-records.json; then
        log_message "[error] Container does not have an IPv6 address, make sure the host has IPv6 enabled and the container is on the host network."
    else
        log_message "[info] Container does not have an IPv6 address."
    fi
    ipv6="false"
else
    ipv6="true"
fi

log_message "[info] Script has initialised"
# Main loop
while true; do

    # Test the cloudflare API Token
    token_status=$(test_api_token "$API_TOKEN")
    log_message "$token_status"
    if [[ "$token_status" != *"error"* && -n "$API_TOKEN" && "$API_TOKEN" != "YOUR_CLOUDFLARE_API_TOKEN" ]]; then

        # Retrieve the current public IPv4 and IPv6 addresses
        current_ipv4=$(get_public_ip "v4")
        log_message "[info] Current public IPV4 address is $current_ipv4"
        if [[ "$ipv6" == *"true"* ]]; then
            current_ipv6=$(get_public_ip "v6")
            log_message "[info] Current public IPV6 address is $current_ipv6"
        fi

        # Iterate through each configured DNS record
        for record in "${RECORDS_CONFIG[@]}"; do
            zone_id=$(echo "$record" | jq -r '.zone_id')
            record_type=$(echo "$record" | jq -r '.record_type')
            proxied=$(echo "$record" | jq -r '.proxied')
            ttl=$(echo "$record" | jq -r '.ttl')
            subdomain=$(echo "$record" | jq -r '.subdomain')
            alternate_api_token=$(echo "$record" | jq -r '.alternate_api_token')

            if [[ -z "$alternate_api_token" || "$alternate_api_token" = "null" || "$alternate_api_token" == "ALTERNATE_CLOUDFLARE_API_TOKEN" ]]; then
                log_message "[info] No alternate API token speciefd using token from config or env variable."
            else
                record_token_status=$(test_api_token "$alternate_api_token")
                log_message "$record_token_status"
                if [[ "$record_token_status" != *"error"* ]]; then
                    global_token=$API_TOKEN
                    API_TOKEN=$alternate_api_token
                    using_alt_token="true"
                else
                    log_message "[error] Alternate api token invalid, trying global token from config or env variable."
                fi
            fi

            # Get DNS zone name
            zone_name=$(get_zone_name)
            if [[ "$zone_name" == *"error"* ]]; then
                log_message "$zone_name"
                log_message "[error] Failed to retrieve zone name for zoneid $zone_id, skipping record update."
                continue
            else
                log_message "[info] Retrieved zone name for zoneid $zone_id: $zone_name"
            fi

            # Get DNS record value
            dns_record_value=$(get_dns_record_value)
            if [[ "$dns_record_value" == *"error"* ]]; then
                log_message "$dns_record_value"
                log_message "[error] Failed to retrieve DNS record value for record type $record_type in zone $zone_name, skipping record update."
                continue
            fi
            IFS=" " read -r record_content record_id <<< "$dns_record_value"
            if [ -z "$record_content" ] || [ "$record_content" = "null" ]; then
                log_message "[error] Failed to retrieve DNS record value for record type $record_type in zone $zone_name, skipping record update."
                continue
            else
                log_message "[info] Retrieved DNS record value for record ${subdomain:+"$subdomain."}$zone_name type $record_type in zone $zone_name: $record_content"
            fi
            # Check and update the record
            case "$record_type" in
                "A")
                    check_and_update_record "$current_ipv4"
                    for output in "$output1" "$output2"; do
                        if [ -n "$output" ]; then
                            log_message "$output"
                        fi
                    done
                    ;;
                "AAAA")
                    if [[ "$ipv6" == *"true"* ]]; then
                        check_and_update_record "$current_ipv6"
                        for output in "$output1" "$output2"; do
                            if [ -n "$output" ]; then
                                log_message "$output"
                            fi
                        done
                    else
                        log_message "[warning] Container does not have an IPv6 address, skipping record."
                    fi
                    ;;
                *)
                    # Log if the record type is unsupported
                    log_message "[error] Unsupported record type: $record_type, skipping update for ${subdomain:+"$subdomain."}$zone_name in Zone $zone_name."
                    continue
                    ;;
            esac
            if [[ "$using_alt_token" == *"true"* ]]; then
                API_TOKEN=$global_token
                using_alt_token="false"
            fi
        done
    else
        log_message "[error] Cloudflare API token not valid, exiting."
        exit 1
    fi
    # Sleep for the specified interval before the next run
    log_message "[info] End of the run, sleeping for $SLEEP_INTERVAL seconds."
    sleep $SLEEP_INTERVAL
done