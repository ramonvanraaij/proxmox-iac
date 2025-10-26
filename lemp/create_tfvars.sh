#!/usr/bin/env bash
# create_tfvars.sh
# =================================================================
# Interactive Terraform .tfvars File Creator
#
# Copyright (c) 2025 Rámon van Raaij
# License: MIT
# Author: Rámon van Raaij | Bluesky: @ramonvanraaij.nl | GitHub: https://github.com/ramonvanraaij | Website: https://ramon.vanraaij.eu
#
# This script provides an interactive wizard to generate a `terraform.tfvars`
# file for provisioning a Proxmox LXC container.
#
# It performs the following actions:
# 1. Fetches the next available container ID and a list of LXC templates
#    from helper scripts.
# 2. Prompts the user for all necessary details, such as hostname,
#    passwords, and network configuration, with smart defaults.
# 3. Uses the PM_API_URL environment variable (if set) to suggest a
#    default Proxmox Host IP.
# 4. Securely prompts for the container's root password.
# 5. Generates a clean, well-formatted `terraform.tfvars` file based on
#    the user's input.
#
# --- Setup ---
# 1. Dependencies: This script requires two helper scripts to be present
#    in the same directory and be executable (`chmod +x`):
#    - `get_next_id.sh`: Fetches the next available CT ID from Proxmox.
#    - `get_templates.sh`: Fetches a list of available LXC templates.
#
# 2. Environment Variables: It's recommended (but not required) to source
#    your Proxmox API secrets file before running this script. If the
#    PM_API_URL variable is set, it will be used as the default host IP.
#    Example: source ~/.proxmox_api_secrets
#
# 3. Permissions: Make this script executable:
#    chmod +x create_tfvars.sh
#
# --- Usage ---
# Run the script from your Terraform project directory. It will create
# or overwrite the `terraform.tfvars` file in the same directory.
#
#   ./create_tfvars.sh
# =================================================================

# --- Script Configuration ---
# Exit on error, treat unset variables as an error, and fail on piped command errors.
set -o errexit -o nounset -o pipefail

# --- Define color variables for styled terminal output ---
readonly GREEN=$(tput setaf 2)
readonly RED=$(tput setaf 1)
readonly YELLOW=$(tput setaf 3)
readonly NORMAL=$(tput sgr0)

# --- Functions ---

# Logs a message to the console with a timestamp and color.
log_message() {
    local color="$1"
    local message="$2"
    printf "${color}[%s] %s${NORMAL}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$message"
}

# --- Main script logic ---
main() {
    log_message "${YELLOW}" "--- Starting Terraform .tfvars Setup Wizard ---"

    # --- 1. Pre-flight Checks ---
    local dependencies="get_next_id.sh get_templates.sh"
    for script in $dependencies; do
        if [ ! -f "$script" ] || [ ! -x "$script" ]; then
            log_message "${RED}" "FATAL: Required helper script '${script}' not found or not executable."
            exit 1
        fi
    done
    log_message "${GREEN}" "All helper scripts are present and executable."

    # --- 2. Get Dynamic Data from Proxmox ---
    local NEXT_ID
    NEXT_ID=$(./get_next_id.sh)
    log_message "${YELLOW}" "Next available container ID is: ${NEXT_ID}"

    # --- 3. Interactive Prompts ---

    # Determine default Proxmox host IP from environment variable if available
    local default_proxmox_ip=""
    local proxmox_ip_prompt="Enter Proxmox Host IP (for SSH access) [no default]: "
    if [ -n "${PM_API_URL:-}" ]; then
        # Extract hostname/IP from the URL (remove protocol, port, path)
        default_proxmox_ip=$(echo "${PM_API_URL}" | sed -e 's|https\?://||' -e 's|:.*||')
        proxmox_ip_prompt="Enter Proxmox Host IP (for SSH access) [default: ${default_proxmox_ip}]: "
    fi
    read -p "$proxmox_ip_prompt" PROXMOX_HOST_IP_INPUT
    # Use the input if provided, otherwise the default (which might be empty)
    local PROXMOX_HOST_IP=${PROXMOX_HOST_IP_INPUT:-$default_proxmox_ip}

    if [ -z "$PROXMOX_HOST_IP" ]; then
        log_message "${RED}" "Proxmox Host IP is required for the provisioner."
        exit 1
    fi

    read -p "Enter Proxmox Node Name [default: pve]: " NODE
    NODE=${NODE:-pve}

    read -p "Enter Storage Pool for Templates [default: local]: " STORAGE
    STORAGE=${STORAGE:-local}

    # Fetch templates using the helper script
    mapfile -t TEMPLATES < <(./get_templates.sh "$NODE" "$STORAGE")
    if [ ${#TEMPLATES[@]} -eq 0 ]; then
        log_message "${RED}" "No LXC templates found on node '${NODE}' in storage '${STORAGE}'."
        exit 1
    fi

    read -p "Enter Hostname [default: lemp-iac]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-lemp-iac}

    echo "Please select an OS template:"
    for i in "${!TEMPLATES[@]}"; do
        printf "  %s) %s\n" "$((i+1))" "${TEMPLATES[$i]}"
    done
    printf "  %s) Quit\n" "$((${#TEMPLATES[@]}+1))"
    
    read -p "Enter selection [1-$((${#TEMPLATES[@]}+1))]: " TEMPLATE_CHOICE
    if ! [[ "$TEMPLATE_CHOICE" =~ ^[0-9]+$ ]] || (( TEMPLATE_CHOICE < 1 || TEMPLATE_CHOICE > $((${#TEMPLATES[@]}+1)) )); then
        log_message "${RED}" "Invalid selection."
        exit 1
    fi

    if (( TEMPLATE_CHOICE == $((${#TEMPLATES[@]}+1)) )); then
        log_message "${YELLOW}" "Operation cancelled."
        exit 0
    fi
    local OSTemplate="${TEMPLATES[$((TEMPLATE_CHOICE-1))]}"

    read -p "Enter storage for root disk (e.g., local-lvm): " ROOTFS_STORAGE
    if [ -z "$ROOTFS_STORAGE" ]; then
        log_message "${RED}" "Root disk storage is required."
        exit 1
    fi

    # Securely prompt for the root password
    read -sp "Enter a root password for the container (will not be displayed): " ROOT_PASSWORD
    echo "" # Add a newline for better formatting

    read -p "Use static IP? (y/n) [default: y]: " USE_STATIC
    USE_STATIC=${USE_STATIC:-y}

    local CONTAINER_ID IP_PREFIX CIDR_SUFFIX GATEWAY IP_HOST_PART IP_CONFIG
    if [[ "$USE_STATIC" == "y" || "$USE_STATIC" == "Y" ]]; then
        read -p "Enter Container ID [default: ${NEXT_ID}]: " CONTAINER_ID_INPUT
        CONTAINER_ID=${CONTAINER_ID_INPUT:-$NEXT_ID}
        
        # Ask for IP parts separately
        read -p "Enter IP Prefix [default: 192.168.0]: " IP_PREFIX_INPUT
        IP_PREFIX=${IP_PREFIX_INPUT:-"192.168.0"}
        
        read -p "Enter CIDR Suffix [default: 24]: " CIDR_SUFFIX_INPUT
        CIDR_SUFFIX=${CIDR_SUFFIX_INPUT:-"24"}
        
        # Suggest the host part based on the container ID
        local suggested_host_part="${CONTAINER_ID##*.}" # Get last octet if ID has dots, otherwise full ID
        read -p "Enter Host IP Part (last octet) [default: ${suggested_host_part}]: " IP_HOST_PART_INPUT
        IP_HOST_PART=${IP_HOST_PART_INPUT:-$suggested_host_part}
        
        # Construct the full IP config string for display/reference
        IP_CONFIG="${IP_PREFIX}.${IP_HOST_PART}/${CIDR_SUFFIX}"
        # Log the full IP address that will be used
        log_message "${YELLOW}" "Static IP address set to: ${IP_CONFIG%/*}" # Show IP without CIDR
        
        # CORRECTED: Updated gateway prompt to use default format
        local suggested_gateway="${IP_PREFIX}.1"
        read -p "Enter Gateway [default: ${suggested_gateway}]: " GATEWAY_INPUT
        GATEWAY=${GATEWAY_INPUT:-$suggested_gateway} # Use suggested gateway based on prefix
        
        if [[ -z "$IP_PREFIX" || -z "$CIDR_SUFFIX" || -z "$GATEWAY" || -z "$IP_HOST_PART" ]]; then
            log_message "${RED}" "IP Prefix, CIDR Suffix, Host Part, and Gateway are required for static configuration."
            exit 1
        fi
    fi

    # --- 4. Write the terraform.tfvars File ---
    log_message "${YELLOW}" "Generating terraform.tfvars file..."
    # Overwrite the file with `>` to ensure it's clean on every run.
    cat > terraform.tfvars << EOL
# This file was auto-generated by the create_tfvars.sh script
proxmox_host_ip = "${PROXMOX_HOST_IP}"
target_node     = "${NODE}"
hostname        = "${HOSTNAME}"
ostemplate      = "${OSTemplate}"
rootfs_storage  = "${ROOTFS_STORAGE}"
root_password   = "${ROOT_PASSWORD}"
EOL

    # Append network configuration based on user's choice
    if [[ "$USE_STATIC" == "y" || "$USE_STATIC" == "Y" ]]; then
        cat >> terraform.tfvars << EOL
# Static IP configuration
container_id    = ${CONTAINER_ID}
ip_prefix       = "${IP_PREFIX}"
cidr_suffix     = "${CIDR_SUFFIX}"
gateway         = "${GATEWAY}"
# Note: The full IP (${IP_CONFIG}) is constructed within Terraform using ip_prefix and container_id
EOL
    else
        cat >> terraform.tfvars << EOL
# Using DHCP - network details will be assigned by the Proxmox DHCP server
container_id    = null
ip_prefix       = null
cidr_suffix     = null # Provide a default null value for consistency
gateway         = null
EOL
    fi

    log_message "${GREEN}" "terraform.tfvars created successfully!"
    echo "--------------------------------------------------"
    cat terraform.tfvars
    echo "--------------------------------------------------"
}

# Execute the main function.
main
