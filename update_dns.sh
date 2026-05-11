#!/bin/bash
set -uo pipefail

# ---------------------------------------------------------------------------
# Cloudflare DDNS Updater
# Detects public IPv4/IPv6 and updates Cloudflare DNS records when they change.
# ---------------------------------------------------------------------------

EXAMPLE_CONFIG="/app/cloudflare-ddns-config.yaml"
CONFIG="/config/cloudflare-ddns-config.yaml"
DNS_RECORDS_FILE="/config/dns-records.json"

# Timeout options applied to every curl call
CURL_OPTS=(--silent --max-time 10 --connect-timeout 5)

# ---------------------------------------------------------------------------
# Bootstrap: set a safe default log path before the config is available
# ---------------------------------------------------------------------------
LOG_FILE="/var/log/cloudflare-ddns/update_dns.log"

_bootstrap_log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local entry="[$ts] $1"
    echo "$entry"
    echo "$entry" >> "$LOG_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Copy default config files on first run
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG" ]]; then
    cp "$EXAMPLE_CONFIG" "$CONFIG"
    _bootstrap_log "[info] Created default config: $CONFIG — edit it before use."
fi
if [[ ! -f "$DNS_RECORDS_FILE" ]]; then
    cp /app/dns-records.json "$DNS_RECORDS_FILE"
    _bootstrap_log "[info] Created default DNS records file: $DNS_RECORDS_FILE — edit it before use."
fi

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
for _cmd in curl yq jq; do
    if ! command -v "$_cmd" &>/dev/null; then
        _bootstrap_log "[error] Required tool not found: $_cmd — exiting."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Read configuration (environment variables take precedence over config file)
# ---------------------------------------------------------------------------
_cfg() { yq eval "${1} // \"\"" "$CONFIG" 2>/dev/null || true; }

LOG_FILE_CFG="${LOG_FILE_LOCATION:-$(_cfg '.LOG_FILE')}"
if [[ -n "$LOG_FILE_CFG" && "$LOG_FILE_CFG" != "null" ]]; then
    if [[ ! -d "$(dirname "$LOG_FILE_CFG")" ]]; then
        _bootstrap_log "[warning] Invalid LOG_FILE path '$LOG_FILE_CFG', keeping default."
    else
        LOG_FILE="$LOG_FILE_CFG"
    fi
fi

API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(_cfg '.API_TOKEN')}"
SLEEP_INTERVAL="${SLEEP_INT:-$(_cfg '.SLEEP_INTERVAL')}"
DRY_RUN="${DRY_RUN_MODE:-$(_cfg '.DRY_RUN')}"
LOG_ROTATION="${ENABLE_LOG_ROTATION:-$(_cfg '.LOG_ROTATION')}"
LOG_ROTATION_SIZE="${MAX_LOG_SIZE:-$(_cfg '.LOG_ROTATION_SIZE')}"
REMOVE_OLD_LOGS="${DELETE_OLD_LOGS:-$(_cfg '.REMOVE_OLD_LOGS')}"
LOG_FILES_AMOUNT="${NUMBER_OF_LOG_FILES_TO_KEEP:-$(_cfg '.LOG_FILES_AMOUNT')}"

# ---------------------------------------------------------------------------
# Normalize helpers
# ---------------------------------------------------------------------------
_normalize_bool() {
    local val="${1,,}" default="$2" name="$3"
    case "$val" in
        true|false) echo "$val" ;;
        ""|null)    _bootstrap_log "[info] $name not set, defaulting to $default."; echo "$default" ;;
        *)          _bootstrap_log "[warning] Invalid value for $name ('$1'), defaulting to $default."; echo "$default" ;;
    esac
}

_normalize_posint() {
    local val="$1" default="$2" name="$3"
    if [[ -z "$val" || "$val" == "null" ]]; then
        _bootstrap_log "[info] $name not set, defaulting to $default."
        echo "$default"
    elif [[ "$val" =~ ^[1-9][0-9]*$ ]]; then
        echo "$val"
    else
        _bootstrap_log "[warning] Invalid value for $name ('$val'), defaulting to $default."
        echo "$default"
    fi
}

DRY_RUN=$(_normalize_bool "${DRY_RUN:-}" "false" "DRY_RUN")
SLEEP_INTERVAL=$(_normalize_posint "${SLEEP_INTERVAL:-}" "900" "SLEEP_INTERVAL")
LOG_ROTATION=$(_normalize_bool "${LOG_ROTATION:-}" "true" "LOG_ROTATION")
LOG_ROTATION_SIZE=$(_normalize_posint "${LOG_ROTATION_SIZE:-}" "10" "LOG_ROTATION_SIZE")
REMOVE_OLD_LOGS=$(_normalize_bool "${REMOVE_OLD_LOGS:-}" "true" "REMOVE_OLD_LOGS")
LOG_FILES_AMOUNT=$(_normalize_posint "${LOG_FILES_AMOUNT:-}" "10" "LOG_FILES_AMOUNT")

# ---------------------------------------------------------------------------
# Full logging function (with rotation)
# ---------------------------------------------------------------------------
log_message() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local entry="[$ts] $1"
    echo "$entry"
    echo "$entry" >> "$LOG_FILE"

    if [[ "$LOG_ROTATION" == "true" ]]; then
        local max_bytes=$(( LOG_ROTATION_SIZE * 1048576 ))
        local current_size
        current_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if (( current_size > max_bytes )); then
            local rotated="$LOG_FILE.$(date '+%Y%m%d%H%M%S')"
            mv "$LOG_FILE" "$rotated"
            echo "[info] Log rotated → $rotated" >> "$LOG_FILE"
        fi
    fi

    if [[ "$REMOVE_OLD_LOGS" == "true" ]]; then
        local log_dir log_base count
        log_dir=$(dirname "$LOG_FILE")
        log_base=$(basename "$LOG_FILE")
        count=$(find "$log_dir" -maxdepth 1 -type f -name "${log_base}.*" 2>/dev/null | wc -l)
        if (( count > LOG_FILES_AMOUNT )); then
            local excess=$(( count - LOG_FILES_AMOUNT ))
            mapfile -t old_files < <(
                find "$log_dir" -maxdepth 1 -type f -name "${log_base}.*" -printf '%T@ %p\n' \
                | sort -n \
                | head -n "$excess" \
                | cut -d' ' -f2-
            )
            if (( ${#old_files[@]} > 0 )); then
                rm -- "${old_files[@]}"
                log_message "[info] Removed $excess old log file(s), keeping $LOG_FILES_AMOUNT."
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Check user config for missing keys (compared to bundled example)
# ---------------------------------------------------------------------------
check_config_keys() {
    local missing
    missing=$(comm -23 \
        <(yq eval 'keys | .[]' "$EXAMPLE_CONFIG" 2>/dev/null | sort) \
        <(yq eval 'keys | .[]' "$CONFIG" 2>/dev/null | sort) \
    )
    if [[ -n "$missing" ]]; then
        local formatted
        formatted=$(echo "$missing" | tr '\n' ',' | sed 's/,$//;s/,/, /g')
        log_message "[warning] Config is missing keys (may use defaults): $formatted"
    else
        log_message "[info] Config keys look complete."
    fi
}

# ---------------------------------------------------------------------------
# Public IP detection
# Prefers Cloudflare's own trace endpoint; falls back to ipify.
# ---------------------------------------------------------------------------
get_public_ip() {
    local version="$1"
    local ip_cf ip_ipify

    case "$version" in
        v4)
            ip_cf=$(curl "${CURL_OPTS[@]}" 'https://1.1.1.1/cdn-cgi/trace' 2>/dev/null \
                | grep '^ip=' | cut -d= -f2 || true)
            ip_ipify=$(curl "${CURL_OPTS[@]}" 'https://api.ipify.org?format=text' 2>/dev/null || true)
            ;;
        v6)
            ip_cf=$(curl "${CURL_OPTS[@]}" 'https://[2606:4700:4700::1111]/cdn-cgi/trace' 2>/dev/null \
                | grep '^ip=' | cut -d= -f2 || true)
            ip_ipify=$(curl "${CURL_OPTS[@]}" 'https://api6.ipify.org?format=text' 2>/dev/null || true)
            ;;
        *)
            log_message "[error] get_public_ip: invalid version '$version'"
            return 1
            ;;
    esac

    if [[ -n "$ip_cf" ]]; then
        echo "$ip_cf"
    elif [[ -n "$ip_ipify" ]]; then
        log_message "[warning] Cloudflare trace unavailable for $version, using ipify fallback."
        echo "$ip_ipify"
    else
        log_message "[error] Could not determine public IP ($version) from any source."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Cloudflare API helpers
# ---------------------------------------------------------------------------
test_api_token() {
    local token="$1"
    local response
    response=$(curl "${CURL_OPTS[@]}" -X GET \
        'https://api.cloudflare.com/client/v4/user/tokens/verify' \
        -H "Authorization: Bearer $token")
    if [[ $(jq -r '.errors | length' <<< "$response") -gt 0 ]]; then
        log_message "[error] API token validation failed: $(jq -r '.errors[0].message // "unknown error"' <<< "$response")"
        return 1
    fi
}

get_zone_name() {
    local zone_id="$1" token="$2"
    local response
    response=$(curl "${CURL_OPTS[@]}" -X GET \
        "https://api.cloudflare.com/client/v4/zones/$zone_id" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json')
    if [[ $(jq -r '.errors | length' <<< "$response") -gt 0 ]]; then
        log_message "[error] Failed to get zone name for $zone_id: $(jq -r '.errors[0].message // "unknown error"' <<< "$response")"
        return 1
    fi
    jq -r '.result.name' <<< "$response"
}

get_dns_record() {
    local zone_id="$1" record_type="$2" full_name="$3" token="$4"
    local response
    response=$(curl "${CURL_OPTS[@]}" -X GET \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$record_type&name=$(jq -rn --arg n "$full_name" '$n | @uri')" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json')
    if [[ $(jq -r '.errors | length' <<< "$response") -gt 0 ]]; then
        log_message "[error] Failed to get DNS record $full_name ($record_type): $(jq -r '.errors[0].message // "unknown error"' <<< "$response")"
        return 1
    fi
    # Return "content record_id" for the first matching record
    jq -r '.result[0] | "\(.content) \(.id)"' <<< "$response"
}

update_dns_record() {
    local zone_id="$1" record_id="$2" full_name="$3" record_type="$4"
    local new_ip="$5" proxied="$6" ttl="$7" token="$8"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "[dry-run] Would update $full_name ($record_type) → $new_ip (proxied=$proxied, ttl=$ttl)"
        return 0
    fi

    # Build the JSON payload safely with jq to prevent injection
    local payload
    payload=$(jq -n \
        --arg  content  "$new_ip" \
        --arg  name     "$full_name" \
        --arg  type     "$record_type" \
        --argjson proxied "$proxied" \
        --argjson ttl     "$ttl" \
        '{content: $content, name: $name, type: $type, proxied: $proxied, ttl: $ttl}')

    local response
    response=$(curl "${CURL_OPTS[@]}" -X PUT \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' \
        --data "$payload")

    if [[ $(jq -r '.errors | length' <<< "$response") -gt 0 ]]; then
        log_message "[error] Failed to update $full_name ($record_type): $(jq -r '.errors[0].message // "unknown error"' <<< "$response")"
        return 1
    fi
    log_message "[info] Updated $full_name ($record_type) → $new_ip"
}

# ---------------------------------------------------------------------------
# Signal handler — allows graceful shutdown via SIGTERM / SIGINT
# ---------------------------------------------------------------------------
cleanup() {
    log_message "[info] Termination signal received, exiting."
    exit 0
}
trap cleanup SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Load and validate DNS records config
# ---------------------------------------------------------------------------
if [[ ! -f "$DNS_RECORDS_FILE" ]]; then
    log_message "[error] DNS records file not found: $DNS_RECORDS_FILE"
    exit 1
fi
DNS_RECORDS_JSON=$(cat "$DNS_RECORDS_FILE")

if ! jq -e '.RECORDS_CONFIG' <<< "$DNS_RECORDS_JSON" >/dev/null 2>&1; then
    log_message "[error] RECORDS_CONFIG key not found in $DNS_RECORDS_FILE"
    exit 1
fi
mapfile -t RECORDS_CONFIG < <(jq -c '.RECORDS_CONFIG[]' <<< "$DNS_RECORDS_JSON")
if [[ ${#RECORDS_CONFIG[@]} -eq 0 ]]; then
    log_message "[error] No records found in RECORDS_CONFIG in $DNS_RECORDS_FILE"
    exit 1
fi

check_config_keys

# ---------------------------------------------------------------------------
# Validate API token configuration
# ---------------------------------------------------------------------------
if [[ -z "$API_TOKEN" || "$API_TOKEN" == "null" || "$API_TOKEN" == "YOUR_CLOUDFLARE_API_TOKEN" ]]; then
    log_message "[error] API token is not configured. Set CLOUDFLARE_API_TOKEN or update $CONFIG"
    exit 1
fi

# ---------------------------------------------------------------------------
# Detect IPv6 availability
# ---------------------------------------------------------------------------
IPV6_AVAILABLE=false
if ip -6 addr show scope global 2>/dev/null | grep -q 'inet6'; then
    IPV6_AVAILABLE=true
else
    if jq -e '.RECORDS_CONFIG[] | select(.record_type == "AAAA")' <<< "$DNS_RECORDS_JSON" >/dev/null 2>&1; then
        log_message "[warning] AAAA records configured but no global IPv6 address found on this host."
        log_message "[warning] Ensure the host has IPv6 and the container uses host networking."
    else
        log_message "[info] No IPv6 address detected (no AAAA records configured)."
    fi
fi

log_message "[info] Cloudflare DDNS updater started — interval=${SLEEP_INTERVAL}s, dry-run=${DRY_RUN}, ipv6=${IPV6_AVAILABLE}"

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while true; do

    if ! test_api_token "$API_TOKEN"; then
        log_message "[error] Global API token is invalid, exiting."
        exit 1
    fi
    log_message "[info] API token validated."

    # Fetch current public IPs
    current_ipv4=""
    if ! current_ipv4=$(get_public_ip v4); then
        log_message "[warning] Could not determine public IPv4, skipping this run."
        sleep "$SLEEP_INTERVAL" & wait $!
        continue
    fi
    log_message "[info] Public IPv4: $current_ipv4"

    current_ipv6=""
    if [[ "$IPV6_AVAILABLE" == "true" ]]; then
        if ! current_ipv6=$(get_public_ip v6); then
            log_message "[warning] Could not determine public IPv6 this run."
        else
            log_message "[info] Public IPv6: $current_ipv6"
        fi
    fi

    for record in "${RECORDS_CONFIG[@]}"; do
        zone_id=$(jq -r '.zone_id'                         <<< "$record")
        record_type=$(jq -r '.record_type'                 <<< "$record")
        subdomain=$(jq -r '.subdomain // ""'               <<< "$record")
        proxied=$(jq -r '.proxied // true'                 <<< "$record")
        ttl=$(jq -r '.ttl // 1 | tonumber'                 <<< "$record")
        alt_token=$(jq -r '.alternate_api_token // ""'     <<< "$record")

        # Normalise proxied to a JSON boolean (handles both string and boolean input)
        case "${proxied,,}" in
            true)  proxied=true  ;;
            false) proxied=false ;;
            *)     proxied=true  ;;
        esac

        # Resolve which API token to use for this record
        active_token="$API_TOKEN"
        if [[ -n "$alt_token" && "$alt_token" != "null" && "$alt_token" != "ALTERNATE_CLOUDFLARE_API_TOKEN" ]]; then
            if test_api_token "$alt_token" 2>/dev/null; then
                active_token="$alt_token"
                log_message "[info] Using alternate API token for zone $zone_id."
            else
                log_message "[warning] Alternate API token invalid for zone $zone_id, falling back to global token."
            fi
        fi

        # Resolve zone name
        zone_name=""
        if ! zone_name=$(get_zone_name "$zone_id" "$active_token"); then
            log_message "[error] Could not retrieve zone name for $zone_id, skipping record."
            continue
        fi
        log_message "[info] Zone: $zone_name ($zone_id)"

        full_name="${subdomain:+${subdomain}.}${zone_name}"

        # Select the appropriate public IP for this record type
        case "$record_type" in
            A)
                public_ip="$current_ipv4"
                ;;
            AAAA)
                if [[ "$IPV6_AVAILABLE" != "true" || -z "$current_ipv6" ]]; then
                    log_message "[warning] Skipping AAAA record $full_name: no IPv6 address available."
                    continue
                fi
                public_ip="$current_ipv6"
                ;;
            *)
                log_message "[error] Unsupported record type '$record_type' for $full_name, skipping."
                continue
                ;;
        esac

        # Fetch current DNS record value
        dns_result=""
        if ! dns_result=$(get_dns_record "$zone_id" "$record_type" "$full_name" "$active_token"); then
            log_message "[error] Could not retrieve DNS record for $full_name ($record_type), skipping."
            continue
        fi
        read -r record_content record_id <<< "$dns_result"
        if [[ -z "$record_content" || "$record_content" == "null" ]]; then
            log_message "[error] Empty DNS record returned for $full_name ($record_type), skipping."
            continue
        fi
        log_message "[info] $full_name ($record_type): current=$record_content, public=$public_ip"

        # Update only if the IP has changed
        if [[ "$public_ip" == "$record_content" ]]; then
            log_message "[info] $full_name ($record_type): no change, skipping update."
        else
            update_dns_record \
                "$zone_id" "$record_id" "$full_name" "$record_type" \
                "$public_ip" "$proxied" "$ttl" "$active_token"
        fi
    done

    log_message "[info] Run complete. Sleeping ${SLEEP_INTERVAL}s."
    # sleep in background + wait so SIGTERM/SIGINT is handled immediately
    sleep "$SLEEP_INTERVAL" & wait $!
done
