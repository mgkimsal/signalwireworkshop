#!/usr/bin/env bash
#
# Workshop Configuration
# ──────────────────────
# Sets up your API credentials and starts ngrok.
# Run this once when you first enter the container.
#
# Usage:
#   ./config.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors / Helpers ────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${BLUE}[INFO]${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }

ask() {
    local prompt="$1" default="$2" var
    if [ -n "$default" ]; then
        printf "  ${prompt} [${default}]: " >&2
    else
        printf "  ${prompt}: " >&2
    fi
    read -r var
    echo "${var:-$default}"
}

env_val() {
    local key="$1"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        grep "^${key}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2-
    fi
}

# ── Collect Credentials ────────────────────────────────────────────────────

printf "\n${BOLD}╔══════════════════════════════════════════════════════╗${RESET}\n"
printf "${BOLD}║  SignalWire Workshop — Configuration                 ║${RESET}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}\n\n"

echo "Enter your API credentials below. Press Enter to keep existing values."
echo "You can re-run this script or edit .env anytime."
echo ""

# Load existing values as defaults
sw_project=$(env_val SIGNALWIRE_PROJECT_ID)
sw_token=$(env_val SIGNALWIRE_API_TOKEN)
sw_space=$(env_val SIGNALWIRE_SPACE)
auth_user=$(env_val SWML_BASIC_AUTH_USER)
auth_pass=$(env_val SWML_BASIC_AUTH_PASSWORD)
weather_key=$(env_val WEATHER_API_KEY)
ninjas_key=$(env_val API_NINJAS_KEY)
ngrok_domain=$(env_val SWML_PROXY_URL_BASE)
ngrok_domain="${ngrok_domain#https://}"

# ── SignalWire ──

printf "${BOLD}1. SignalWire Credentials${RESET} (from your SignalWire dashboard)\n"
sw_project=$(ask "Project ID" "${sw_project}")
sw_token=$(ask "API Token" "${sw_token}")
sw_space=$(ask "Space (e.g. myspace.signalwire.com)" "${sw_space}")
echo ""

# ── Agent Auth ──

printf "${BOLD}2. Agent Authentication${RESET} (SignalWire uses these to reach your agent)\n"
auth_user=$(ask "Basic Auth User" "${auth_user:-workshop}")
auth_pass=$(ask "Basic Auth Password" "${auth_pass:-$(openssl rand -hex 8 2>/dev/null || echo changeMe123)}")
echo ""

# ── ngrok ──

printf "${BOLD}3. ngrok Tunnel${RESET} (from ngrok.com/dashboard)\n"
ngrok_token=$(ask "ngrok Authtoken" "")

if [ -n "$ngrok_token" ] && command -v ngrok &>/dev/null; then
    ngrok config add-authtoken "$ngrok_token" 2>/dev/null && ok "ngrok authtoken configured" \
        || warn "Could not configure ngrok authtoken"
fi

# Auto-detect domain from running tunnel
if [ -z "$ngrok_domain" ]; then
    _detected=$(curl -s --connect-timeout 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null \
        | grep -o '"public_url":"https://[^"]*"' | head -1 \
        | sed 's/"public_url":"https:\/\///; s/"//') || true
    if [ -n "${_detected:-}" ]; then
        ngrok_domain="$_detected"
        ok "Auto-detected ngrok domain: ${ngrok_domain}"
    fi
fi

ngrok_domain=$(ask "ngrok Static Domain (e.g. your-name.ngrok-free.app)" "${ngrok_domain}")
echo ""

# ── External APIs ──

printf "${BOLD}4. External API Keys${RESET}\n"
weather_key=$(ask "WeatherAPI key (weatherapi.com — free at weatherapi.com)" "${weather_key}")
ninjas_key=$(ask "API Ninjas key (api-ninjas.com — free at api-ninjas.com)" "${ninjas_key}")
echo ""

# ── Write .env ──────────────────────────────────────────────────────────────

proxy_url=""
if [ -n "$ngrok_domain" ]; then
    proxy_url="https://${ngrok_domain}"
fi

cat > "$SCRIPT_DIR/.env" <<ENVEOF
# SignalWire Credentials
SIGNALWIRE_PROJECT_ID=${sw_project}
SIGNALWIRE_API_TOKEN=${sw_token}
SIGNALWIRE_SPACE=${sw_space}

# Agent Authentication (used by SignalWire to reach your agent)
SWML_BASIC_AUTH_USER=${auth_user}
SWML_BASIC_AUTH_PASSWORD=${auth_pass}

# ngrok tunnel URL
SWML_PROXY_URL_BASE=${proxy_url}

# Weather API (weatherapi.com - free tier)
WEATHER_API_KEY=${weather_key}

# API Ninjas (api-ninjas.com - free tier)
API_NINJAS_KEY=${ninjas_key}
ENVEOF

ok "Saved .env"

# Symlink .env into each language dir
for dir in python typescript go ruby perl java cpp dotnet php; do
    [ -d "$SCRIPT_DIR/$dir" ] || continue
    ln -sfn "../.env" "$SCRIPT_DIR/$dir/.env" 2>/dev/null || true
done

# Java env.sh
if [ -d "$SCRIPT_DIR/java" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    {
        echo "#!/usr/bin/env bash"
        echo "# Auto-generated from ../.env"
        grep -v '^\s*#' "$SCRIPT_DIR/.env" | grep -v '^\s*$' | while IFS='=' read -r key val; do
            echo "export ${key}=\"${val}\""
        done
    } > "$SCRIPT_DIR/java/env.sh"
    chmod +x "$SCRIPT_DIR/java/env.sh"
fi

# ── Start ngrok ─────────────────────────────────────────────────────────────

if command -v ngrok &>/dev/null && command -v screen &>/dev/null && [ -n "$ngrok_domain" ]; then
    # Check if already running
    _tunnel=$(curl -s --connect-timeout 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null \
        | grep -o '"public_url":"https://[^"]*"' | head -1 \
        | sed 's/"public_url":"https:\/\///; s/"//') || true

    if [ -n "${_tunnel:-}" ]; then
        ok "ngrok already running (tunnel: ${_tunnel})"
    elif screen -ls 2>/dev/null | grep -q "workshop-ngrok"; then
        warn "screen session 'workshop-ngrok' exists but tunnel not responding"
        warn "Kill it with: screen -S workshop-ngrok -X quit"
    else
        info "Starting ngrok tunnel..."
        screen -dmS workshop-ngrok ngrok http --url="$ngrok_domain" 3000

        attempts=0
        while [ $attempts -lt 10 ]; do
            sleep 0.5
            _tunnel=$(curl -s --connect-timeout 1 http://127.0.0.1:4040/api/tunnels 2>/dev/null \
                | grep -o '"public_url":"https://[^"]*"' | head -1 \
                | sed 's/"public_url":"https:\/\///; s/"//') || true
            if [ -n "${_tunnel:-}" ]; then
                ok "ngrok tunnel active: https://${_tunnel}"
                break
            fi
            attempts=$((attempts + 1))
        done

        if [ -z "${_tunnel:-}" ]; then
            warn "ngrok started but tunnel not yet responding — check: screen -r workshop-ngrok"
        fi
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
printf "${BOLD}════════════════════════════════════════════════════════${RESET}\n"
printf "${GREEN}Configuration complete!${RESET}\n\n"

# Show SWML URL
_tunnel_domain=$(curl -s --connect-timeout 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null \
    | grep -o '"public_url":"https://[^"]*"' | head -1 \
    | sed 's/"public_url":"https:\/\///; s/"//') || true

if [ -n "${_tunnel_domain:-}" ]; then
    printf "${GREEN}✓ ngrok tunnel is running${RESET}\n\n"
    if [ -n "$auth_user" ] && [ -n "$auth_pass" ]; then
        printf "${BOLD}Your SignalWire SWML URL (paste into dashboard):${RESET}\n"
        echo "  https://${auth_user}:${auth_pass}@${_tunnel_domain}/"
        echo ""
    fi
    echo "  View tunnel:   screen -r workshop-ngrok  (detach: Ctrl-A D)"
    echo "  Stop tunnel:   screen -S workshop-ngrok -X quit"
    echo "  ngrok web UI:  http://localhost:4040"
else
    if [ -n "$ngrok_domain" ]; then
        echo "  Start tunnel:  ngrok http --url=${ngrok_domain} 3000"
    fi
fi

echo ""
printf "${BOLD}Run an agent:${RESET}\n"
echo "  cd python && source venv/bin/activate && python steps/step04_hello_agent.py"
echo ""
echo "Type 'help' for all language commands."
echo ""
