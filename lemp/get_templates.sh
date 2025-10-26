#!/usr/bin/env bash
# get_templates.sh
# =================================================================
# Proxmox LXC Template Lister
#
# Copyright (c) 2025 Rámon van Raaij
# License: MIT
# Author: Rámon van Raaij | Bluesky: @ramonvanraaij.nl | GitHub: https://github.com/ramonvanraaij | Website: https://ramon.vanraaij.eu
#
# This script queries the Proxmox VE API to list available LXC
# templates (vztmpl) on a specified storage pool of a specific node.
# It is intended to be used as a helper script, typically by
# `create_tfvars.sh`.
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
#    chmod +x get_templates.sh
#
# --- Usage ---
# Run the script directly. It will output a list of template volume IDs,
# one per line.
#
#   ./get_templates.sh [NODE_NAME] [STORAGE_NAME]
#
# Arguments:
#   NODE_NAME (Optional): The name of the Proxmox node. Defaults to "pve".
#   STORAGE_NAME (Optional): The name of the storage pool. Defaults to "local".
#
# Examples:
#   ./get_templates.sh                # Uses defaults: node 'pve', storage 'local'
#   ./get_templates.sh pve storage-nfs # Uses specified node and storage
# =================================================================

# --- Script Configuration ---
# Exit on error, treat unset variables as an error, and fail on piped command errors.
set -o errexit -o nounset -o pipefail

# --- Default Configuration ---
# These values are used if arguments are not provided.
readonly DEFAULT_NODE="pve"
readonly DEFAULT_STORAGE="local"

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
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable '${var}' is not set or is empty."
            log_error "Please source your Proxmox API secrets file (e.g., source ~/.proxmox_api_secrets)."
            exit 1
        fi
    done

    # Check if PM_TLS_INSECURE is set, default to false if not.
    local curl_insecure_opt="-k" # Default to insecure
    if [ "${PM_TLS_INSECURE:-}" = "false" ]; then
        curl_insecure_opt="" # Don't use -k if explicitly set to false
    fi

    # --- 2. Determine Node and Storage ---
    # Use provided arguments or fall back to defaults.
    local node="${1:-${DEFAULT_NODE}}"
    local storage="${2:-${DEFAULT_STORAGE}}"

    # --- 3. Fetch and List Templates ---
    local api_url="${PM_API_URL}/nodes/${node}/storage/${storage}/content"
    local api_response
    
    # Fetch storage content using curl.
    if ! api_response=$(curl -s --fail $curl_insecure_opt \
             -H "Authorization: PVEAPIToken=${PM_API_TOKEN_ID}=${PM_API_TOKEN_SECRET}" \
             "${api_url}"); then
        log_error "Failed to fetch content from Proxmox API for node '${node}', storage '${storage}'."
        log_error "Check API URL, token, secret, node/storage names, and network connectivity."
        exit 1
    fi

    # DEBUGGING: Print the raw JSON response to standard error (optional)
    # echo "--- RAW API RESPONSE ---" >&2 
    # echo "${api_response}" | jq '.' >&2 # Pretty print JSON to stderr
    # echo "--- END RAW API RESPONSE ---" >&2

    # Parse the JSON response using jq to extract LXC template volume IDs.
    # CORRECTED: Filter using '.content' instead of '.contenttype'.
    local templates
    templates=$(echo "${api_response}" | jq -r '.data[] | select(.content == "vztmpl") | .volid')

    # Check if any templates were found.
    if [ -z "$templates" ]; then
        log_error "No LXC templates ('vztmpl') found on node '${node}' in storage '${storage}' based on the API response."
        # Exit with success (0) but empty output, as this isn't necessarily a script *error*.
        exit 0
    fi

    # --- 4. Output Template List ---
    # Print the found template volume IDs, one per line.
    echo "$templates"
}

# Execute the main function, passing command-line arguments.
main "$@"

