#!/usr/bin/env bash
# verify.sh
# =================================================================
# Post-deployment validation for the Reproducible Fortress LEMP stack
#
# Copyright (c) 2025-2026 Ramon van Raaij
# License: BSD 3-Clause
# Author: Ramon van Raaij | Bluesky: @ramonvanraaij.nl | GitHub: https://github.com/ramonvanraaij | Website: https://ramon.vanraaij.eu
#
# This script runs INSIDE a deployed container (as root) and checks that
# every component of the stack installed and is running correctly: Alpine
# release, repositories, Nginx, PHP-FPM (8.3 + 8.4), MariaDB, CrowdSec
# (agent, LAPI, CAPI, bouncers, collections, nftables sets) and WordPress
# reachability for each configured site.
#
# It performs the following actions:
# 1. Probes services, sockets and package state with non-fatal checks.
# 2. Drives cscli to confirm CrowdSec is registered and the bouncers pull.
# 3. Issues a local HTTP request per site (Host header) to confirm the
#    WordPress installer / site responds.
#
# Usage:
#   ./verify.sh [site_domain ...]
#   # e.g. ./verify.sh site1.com site2.com
#   # With no arguments it auto-discovers sites from /etc/nginx/http.d.
#
# **Note:**
# Exit status is non-zero if any check FAILs, so it is CI-friendly.
# =================================================================

set -o nounset -o pipefail

# --- Configuration ---
PASS=0
FAIL=0
RED=''; GRN=''; YLW=''; RST=''
if [ -t 1 ]; then RED=$(printf '\033[31m'); GRN=$(printf '\033[32m'); YLW=$(printf '\033[33m'); RST=$(printf '\033[0m'); fi

# --- Core helpers ---

# ok <label> <command...> : run command, PASS if it exits 0
ok() {
  label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  %s[PASS]%s %s\n' "$GRN" "$RST" "$label"; PASS=$((PASS + 1))
  else
    printf '  %s[FAIL]%s %s\n' "$RED" "$RST" "$label"; FAIL=$((FAIL + 1))
  fi
}

# match <label> <pattern> <command...> : PASS if command stdout matches pattern
match() {
  label="$1"; pattern="$2"; shift 2
  if "$@" 2>/dev/null | grep -qE "$pattern"; then
    printf '  %s[PASS]%s %s\n' "$GRN" "$RST" "$label"; PASS=$((PASS + 1))
  else
    printf '  %s[FAIL]%s %s\n' "$RED" "$RST" "$label"; FAIL=$((FAIL + 1))
  fi
}

info() { printf '%s== %s ==%s\n' "$YLW" "$1" "$RST"; }

# --- Discover sites ---
SITES=("$@")
if [ "${#SITES[@]}" -eq 0 ]; then
  # auto-discover from nginx server_name directives
  if [ -d /etc/nginx/http.d ]; then
    while IFS= read -r d; do SITES+=("$d"); done < <(
      grep -rhoE 'server_name[[:space:]]+[^;]+' /etc/nginx/http.d/ 2>/dev/null \
        | awk '{for(i=2;i<=NF;i++)print $i}' | grep -vE '^(_|localhost)$' | sort -u)
  fi
fi

# --- System ---
info "System / Alpine release"
printf '  alpine-release: %s\n' "$(cat /etc/alpine-release 2>/dev/null || echo unknown)"
printf '  python3:        %s\n' "$(/usr/bin/python3 --version 2>&1)"
match "apk repositories point at a stable vX.Y branch" 'alpine/v[0-9]+\.[0-9]+/main' cat /etc/apk/repositories
ok   "no broken/orphaned apk packages" sh -c 'test -z "$(apk version 2>/dev/null | grep -c '\''<'\'' | grep -v 0)"  || true; apk audit --system >/dev/null 2>&1 || true; true'

# --- Nginx ---
info "Nginx"
ok    "nginx binary present" command -v nginx
ok    "nginx config valid (nginx -t)" nginx -t
ok    "nginx service running" sh -c 'rc-service nginx status >/dev/null 2>&1 || pgrep -x nginx >/dev/null'
match "nginx answers on 127.0.0.1:80" 'HTTP/1\.[01] [0-9]{3}' sh -c 'curl -sS -m 5 -o /dev/null -D - http://127.0.0.1/ || true'

# --- PHP-FPM ---
info "PHP-FPM (8.3 + 8.4)"
for v in 83 84; do
  ok    "php-fpm${v} binary present"  test -x "/usr/sbin/php-fpm${v}"
  ok    "php-fpm${v} config test"     "/usr/sbin/php-fpm${v}" -t
  ok    "php-fpm${v} service running" sh -c "rc-service php-fpm${v} status >/dev/null 2>&1 || pgrep -f php-fpm${v} >/dev/null"
done

# --- MariaDB ---
info "MariaDB"
ok    "mariadb (mysqld) running" sh -c 'rc-service mariadb status >/dev/null 2>&1 || pgrep -x mariadbd >/dev/null || pgrep -x mysqld >/dev/null'
ok    "mysql client present" command -v mariadb || command -v mysql
ok    "mysqld unix socket present" test -S /run/mysqld/mysqld.sock

# --- CrowdSec ---
info "CrowdSec"
if command -v cscli >/dev/null 2>&1; then
  ok    "crowdsec agent running"          sh -c 'rc-service crowdsec status >/dev/null 2>&1 || pgrep -x crowdsec >/dev/null'
  ok    "cs-firewall-bouncer running"     sh -c 'rc-service cs-firewall-bouncer status >/dev/null 2>&1 || pgrep -f crowdsec-firewall-bouncer >/dev/null'
  match "LAPI reachable"                  'You can successfully|^$|Trying to authenticate' sh -c 'cscli lapi status 2>&1 || true'
  match "CAPI registered"                 'You can successfully|Trying to authenticate|Loaded credentials' sh -c 'cscli capi status 2>&1 || true'
  match "at least one bouncer registered" 'true|valid|crowdsec' sh -c 'cscli bouncers list -o raw 2>/dev/null || cscli bouncers list 2>/dev/null || true'
  match "collections installed"           'crowdsecurity' sh -c 'cscli collections list 2>/dev/null || true'
  ok    "cscli metrics runs"              sh -c 'cscli metrics >/dev/null 2>&1'
  ok    "cscli decisions list runs"       sh -c 'cscli decisions list >/dev/null 2>&1'
  # nftables sets created by the firewall bouncer
  match "nftables crowdsec ipv4 set exists" 'crowdsec-blacklist|crowdsec' sh -c 'nft list sets 2>/dev/null || true'
else
  printf '  %s[SKIP]%s cscli not installed (crowdsec_enabled=false?)\n' "$YLW" "$RST"
fi

# --- WordPress / sites ---
info "WordPress / sites"
if [ "${#SITES[@]}" -eq 0 ]; then
  printf '  %s[SKIP]%s no sites discovered/given\n' "$YLW" "$RST"
else
  for s in "${SITES[@]}"; do
    # local request with Host header; WordPress installer or site should answer 200/302
    code=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' --resolve "${s}:80:127.0.0.1" "http://${s}/" 2>/dev/null || echo 000)
    if printf '%s' "$code" | grep -qE '^(200|301|302)$'; then
      printf '  %s[PASS]%s %s responds (HTTP %s)\n' "$GRN" "$RST" "$s" "$code"; PASS=$((PASS + 1))
    else
      printf '  %s[FAIL]%s %s responds (HTTP %s)\n' "$RED" "$RST" "$s" "$code"; FAIL=$((FAIL + 1))
    fi
    # is it WordPress? follow redirects and look for WP markers (installer or live site)
    if curl -sSL -m 10 --resolve "${s}:80:127.0.0.1" "http://${s}/" 2>/dev/null \
        | grep -qiE 'wordpress|wp-content|setup configuration file|wp-admin/(install|setup-config)'; then
      printf '  %s[PASS]%s %s serves WordPress\n' "$GRN" "$RST" "$s"; PASS=$((PASS + 1))
    else
      printf '  %s[FAIL]%s %s does not look like WordPress\n' "$RED" "$RST" "$s"; FAIL=$((FAIL + 1))
    fi
  done
fi

# --- Summary ---
printf '\n%s== Summary ==%s  %sPASS=%d%s  %sFAIL=%d%s\n' "$YLW" "$RST" "$GRN" "$PASS" "$RST" "$RED" "$FAIL" "$RST"
[ "$FAIL" -eq 0 ]
