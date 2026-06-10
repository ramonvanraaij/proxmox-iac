#!/usr/bin/env bash
# test_deployment.sh
# =================================================================
# External, variable-driven test driver for a deployed LEMP container
#
# Copyright (c) 2025-2026 Rámon van Raaij
# License: BSD 3-Clause
# Author: Rámon van Raaij | Bluesky: @ramonvanraaij.nl | GitHub: https://github.com/ramonvanraaij | Website: https://ramon.vanraaij.eu
#
# This script validates a running deployment FROM THE OUTSIDE (e.g. the
# control host). It reads the deployment variables from terraform.tfvars
# (container IP, Proxmox host, container id) and the site list from the
# playbook, then:
# 1. Hits each fake site domain over HTTP using `curl --resolve`, so the
#    placeholder domains (site1.com, site2.com) resolve to the container IP
#    WITHOUT any change to DNS or /etc/hosts.
# 2. Runs the in-container verify.sh (services, PHP-FPM, MariaDB, CrowdSec,
#    nftables) as root through the Proxmox `pct exec` wrapper.
#
# Usage:
#   cd lemp && ./test_deployment.sh
#   # All values are read from terraform.tfvars (which is gitignored).
#   # Override only when testing a target that is not in tfvars (the IPs
#   # below are example-range placeholders, not a real network):
#   ./test_deployment.sh --ip 192.168.0.199 --proxmox 192.168.0.200 \
#       --vmid 199 site1.com site2.com
#
# **Note:**
# The container IP, Proxmox host and container id are taken from
# terraform.tfvars; nothing host-specific is hardcoded in this script.
# Exit status is non-zero if any external check FAILs. The in-container
# verify.sh result is shown inline. No DNS/hosts changes are required.
# =================================================================

set -o nounset -o pipefail

# --- Locate files relative to this script ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TFVARS="${SCRIPT_DIR}/terraform.tfvars"
PLAYBOOK="${SCRIPT_DIR}/playbook.yml"
VERIFY="${SCRIPT_DIR}/verify.sh"

# --- tfvars parser (handles quoted strings and bare numbers, strips comments) ---
tfvar() {
  awk -v k="$1" -F= '
    $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      v=$2; sub(/#.*/,"",v); gsub(/[[:space:]]/,"",v); gsub(/"/,"",v); print v; exit
    }' "$TFVARS" 2>/dev/null
}

# --- Defaults from tfvars, overridable by flags ---
CONTAINER_IP=""; PROXMOX_IP=""; VMID=""; CI_USER="ci"
SITES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ip) CONTAINER_IP="$2"; shift 2 ;;
    --proxmox) PROXMOX_IP="$2"; shift 2 ;;
    --vmid) VMID="$2"; shift 2 ;;
    --ci-user) CI_USER="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) SITES+=("$1"); shift ;;
  esac
done

if [ -f "$TFVARS" ]; then
  [ -z "$VMID" ]       && VMID="$(tfvar container_id)"
  [ -z "$PROXMOX_IP" ] && PROXMOX_IP="$(tfvar proxmox_host_ip)"
  if [ -z "$CONTAINER_IP" ]; then
    pfx="$(tfvar ip_prefix)"
    [ -n "$pfx" ] && [ -n "$VMID" ] && CONTAINER_IP="${pfx}.${VMID}"
  fi
fi

# --- Site list: args, else parse the playbook, else placeholders ---
if [ "${#SITES[@]}" -eq 0 ] && [ -f "$PLAYBOOK" ]; then
  while IFS= read -r d; do [ -n "$d" ] && SITES+=("$d"); done < <(
    grep -E '^[[:space:]]*-[[:space:]]*domain:' "$PLAYBOOK" 2>/dev/null | cut -d'"' -f2)
fi
[ "${#SITES[@]}" -eq 0 ] && SITES=("site1.com" "site2.com")

if [ -z "$CONTAINER_IP" ]; then
  echo "ERROR: could not determine container IP (no terraform.tfvars and no --ip)." >&2
  exit 2
fi

echo "=================================================================="
echo " Target container IP : ${CONTAINER_IP}"
echo " Proxmox host        : ${PROXMOX_IP:-<unknown>}   vmid: ${VMID:-<unknown>}"
echo " Sites               : ${SITES[*]}"
echo " (fake domains resolved with curl --resolve - no DNS/hosts change)"
echo "=================================================================="

PASS=0; FAIL=0
GRN=''; RED=''; YLW=''; RST=''
if [ -t 1 ]; then GRN=$(printf '\033[32m'); RED=$(printf '\033[31m'); YLW=$(printf '\033[33m'); RST=$(printf '\033[0m'); fi

# --- 1. External HTTP checks via curl --resolve (no DNS / no /etc/hosts) ---
echo
echo "${YLW}== External HTTP checks (curl --resolve) ==${RST}"
for s in "${SITES[@]}"; do
  code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' \
           --resolve "${s}:80:${CONTAINER_IP}" "http://${s}/" 2>/dev/null || echo 000)
  if printf '%s' "$code" | grep -qE '^(200|301|302)$'; then
    printf '  %s[PASS]%s %s -> HTTP %s\n' "$GRN" "$RST" "$s" "$code"; PASS=$((PASS+1))
  else
    printf '  %s[FAIL]%s %s -> HTTP %s\n' "$RED" "$RST" "$s" "$code"; FAIL=$((FAIL+1))
  fi
  if curl -sSL -m 12 --resolve "${s}:80:${CONTAINER_IP}" "http://${s}/" 2>/dev/null \
       | grep -qiE 'wordpress|wp-content|setup configuration file|wp-admin/(install|setup-config)'; then
    printf '  %s[PASS]%s %s serves WordPress\n' "$GRN" "$RST" "$s"; PASS=$((PASS+1))
  else
    printf '  %s[FAIL]%s %s does not look like WordPress\n' "$RED" "$RST" "$s"; FAIL=$((FAIL+1))
  fi
done

# --- 2. In-container deep checks via the Proxmox pct exec wrapper ---
echo
echo "${YLW}== In-container checks (verify.sh via pct exec) ==${RST}"
if [ -n "$PROXMOX_IP" ] && [ -n "$VMID" ] && [ -f "$VERIFY" ]; then
  B64="$(base64 -w0 "$VERIFY" 2>/dev/null || base64 "$VERIFY" | tr -d '\n')"
  SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=12"
  remote="echo ${B64} | base64 -d > /root/verify.sh && chmod +x /root/verify.sh && bash /root/verify.sh ${SITES[*]}"
  # shellcheck disable=SC2029
  if ssh ${SSH_OPTS} "${CI_USER}@${PROXMOX_IP}" "sudo pct exec ${VMID} -- sh -c '${remote}'"; then
    : # verify.sh prints its own PASS/FAIL summary and sets exit status
  else
    printf '  %s[WARN]%s in-container verify.sh reported failures (see above)\n' "$YLW" "$RST"; FAIL=$((FAIL+1))
  fi
else
  printf '  %s[SKIP]%s need --proxmox + --vmid + verify.sh to run in-container checks\n' "$YLW" "$RST"
fi

echo
printf '%s== External Summary ==%s  %sPASS=%d%s  %sFAIL=%d%s\n' "$YLW" "$RST" "$GRN" "$PASS" "$RST" "$RED" "$FAIL" "$RST"
[ "$FAIL" -eq 0 ]
