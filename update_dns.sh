#!/bin/bash

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "[error] curl is not installed. Please install curl (e.g., 'apk --no-cache add curl' or 'apt-get install curl')." >&2
    exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "[error] yq is not installed. Please install yq (e.g., 'apk --no-cache add yq' or 'apt-get install yq')." >&2
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "[error] jq is not installed. Please install jq (e.g., 'apk --no-cache add jq' or 'apt-get install jq')." >&2
    exit 1
fi

# Create config files if they don't exist
if [ ! -f /config/cloudflare-ddns-config.yaml ]; then
    cp /app/cloudflare-ddns-config.yaml /config/cloudflare-ddns-config.yaml
fi
if [ ! -f /config/dns-records.json ]; then
    cp /app/dns-records.json /config/dns-records.json
fi

# Source settings from the configuration file
CONFIG="/config/cloudflare-ddns-config.yaml"
API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(yq eval '.API_TOKEN' "$CONFIG")}"
SLEEP_INTERVAL="${SLEEP_INT:-$(yq eval '.SLEEP_INTERVAL' "$CONFIG")}"
LOG_FILE="${LOG_FILE_LOCATION:-$(yq eval '.LOG_FILE' "$CONFIG")}"

# Load the JSON file into a variable
DNS_RECORDS_JSON=$(cat /config/dns-records.json)

# Convert JSON array to Bash array
IFS=$'\n' read -d '' -ra ZONE_CONFIGS < <(echo "$DNS_RECORDS_JSON" | jq -c '.ZONE_CONFIGS[]')

# Function to log messages and echo to the console
log_message() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] $1"
    
    # Print log entry to console
    echo "$log_entry"
    
    # Log to file
    echo "$log_entry" >> "$LOG_FILE" 2>&1
    
    # Rotate log file if it exceeds a certain size (e.g., 1 MB)
    local log_file_size=$(du -b "$LOG_FILE" | cut -f1)
    local max_log_size=$((1024 * 1024))  # 1 MB
    if [ "$log_file_size" -gt "$max_log_size" ]; then
        local backup_file="$LOG_FILE.$(date +%Y%m%d%H%M%S)"
        mv "$LOG_FILE" "$backup_file"
        echo "[info] Log file rotated. Old log file: $backup_file" >> "$LOG_FILE" 2>&1
    fi
}

# Function to get the current public IPv4 address
get_public_ipv4() {
    curl -s https://api.ipify.org?format=text
}

# Function to get the current public IPv6 address
get_public_ipv6() {
    curl -s https://api64.ipify.org?format=text
}

# Function to test Cloudflare API token
test_api_token() {
    local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $API_TOKEN")

    # Check for errors in the response
    if [[ $(echo "$response" | jq -r '.errors | length') -gt 0 ]]; then
        echo "[error] Error testing API token: $response"
    else
        echo "[info] The Cloudflare API token is valid."
    fi
}

# Function to get DNS record
get_dns_record_value() {
    local full_record_name="${subdomain:+"$subdomain."}$record_name"

    local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$record_type&name=$full_record_name" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json")

    echo "$(jq -r '.result[] | "\(.content) \(.id)"' <<< "$response")"
}

# Function to update DNS record
update_dns_record() {
    local new_ip=$1
    local full_record_name="${subdomain:+"$subdomain."}$record_name"

    local response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{
            "content": "'$new_ip'",
            "name": "'$full_record_name'",
            "proxied": '$proxied',
            "type": "'$record_type'",
            "ttl": 1
        }')

    # Check for errors in the response
    if [[ $(echo "$response" | jq -r '.errors | length') -gt 0 ]]; then
        echo "[error] Error updating DNS record for ${subdomain:+"$subdomain."}$record_name in Zone $zone_id: $response"
    else
        echo "[info] DNS record updated successfully for ${subdomain:+"$subdomain."}$record_name in Zone $zone_id."
    fi
}

check_and_update_record(){
    # Check if the public IPv4 is different from the current DNS record value
    local public_ip=$1
    output2=""
    output3=""
    if [ "$public_ip" != "$record_content" ]; then
        output1="[info] Current value is different from Public IP, Updating DNS Record for record ${subdomain:+"$subdomain."}$record_name type $record_type in zone $zone_id"
        output2=$(update_dns_record "$public_ip")
        # Check for errors during DNS record update
        if [ "$output2" == *"Error"* ]; then
            output3="[error] Failed to update the DNS Record for ${subdomain:+"$subdomain."}$record_name type $record_type in Zone $zone_id."
        else
            output3="[info] Changed the DNS Record for ${subdomain:+"$subdomain."}$record_name type $record_type from $record_content to $public_ip"
        fi
    else
        output1="[info] Public IP is the same as current value. Skipping update for ${subdomain:+"$subdomain."}$record_name in Zone $zone_id."
    fi
}

# Signal handler function
cleanup() {
    log_message "[info] Received termination signal. Exiting."
    exit 0
}

# Register the cleanup function to handle termination signals
trap cleanup SIGTERM SIGINT

# Main loop
log_message "[info] Script has initialised"
while true; do

    # Test the cloudflare API Token
    token_status=$(test_api_token)
    log_message "$token_status"
    if [ "$token_status" != *"Error"* ]; then

        # Retrieve the current public IPv4 and IPv6 addresses
        current_ipv4=$(get_public_ipv4)
        log_message "[info] Current public IPV4 address is $current_ipv4"
        current_ipv6=$(get_public_ipv6)
        log_message "[info] Current public IPV6 address is $current_ipv6"

        # Iterate through each configured DNS record
        for zone_config in "${ZONE_CONFIGS[@]}"; do
            zone_id=$(echo "$zone_config" | jq -r '.zone_id')
            record_type=$(echo "$zone_config" | jq -r '.record_type')
            record_name=$(echo "$zone_config" | jq -r '.record_name')
            proxied=$(echo "$zone_config" | jq -r '.proxied')
            subdomain=$(echo "$zone_config" | jq -r '.subdomain')
            get_dns_record_value_return=$(get_dns_record_value)
            IFS=" " read -r record_content record_id <<< "$get_dns_record_value_return"
            log_message "[info] Retrieved DNS record value for record ${subdomain:+"$subdomain."}$record_name type $record_type in Zone $zone_id: $record_content"

            # Check and update the record
            case "$record_type" in
                "A")
                    check_and_update_record "$current_ipv4"
                    for output in "$output1" "$output2" "$output3"; do
                        if [ -n "$output" ]; then
                            log_message "$output"
                        fi
                    done
                    ;;
                "AAAA")
                    check_and_update_record "$current_ipv6"
                    for output in "$output1" "$output2" "$output3"; do
                        if [ -n "$output" ]; then
                            log_message "$output"
                        fi
                    done
                    ;;
                *)
                    # Log if the record type is unsupported
                    log_message "[error] Unsupported record type: $record_type. Skipping update for ${subdomain:+"$subdomain."}$record_name in Zone $zone_id."
                    continue
                    ;;
            esac
        done
    fi
    # Sleep for the specified interval before the next run
    log_message "[info] End of the run. Sleeping for $SLEEP_INTERVAL seconds."
    sleep $SLEEP_INTERVAL
done