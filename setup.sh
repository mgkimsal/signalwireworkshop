#!/usr/bin/env bash
#
# Workshop Setup Script
# ─────────────────────
# Clones all SDKs, builds them, and wires each language to use the local copy.
#
# Usage:
#   ./setup.sh                 # set up all languages
#   ./setup.sh python go       # set up specific languages only
#   ./setup.sh --auto python   # auto-install missing deps (no prompt)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="$SCRIPT_DIR/sdks"
REPO_BASE="https://github.com/signalwire"

ALL_LANGS=(python typescript go ruby perl java cpp dotnet php)

# Parse flags and language arguments
AUTO_INSTALL=false
if [ $# -gt 0 ]; then
    LANGS=()
    for arg in "$@"; do
        case "$arg" in
            --auto) AUTO_INSTALL=true ;;
            -*)     echo "Unknown flag: $arg" >&2; exit 1 ;;
            *)
                # Strip trailing slash (e.g. "java/" → "java") and validate
                arg="${arg%/}"
                valid=false
                for l in "${ALL_LANGS[@]}"; do [[ "$l" == "$arg" ]] && valid=true; done
                if [ "$valid" = true ]; then
                    LANGS+=("$arg")
                else
                    echo "Unknown language: $arg" >&2
                    echo "Valid languages: ${ALL_LANGS[*]}" >&2
                    exit 1
                fi
                ;;
        esac
    done
    if [ ${#LANGS[@]} -eq 0 ]; then
        LANGS=("${ALL_LANGS[@]}")
    fi
else
    LANGS=("${ALL_LANGS[@]}")
fi

# ── Colors / Helpers ─────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${BLUE}[INFO]${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${RESET} %s\n" "$*"; }

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        warn "Required tool '$1' not found — $2 setup will be skipped"
        return 1
    fi
    return 0
}

check_version() {
    local tool="$1" required="$2" actual="$3" label="$4"
    if [ "$(printf '%s\n%s' "$required" "$actual" | sort -V | head -1)" = "$required" ]; then
        return 0
    else
        warn "$label requires $tool $required+ but found $actual"
        return 1
    fi
}

lang_enabled() {
    local lang="$1"
    for l in "${LANGS[@]}"; do
        [[ "$l" == "$lang" ]] && return 0
    done
    return 1
}

clone_sdk() {
    local lang="$1"
    local target="$SDK_DIR/signalwire-${lang}"
    if [ -d "$target" ]; then
        info "Updating signalwire-${lang}..."
        (cd "$target" && git pull --ff-only -q 2>/dev/null) || warn "Could not update signalwire-${lang} (offline?)"
    else
        info "Cloning signalwire-${lang}..."
        git clone --depth 1 "${REPO_BASE}/signalwire-${lang}.git" "$target"
    fi
}

# ── Platform Detection ──────────────────────────────────────────────────────

_detect_platform() {
    case "$(uname -s)" in
        Darwin) PLATFORM=macos ;;
        Linux)  PLATFORM=linux ;;
        *)      PLATFORM=unknown ;;
    esac
}

_has_brew() { command -v brew &>/dev/null; }
_has_apt()  { command -v apt-get &>/dev/null; }

# ── WSL Checks ──────────────────────────────────────────────────────────────

_wsl_checks() {
    [ "$PLATFORM" = linux ] || return 0
    grep -qi microsoft /proc/version 2>/dev/null || return 0

    # Warn if running from /mnt/c/
    if [[ "$SCRIPT_DIR" == /mnt/* ]]; then
        warn "Running from Windows filesystem ($SCRIPT_DIR)"
        warn "This will be slow and may cause permission errors."
        warn "Recommendation: cd ~ && git clone <repo> workshop && cd workshop"
        echo ""
    fi

    # Check for CRLF line endings
    if head -1 "$0" | grep -q $'\r'; then
        warn "setup.sh has Windows (CRLF) line endings"
        if command -v dos2unix &>/dev/null; then
            info "Fixing with dos2unix..."
            dos2unix "$0" 2>/dev/null
            warn "Fixed! Please re-run: ./setup.sh ${LANGS[*]}"
            exit 1
        else
            warn "Fix with: sudo apt install -y dos2unix && dos2unix setup.sh test.sh"
            exit 1
        fi
    fi
}

# ── Dependency Installer ────────────────────────────────────────────────────

install_deps() {
    _detect_platform
    if [ "$PLATFORM" = unknown ]; then
        warn "Unknown platform ($(uname -s)) — skipping dependency check"
        return 0
    fi

    _wsl_checks

    local missing_brew=()
    local missing_apt=()
    local need_node=false
    local need_go=false
    local need_dotnet=false
    local need_composer=false
    local need_bundler=false
    local missing_names=()

    # ── Base tools (always checked) ──
    if [ "$PLATFORM" = macos ]; then
        command -v jq &>/dev/null || { missing_brew+=(jq); missing_names+=("jq"); }
    else
        for tool in git curl wget jq; do
            command -v "$tool" &>/dev/null || { missing_apt+=("$tool"); missing_names+=("$tool"); }
        done
        dpkg -s build-essential &>/dev/null 2>&1 || { missing_apt+=(build-essential); missing_names+=("build-essential"); }
    fi

    # ── Per-language checks ──
    if lang_enabled python; then
        if ! command -v python3 &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(python@3.12); missing_names+=("python@3.12")
            else
                missing_apt+=(python3 python3-venv python3-pip); missing_names+=("python3 + venv/pip")
            fi
        elif [ "$PLATFORM" = linux ]; then
            dpkg -s python3-venv &>/dev/null 2>&1 || { missing_apt+=(python3-venv); missing_names+=("python3-venv"); }
            dpkg -s python3-pip &>/dev/null 2>&1  || { missing_apt+=(python3-pip); missing_names+=("python3-pip"); }
        fi
    fi

    if lang_enabled typescript; then
        if ! command -v node &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(node@20); missing_names+=("node@20")
            else
                need_node=true; missing_names+=("nodejs 20 (via NodeSource)")
            fi
        fi
    fi

    if lang_enabled go; then
        if ! command -v go &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(go); missing_names+=("go")
            else
                need_go=true; missing_names+=("go (official tarball)")
            fi
        fi
    fi

    if lang_enabled ruby; then
        if ! command -v ruby &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(ruby); missing_names+=("ruby")
            else
                missing_apt+=(ruby-full); missing_names+=("ruby-full")
            fi
        fi
        if ! command -v bundle &>/dev/null; then
            need_bundler=true
            command -v ruby &>/dev/null && missing_names+=("bundler (gem)")
        fi
    fi

    if lang_enabled perl; then
        if [ "$PLATFORM" = macos ]; then
            command -v perl &>/dev/null  || { missing_brew+=(perl); missing_names+=("perl"); }
            command -v cpanm &>/dev/null || { missing_brew+=(cpanminus); missing_names+=("cpanminus"); }
        else
            command -v perl &>/dev/null  || { missing_apt+=(perl); missing_names+=("perl"); }
            command -v cpanm &>/dev/null || { missing_apt+=(cpanminus); missing_names+=("cpanminus"); }
            # libssl-dev needed to compile Net::SSLeay → IO::Socket::SSL
            dpkg -s libssl-dev &>/dev/null 2>&1 || { missing_apt+=(libssl-dev); missing_names+=("libssl-dev"); }
        fi
    fi

    if lang_enabled java; then
        local have_java=false
        if command -v java &>/dev/null; then
            local jver_raw jver
            jver_raw=$(java -version 2>&1 | head -1 | grep -o '"[^"]*"' | tr -d '"')
            jver=$(echo "$jver_raw" | awk -F. '{ if ($1 == 1) print $2; else print $1 }')
            [ "${jver:-0}" -ge 21 ] && have_java=true
        fi
        if [ "$have_java" = false ]; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(openjdk@21); missing_names+=("openjdk@21")
            else
                missing_apt+=(openjdk-21-jdk); missing_names+=("openjdk-21-jdk")
            fi
        fi
    fi

    if lang_enabled cpp; then
        if ! command -v cmake &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(cmake); missing_names+=("cmake")
            else
                missing_apt+=(cmake); missing_names+=("cmake")
            fi
        fi
        if [ "$PLATFORM" = linux ]; then
            command -v g++ &>/dev/null                     || { missing_apt+=(g++); missing_names+=("g++"); }
            dpkg -s libcurl4-openssl-dev &>/dev/null 2>&1  || { missing_apt+=(libcurl4-openssl-dev); missing_names+=("libcurl4-openssl-dev"); }
            dpkg -s nlohmann-json3-dev &>/dev/null 2>&1    || { missing_apt+=(nlohmann-json3-dev); missing_names+=("nlohmann-json3-dev"); }
        fi
    fi

    if lang_enabled dotnet; then
        if ! command -v dotnet &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(dotnet@8); missing_names+=("dotnet@8")
            else
                need_dotnet=true; missing_names+=("dotnet-sdk-8.0 (via Microsoft repo)")
            fi
        fi
    fi

    if lang_enabled php; then
        if ! command -v php &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(php); missing_names+=("php")
            else
                missing_apt+=(php-cli php-mbstring php-xml php-curl); missing_names+=("php + extensions")
            fi
        fi
        if ! command -v composer &>/dev/null; then
            if [ "$PLATFORM" = macos ]; then
                missing_brew+=(composer); missing_names+=("composer")
            else
                need_composer=true; missing_names+=("composer (via installer)")
            fi
        fi
    fi

    # ── Nothing missing? ──
    local total=$(( ${#missing_brew[@]} + ${#missing_apt[@]} ))
    [ "$need_node" = true ]     && total=$((total + 1))
    [ "$need_go" = true ]       && total=$((total + 1))
    [ "$need_dotnet" = true ]   && total=$((total + 1))
    [ "$need_composer" = true ] && total=$((total + 1))
    if [ "$total" -eq 0 ] && [ "$need_bundler" = false ]; then
        ok "All dependencies already installed"
        return 0
    fi

    # ── Show what's missing and ask ──
    printf "\n${BOLD}Missing Dependencies${RESET}\n"
    printf "The following will be installed:\n"
    for name in "${missing_names[@]}"; do
        printf "  • %s\n" "$name"
    done
    echo ""

    if [ "$AUTO_INSTALL" = false ]; then
        printf "Install missing dependencies? [Y/n] "
        read -r answer
        case "$answer" in
            [nN]*) warn "Skipping dependency install — some languages may fail to set up"; return 0 ;;
        esac
    fi

    # ── macOS: brew install ──
    if [ "$PLATFORM" = macos ]; then
        if [ ${#missing_brew[@]} -gt 0 ]; then
            if _has_brew; then
                info "Running: brew install ${missing_brew[*]}"
                brew install "${missing_brew[@]}"
            else
                err "Homebrew not found. Install it first: https://brew.sh/"
                return 1
            fi
        fi
    fi

    # ── Linux: apt + special cases ──
    if [ "$PLATFORM" = linux ]; then
        if [ ${#missing_apt[@]} -gt 0 ]; then
            if _has_apt; then
                info "Running: sudo apt install -y ${missing_apt[*]}"
                sudo apt-get update -qq
                sudo apt-get install -y "${missing_apt[@]}"
            else
                err "apt-get not found. Install packages manually: ${missing_apt[*]}"
                return 1
            fi
        fi

        # Node.js via NodeSource
        if [ "$need_node" = true ]; then
            info "Installing Node.js 20 via NodeSource..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        fi

        # Go via official tarball
        if [ "$need_go" = true ]; then
            local go_version="1.26.1"
            local go_arch
            go_arch=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
            info "Installing Go ${go_version} (${go_arch})..."
            wget -q "https://go.dev/dl/go${go_version}.linux-${go_arch}.tar.gz" -O /tmp/go.tar.gz
            sudo rm -rf /usr/local/go
            sudo tar -C /usr/local -xzf /tmp/go.tar.gz
            rm -f /tmp/go.tar.gz
            export PATH="/usr/local/go/bin:$PATH"
            ok "Go installed to /usr/local/go"
            if ! grep -q '/usr/local/go/bin' ~/.bashrc 2>/dev/null; then
                echo 'export PATH="/usr/local/go/bin:$PATH"' >> ~/.bashrc
                info "Added Go to ~/.bashrc — run 'source ~/.bashrc' in new shells"
            fi
        fi

        # .NET SDK via Microsoft repo
        if [ "$need_dotnet" = true ]; then
            info "Installing .NET SDK 8.0 via Microsoft repo..."
            wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs 2>/dev/null || echo 24.04)/packages-microsoft-prod.deb" \
                -O /tmp/packages-microsoft-prod.deb
            sudo dpkg -i /tmp/packages-microsoft-prod.deb
            rm -f /tmp/packages-microsoft-prod.deb
            sudo apt-get update -qq
            sudo apt-get install -y dotnet-sdk-8.0
            ok ".NET SDK 8.0 installed"
        fi

        # Composer via official installer
        if [ "$need_composer" = true ] && command -v php &>/dev/null; then
            info "Installing Composer..."
            curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 2>/dev/null \
                || sudo bash -c 'curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer'
            ok "Composer installed"
        fi
    fi

    # Ruby bundler (both platforms)
    if [ "$need_bundler" = true ] && command -v ruby &>/dev/null; then
        if ! command -v bundle &>/dev/null; then
            info "Installing bundler..."
            gem install bundler 2>/dev/null || sudo gem install bundler
        fi
    fi

    ok "Dependencies installed"
    echo ""
}

NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

# ── .env Setup ───────────────────────────────────────────────────────────────

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

# Read existing .env value if present
env_val() {
    local key="$1"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        grep "^${key}=" "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2-
    fi
}

setup_env_file() {
    local existing=false
    if [ -f "$SCRIPT_DIR/.env" ]; then
        existing=true
    fi

    # Check if .env has real values or just placeholders
    local needs_setup=false
    if [ "$existing" = false ]; then
        needs_setup=true
    elif grep -q "your-.*-here" "$SCRIPT_DIR/.env" 2>/dev/null; then
        needs_setup=true
    fi

    if [ "$needs_setup" = true ]; then
        printf "\n${BOLD}Environment Setup${RESET}\n"
        echo "Let's configure your API keys. Press Enter to keep defaults/existing values."
        echo "You can always edit .env later."
        echo ""

        # Load existing values as defaults
        local sw_project sw_token sw_space auth_user auth_pass weather_key ninjas_key
        local ngrok_token ngrok_domain

        sw_project=$(env_val SIGNALWIRE_PROJECT_ID)
        sw_token=$(env_val SIGNALWIRE_API_TOKEN)
        sw_space=$(env_val SIGNALWIRE_SPACE)
        auth_user=$(env_val SWML_BASIC_AUTH_USER)
        auth_pass=$(env_val SWML_BASIC_AUTH_PASSWORD)
        weather_key=$(env_val WEATHER_API_KEY)
        ninjas_key=$(env_val API_NINJAS_KEY)
        ngrok_domain=$(env_val SWML_PROXY_URL_BASE)
        # Strip https:// prefix for the prompt default
        ngrok_domain="${ngrok_domain#https://}"

        printf "${BOLD}SignalWire Credentials${RESET} (from dashboard.signalwire.com)\n"
        sw_project=$(ask "Project ID" "${sw_project}")
        sw_token=$(ask "API Token" "${sw_token}")
        sw_space=$(ask "Space (e.g. myspace.signalwire.com)" "${sw_space}")
        echo ""

        printf "${BOLD}Agent Authentication${RESET} (SignalWire uses these to reach your agent)\n"
        auth_user=$(ask "Basic Auth User" "${auth_user:-workshop}")
        auth_pass=$(ask "Basic Auth Password" "${auth_pass:-$(openssl rand -hex 8 2>/dev/null || echo changeMe123)}")
        echo ""

        printf "${BOLD}ngrok Tunnel${RESET} (ngrok.com — exposes your agent to the internet)\n"
        ngrok_token=$(ask "ngrok Authtoken (from ngrok.com/dashboard)" "")

        # Configure ngrok auth if token provided
        if [ -n "$ngrok_token" ] && command -v ngrok &>/dev/null; then
            ngrok config add-authtoken "$ngrok_token" 2>/dev/null && ok "ngrok authtoken configured" \
                || warn "Could not configure ngrok authtoken"
        fi

        # Try to auto-detect domain from a running ngrok tunnel
        if [ -z "$ngrok_domain" ]; then
            local _detected
            _detected=$(curl -s --connect-timeout 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null \
                | grep -o '"public_url":"https://[^"]*"' | head -1 \
                | sed 's/"public_url":"https:\/\///; s/"//') || true
            if [ -n "$_detected" ]; then
                ngrok_domain="$_detected"
                ok "Auto-detected ngrok domain: ${ngrok_domain}"
            fi
        fi

        ngrok_domain=$(ask "ngrok Static Domain (e.g. your-name.ngrok-free.app)" "${ngrok_domain}")
        echo ""

        printf "${BOLD}External API Keys${RESET} (optional — needed for steps 7+)\n"
        weather_key=$(ask "WeatherAPI key (weatherapi.com)" "${weather_key}")
        ninjas_key=$(ask "API Ninjas key (api-ninjas.com)" "${ninjas_key}")
        echo ""

        # Build SWML_PROXY_URL_BASE from domain if provided
        local proxy_url=""
        if [ -n "$ngrok_domain" ]; then
            proxy_url="https://${ngrok_domain}"
        fi

        # Write .env
        cat > "$SCRIPT_DIR/.env" <<ENVEOF
# SignalWire Credentials
SIGNALWIRE_PROJECT_ID=${sw_project}
SIGNALWIRE_API_TOKEN=${sw_token}
SIGNALWIRE_SPACE=${sw_space}

# Agent Authentication (used by SignalWire to reach your agent)
SWML_BASIC_AUTH_USER=${auth_user}
SWML_BASIC_AUTH_PASSWORD=${auth_pass}

# ngrok tunnel URL (used when auto-detection isn't available, e.g. Docker)
SWML_PROXY_URL_BASE=${proxy_url}

# Weather API (weatherapi.com - free tier)
WEATHER_API_KEY=${weather_key}

# API Ninjas (api-ninjas.com - free tier)
API_NINJAS_KEY=${ninjas_key}
ENVEOF
        ok "Wrote .env with your credentials"

        # Show the SWML URL they'll paste into SignalWire dashboard
        if [ -n "$proxy_url" ] && [ -n "$auth_user" ] && [ -n "$auth_pass" ]; then
            printf "\n${BOLD}Your SignalWire SWML URL:${RESET}\n"
            echo "  https://${auth_user}:${auth_pass}@${ngrok_domain}/"
            echo ""
            echo "  Paste this into your phone number's SWML URL field in the SignalWire dashboard."
            echo ""
        fi
    else
        ok ".env already configured"
    fi

    # Symlink .env into each language dir so agents find it
    for lang in "${LANGS[@]}"; do
        local dir="$SCRIPT_DIR/$lang"
        [ -d "$dir" ] || continue
        if [ ! -e "$dir/.env" ] && [ -f "$SCRIPT_DIR/.env" ]; then
            ln -sfn "../.env" "$dir/.env"
        fi
    done

    # Java uses env.sh (source-able), not dotenv
    if lang_enabled java && [ -f "$SCRIPT_DIR/.env" ]; then
        {
            echo "#!/usr/bin/env bash"
            echo "# Auto-generated from ../.env — source this before running Java agents"
            grep -v '^\s*#' "$SCRIPT_DIR/.env" | grep -v '^\s*$' | while IFS='=' read -r key val; do
                echo "export ${key}=\"${val}\""
            done
        } > "$SCRIPT_DIR/java/env.sh"
        chmod +x "$SCRIPT_DIR/java/env.sh"
    fi
}

# ── Prerequisite Checks ──────────────────────────────────────────────────────

check_ngrok() {
    if command -v ngrok &>/dev/null; then
        ok "ngrok found"
    else
        warn "ngrok not found — agents need it to receive calls from SignalWire"
        warn "Install: https://ngrok.com/download"
    fi
}

# ── Clone SDKs ───────────────────────────────────────────────────────────────

printf "\n${BOLD}SignalWire Workshop Setup${RESET}\n"
printf "════════════════════════════════════════\n"
printf "Languages: %s\n" "${LANGS[*]}"
printf "════════════════════════════════════════\n\n"

install_deps
check_ngrok
setup_env_file
echo ""

mkdir -p "$SDK_DIR"

for lang in "${LANGS[@]}"; do
    clone_sdk "$lang"
done

echo ""

# ── Python ───────────────────────────────────────────────────────────────────

if lang_enabled python; then
    info "Setting up Python..."
    if check_tool python3 Python; then
        pyver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
        if check_version python3 "3.10" "$pyver" Python; then
            if [ ! -d "$SCRIPT_DIR/python/venv" ]; then
                info "Creating Python venv..."
                if ! python3 -m venv "$SCRIPT_DIR/python/venv"; then
                    err "Failed to create venv — on Ubuntu/Debian, install: sudo apt install python3-venv python3.${pyver#*.}-venv"
                    PYTHON_OK=false
                fi
            fi
            if [ "${PYTHON_OK:-true}" = false ] || [ ! -f "$SCRIPT_DIR/python/venv/bin/activate" ]; then
                warn "Skipping Python setup (venv not available)"
            else
                source "$SCRIPT_DIR/python/venv/bin/activate"
                pip install -q -r "$SCRIPT_DIR/python/requirements.txt"
                pip install -q -e "$SDK_DIR/signalwire-python"
                ok "Python SDK installed (editable mode) — activate with: source python/venv/bin/activate"
            fi
        fi
    fi
    echo ""
fi

# ── TypeScript ───────────────────────────────────────────────────────────────

if lang_enabled typescript; then
    info "Setting up TypeScript..."
    if check_tool node TypeScript && check_tool npm TypeScript; then
        nodever=$(node -v 2>/dev/null | sed 's/^v//')
        if check_version node "18.0.0" "$nodever" TypeScript; then
            (cd "$SDK_DIR/signalwire-typescript" && npm install --silent && npm run build --silent)
            (cd "$SCRIPT_DIR/typescript" && npm install --silent)
            ok "TypeScript SDK built and linked"
        fi
    fi
    echo ""
fi

# ── Go ───────────────────────────────────────────────────────────────────────

if lang_enabled go; then
    info "Setting up Go..."
    if check_tool go Go; then
        gover=$(go version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]*' | head -1)
        if check_version go "1.22" "${gover:-0.0}" Go; then
            (cd "$SCRIPT_DIR/go" && go mod tidy 2>/dev/null)
            ok "Go SDK linked via go.mod replace directive"
        fi
    fi
    echo ""
fi

# ── Ruby ─────────────────────────────────────────────────────────────────────

if lang_enabled ruby; then
    info "Setting up Ruby..."
    if check_tool ruby Ruby && check_tool bundle Ruby; then
        (cd "$SCRIPT_DIR/ruby" && bundle config set --local path vendor/bundle 2>/dev/null && bundle install --quiet)
        ok "Ruby SDK installed via Gemfile path directive"
    fi
    echo ""
fi

# ── Perl ─────────────────────────────────────────────────────────────────────

if lang_enabled perl; then
    info "Setting up Perl..."
    if check_tool perl Perl; then
        PERL_LOCAL="$SDK_DIR/signalwire-perl/local"
        PERL_LOCAL_BIN="$PERL_LOCAL/bin"
        mkdir -p "$PERL_LOCAL_BIN"

        # Find or bootstrap cpanm locally
        CPANM=""
        if command -v cpanm &>/dev/null; then
            CPANM=cpanm
        elif [ -x "$PERL_LOCAL_BIN/cpanm" ]; then
            CPANM="$PERL_LOCAL_BIN/cpanm"
        else
            info "Downloading cpanm to $PERL_LOCAL_BIN..."
            if curl -sL https://cpanmin.us -o "$PERL_LOCAL_BIN/cpanm" && chmod +x "$PERL_LOCAL_BIN/cpanm"; then
                CPANM="$PERL_LOCAL_BIN/cpanm"
                ok "cpanm bootstrapped locally"
            else
                warn "Could not download cpanm — install it: brew install cpanminus (macOS) or sudo apt install cpanminus (Linux)"
            fi
        fi

        PERL_DEPS_OK=true
        if [ -n "$CPANM" ]; then
            $CPANM --quiet --notest --local-lib "$PERL_LOCAL" --installdeps "$SDK_DIR/signalwire-perl" \
                || { warn "cpanm installdeps for SDK failed — re-run without --quiet for details"; PERL_DEPS_OK=false; }
            (cd "$SCRIPT_DIR/perl" && $CPANM --quiet --notest --local-lib "$PERL_LOCAL" --installdeps .) \
                || { warn "cpanm installdeps for workshop failed"; PERL_DEPS_OK=false; }
        else
            PERL_DEPS_OK=false
        fi

        # Create symlink: perl/lib -> SDK lib directory
        ln -sfn "../sdks/signalwire-perl/lib" "$SCRIPT_DIR/perl/lib"
        ok "Perl SDK symlinked at perl/lib"
        if [ "$PERL_DEPS_OK" = true ]; then
            ok "Perl deps installed to $PERL_LOCAL"
        fi
    fi
    echo ""
fi

# ── Java ─────────────────────────────────────────────────────────────────────

if lang_enabled java; then
    info "Setting up Java..."
    # Prefer workshop's gradlew (Gradle 8.x) — the SDK ships Gradle 9.x
    # which is incompatible with its maven-publish plugin
    GRADLE_CMD=""
    if [ -f "$SCRIPT_DIR/java/gradlew" ]; then
        chmod +x "$SCRIPT_DIR/java/gradlew"
        GRADLE_CMD="$SCRIPT_DIR/java/gradlew"
    elif command -v gradle &>/dev/null; then
        GRADLE_CMD="gradle"
    elif [ -f "$SDK_DIR/signalwire-java/gradlew" ]; then
        chmod +x "$SDK_DIR/signalwire-java/gradlew"
        GRADLE_CMD="$SDK_DIR/signalwire-java/gradlew"
    fi

    if [ -n "$GRADLE_CMD" ]; then
        # Auto-detect brew openjdk on macOS if JAVA_HOME isn't set or points to old Java
        _detect_java_home() {
            local raw major
            raw=$(java -version 2>&1 | head -1 | grep -o '"[^"]*"' | tr -d '"')
            major=$(echo "$raw" | awk -F. '{ if ($1 == 1) print $2; else print $1 }')
            if [ "${major:-0}" -ge 21 ]; then
                return 0
            fi
            # Try brew openjdk
            if command -v brew &>/dev/null; then
                local brew_jdk
                brew_jdk="$(brew --prefix openjdk 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
                if [ -d "$brew_jdk" ]; then
                    export JAVA_HOME="$brew_jdk"
                    export PATH="$JAVA_HOME/bin:$PATH"
                    info "Using brew openjdk: $JAVA_HOME"
                    return 0
                fi
            fi
            # Try /usr/lib/jvm on Linux
            if [ -d /usr/lib/jvm ]; then
                local jh
                jh=$(find /usr/lib/jvm -maxdepth 1 -type d \( -name '*java-2[1-9]*' -o -name '*java-[3-9][0-9]*' \) 2>/dev/null \
                    | sort -V | tail -1)
                if [ -n "$jh" ] && [ -d "$jh" ]; then
                    export JAVA_HOME="$jh"
                    export PATH="$JAVA_HOME/bin:$PATH"
                    info "Using Java from /usr/lib/jvm: $JAVA_HOME"
                    return 0
                fi
            fi
            # Try /usr/libexec/java_home on macOS
            if [ -x /usr/libexec/java_home ]; then
                local jh
                jh=$(/usr/libexec/java_home -v 21+ 2>/dev/null || true)
                if [ -n "$jh" ] && [ -d "$jh" ]; then
                    export JAVA_HOME="$jh"
                    export PATH="$JAVA_HOME/bin:$PATH"
                    info "Using Java from: $JAVA_HOME"
                    return 0
                fi
            fi
            return 1
        }
        _detect_java_home

        javaver_raw=$(java -version 2>&1 | head -1 | grep -o '"[^"]*"' | tr -d '"')
        javaver=$(echo "$javaver_raw" | awk -F. '{ if ($1 == 1) print $2; else print $1 }')
        if [ "${javaver:-0}" -lt 21 ]; then
            warn "Java 21+ required but found version ${javaver_raw:-unknown}"
        else
            (cd "$SDK_DIR/signalwire-java" && $GRADLE_CMD jar --console=plain -q)
            mkdir -p "$SCRIPT_DIR/java/libs"
            cp "$SDK_DIR/signalwire-java/build/libs/signalwire-"*.jar \
               "$SCRIPT_DIR/java/libs/" 2>/dev/null || warn "Could not copy SDK jar"
            # Copy gradlew wrapper into java/ so users don't need system gradle
            if [ ! -f "$SCRIPT_DIR/java/gradlew" ]; then
                cp "$SDK_DIR/signalwire-java/gradlew" "$SCRIPT_DIR/java/gradlew"
                chmod +x "$SCRIPT_DIR/java/gradlew"
                mkdir -p "$SCRIPT_DIR/java/gradle/wrapper"
                cp "$SDK_DIR/signalwire-java/gradle/wrapper/"* "$SCRIPT_DIR/java/gradle/wrapper/"
            fi
            ok "Java SDK jar built and copied to java/libs/"
        fi
    else
        warn "Neither gradle nor gradlew found — Java setup skipped"
    fi
    echo ""
fi

# ── C++ ──────────────────────────────────────────────────────────────────────

if lang_enabled cpp; then
    info "Setting up C++..."
    if check_tool cmake C++; then
        SDK_CPP="$SDK_DIR/signalwire-cpp"
        if [ ! -f "$SDK_CPP/build/libsignalwire.a" ]; then
            mkdir -p "$SDK_CPP/build"
            (cd "$SDK_CPP/build" && cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -3 && \
             make -j"$NCPU" 2>&1 | tail -3)
            ok "C++ SDK built"
        else
            ok "C++ SDK already built"
        fi
    fi
    echo ""
fi

# ── .NET ────────────────────────────────────────────────────────────────────

if lang_enabled dotnet; then
    info "Setting up .NET..."
    if check_tool dotnet .NET; then
        dotnetver=$(dotnet --version 2>/dev/null | cut -d. -f1)
        if [ "${dotnetver:-0}" -ge 8 ]; then
            # Build only net8.0 target (SDK multi-targets net8.0/net9.0/net10.0)
            (cd "$SDK_DIR/signalwire-dotnet" && dotnet build src/SignalWire/SignalWire.csproj -c Release -p:TargetFrameworks=net8.0 --nologo -v q 2>&1 | tail -3)
            ok ".NET SDK built"
        else
            warn ".NET 8.0+ required but found $(dotnet --version 2>/dev/null || echo unknown)"
        fi
    fi
    echo ""
fi

# ── PHP ─────────────────────────────────────────────────────────────────────

if lang_enabled php; then
    info "Setting up PHP..."
    if check_tool php PHP; then
        phpver=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || echo "0.0")
        if check_version php "8.1" "$phpver" PHP; then
            if check_tool composer PHP; then
                (cd "$SDK_DIR/signalwire-php" && composer install --quiet --no-interaction 2>&1 | tail -3)
                ok "PHP SDK dependencies installed"
            fi
        fi
    fi
    echo ""
fi

# ── Summary ──────────────────────────────────────────────────────────────────

printf "${BOLD}════════════════════════════════════════${RESET}\n"
printf "${GREEN}Setup complete for: ${LANGS[*]}${RESET}\n\n"

printf "${BOLD}Next steps:${RESET}\n"
step=1
# Only mention .env if it still has placeholders or is empty
if [ ! -f "$SCRIPT_DIR/.env" ] || grep -q "your-.*-here" "$SCRIPT_DIR/.env" 2>/dev/null; then
    echo "  $step. Edit .env with your SignalWire credentials and API keys"
    step=$((step + 1))
fi
if ! command -v ngrok &>/dev/null; then
    echo "  $step. Install ngrok: https://ngrok.com/download"
    step=$((step + 1))
fi
# Show ngrok start command with their static domain if configured
_domain=$(env_val SWML_PROXY_URL_BASE)
_domain="${_domain#https://}"
if [ -n "$_domain" ]; then
    echo "  $step. Start tunnel:  ngrok http --url=${_domain} 3000"
else
    echo "  $step. Start tunnel:  ngrok http 3000"
fi
echo ""
printf "${BOLD}Run an agent:${RESET}\n"

for lang in "${LANGS[@]}"; do
    case "$lang" in
        python)     echo "  Python:     cd python && source venv/bin/activate && python steps/step04_hello_agent.py" ;;
        typescript) echo "  TypeScript: cd typescript && npx tsx steps/step04_hello_agent.ts" ;;
        go)         echo "  Go:         cd go && go run ./steps/step04_hello_agent" ;;
        ruby)       echo "  Ruby:       cd ruby && bundle exec ruby steps/step04_hello_agent.rb" ;;
        perl)       echo "  Perl:       cd perl && PERL5LIB=../sdks/signalwire-perl/local/lib/perl5 perl steps/step04_hello_agent.pl" ;;
        java)       echo "  Java:       cd java && source env.sh && cp steps/Step04HelloAgent.java src/main/java/HelloAgent.java && ./gradlew run -PmainClass=HelloAgent --console=plain" ;;
        cpp)        echo "  C++:        cd cpp && cp steps/step04_hello_agent.cpp agent.cpp && cd build && cmake .. && make && ./agent" ;;
        dotnet)     echo "  .NET:       cd dotnet && dotnet run" ;;
        php)        echo "  PHP:        cd php && php steps/step04_hello_agent.php" ;;
    esac
done

echo ""
printf "${BOLD}Run tests:${RESET}\n"
echo "  ./test.sh"
echo "  ./test.sh python go"
echo ""
