#!/usr/bin/env bash
# get_next_id.sh
# =================================================================
# Proxmox Next Available LXC Container ID Finder
#
# Copyright (c) 2025 Rámon van Raaij
# License: MIT
# Author: Rámon van Raaij | Bluesky: @ramonvanraaij.nl | GitHub: https://github.com/ramonvanraaij | Website: https://ramon.vanraaij.eu
#
# This script queries the Proxmox VE API to find the highest
# existing LXC container ID and calculates the next available ID
# (highest + 1). It is intended to be used as a helper script,
# often by `create_tfvars.sh`.
#
# --- Setup ---
# 1. Dependencies: This script requires `curl` and `jq`.
#    Install them if necessary (e.g., `apt update && apt install curl jq`).
#
# 2. Environment Variables: This script relies on environment variables
#    for Proxmox API authentication. Ensure the following are set
#    before running, typically by sourcing a secrets file:
#    - PM_API_URL
#    - PM_API_TOKEN_ID
#    - PM_API_TOKEN_SECRET
#    Example: source ~/.proxmox_api_secrets
#
# 3. Permissions: Make the script executable:
#    chmod +x get_next_id.sh
#
# --- Usage ---
# Run the script directly. It will output the next available ID number.
#
#   ./get_next_id.sh
# =================================================================

# --- Script Configuration ---
# Exit on error, treat unset variables as an error, and fail on piped command errors.
set -o errexit -o nounset -o pipefail

# --- Functions ---

# Logs an error message to stderr.
log_error() {
    printf '[ERROR] %s\n' "$1" >&2
}

# --- Main script logic ---
main() {
    # --- 1. Pre-flight Checks ---
    # Check for required commands
    local dependencies="curl jq"
    for cmd in $dependencies; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command '${cmd}' is not installed or not in PATH."
            exit 1
        fi
    done

    # Check for required environment variables
    local required_vars="PM_API_URL PM_API_TOKEN_ID PM_API_TOKEN_SECRET"
    for var in $required_vars; do
        # Use parameter expansion for safe check, including nounset compatibility
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable '${var}' is not set or is empty."
            log_error "Please source your Proxmox API secrets file (e.g., source ~/.proxmox_api_secrets)."
            exit 1
        fi
    done

    # Check if PM_TLS_INSECURE is set, default to false if not.
    local curl_insecure_opt="-k" # Default to insecure if var isn't explicitly false
    if [ "${PM_TLS_INSECURE:-}" = "false" ]; then
        curl_insecure_opt="" # Don't use -k if explicitly set to false
    fi

    # --- 2. Fetch and Calculate Last ID ---
    local api_response
    local last_id
    
    # Fetch cluster resources using curl.
    # -s: Silent mode.
    # $curl_insecure_opt: Includes -k if PM_TLS_INSECURE is not 'false'.
    # --fail: Exit with an error if the HTTP request fails.
    # The Authorization header uses the environment variables.
    if ! api_response=$(curl -s --fail $curl_insecure_opt \
             -H "Authorization: PVEAPIToken=${PM_API_TOKEN_ID}=${PM_API_TOKEN_SECRET}" \
             "${PM_API_URL}/cluster/resources"); then
        log_error "Failed to fetch resources from Proxmox API at ${PM_API_URL}."
        log_error "Check API URL, token, secret, and network connectivity."
        exit 1
    fi

    # Parse the JSON response using jq.
    # 1. `.data[]`: Iterate through the items in the 'data' array.
    # 2. `select(.type == "lxc")`: Filter to keep only LXC containers.
    # 3. `[...]`: Collect the filtered containers back into an array.
    # 4. `.[-1].vmid`: Select the 'vmid' of the last container in the array.
    # 5. `// 99`: If no LXC containers exist (array is empty or vmid is null), default to 99.
    #    This ensures the next ID starts at 100 in an empty cluster.
    last_id=$(echo "${api_response}" | jq '[.data[] | select(.type == "lxc")] | .[-1].vmid // 99')

    # Validate that jq successfully returned a number.
    if ! [[ "$last_id" =~ ^[0-9]+$ ]]; then
        log_error "Failed to parse the last container ID from the API response."
        log_error "API Response was: ${api_response}"
        exit 1
    fi

    # --- 3. Output Next ID ---
    # Calculate and print the next ID.
    echo $((last_id + 1))
}

# Execute the main function.
main
