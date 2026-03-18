#!/usr/bin/env bash
#
# Workshop Setup Script
# ─────────────────────
# Clones all SDKs, builds them, and wires each language to use the local copy.
#
# Usage:
#   ./setup.sh                 # set up all languages
#   ./setup.sh python go       # set up specific languages only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="$SCRIPT_DIR/sdks"
REPO_BASE="https://github.com/signalwire"

ALL_LANGS=(python typescript go ruby perl java cpp)

# If arguments given, only set up those languages; otherwise all
if [ $# -gt 0 ]; then
    LANGS=("$@")
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
    local target="$SDK_DIR/signalwire-agents-${lang}"
    if [ -d "$target" ]; then
        info "Already cloned: signalwire-agents-${lang}"
    else
        info "Cloning signalwire-agents-${lang}..."
        git clone --depth 1 "${REPO_BASE}/signalwire-agents-${lang}.git" "$target"
    fi
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

        sw_project=$(env_val SIGNALWIRE_PROJECT_ID)
        sw_token=$(env_val SIGNALWIRE_API_TOKEN)
        sw_space=$(env_val SIGNALWIRE_SPACE)
        auth_user=$(env_val SWML_BASIC_AUTH_USER)
        auth_pass=$(env_val SWML_BASIC_AUTH_PASSWORD)
        weather_key=$(env_val WEATHER_API_KEY)
        ninjas_key=$(env_val API_NINJAS_KEY)

        printf "${BOLD}SignalWire Credentials${RESET} (from dashboard.signalwire.com)\n"
        sw_project=$(ask "Project ID" "${sw_project}")
        sw_token=$(ask "API Token" "${sw_token}")
        sw_space=$(ask "Space (e.g. myspace.signalwire.com)" "${sw_space}")
        echo ""

        printf "${BOLD}Agent Authentication${RESET} (SignalWire uses these to reach your agent)\n"
        auth_user=$(ask "Basic Auth User" "${auth_user:-workshop}")
        auth_pass=$(ask "Basic Auth Password" "${auth_pass:-$(openssl rand -hex 8 2>/dev/null || echo changeMe123)}")
        echo ""

        printf "${BOLD}External API Keys${RESET} (optional — needed for steps 7+)\n"
        weather_key=$(ask "WeatherAPI key (weatherapi.com)" "${weather_key}")
        ninjas_key=$(ask "API Ninjas key (api-ninjas.com)" "${ninjas_key}")
        echo ""

        # Write .env
        cat > "$SCRIPT_DIR/.env" <<ENVEOF
# SignalWire Credentials
SIGNALWIRE_PROJECT_ID=${sw_project}
SIGNALWIRE_API_TOKEN=${sw_token}
SIGNALWIRE_SPACE=${sw_space}

# Agent Authentication (used by SignalWire to reach your agent)
SWML_BASIC_AUTH_USER=${auth_user}
SWML_BASIC_AUTH_PASSWORD=${auth_pass}

# ngrok: auto-detected at startup. Uncomment only if not using ngrok.
# SWML_PROXY_URL_BASE=https://your-server.example.com

# Weather API (weatherapi.com - free tier)
WEATHER_API_KEY=${weather_key}

# API Ninjas (api-ninjas.com - free tier)
API_NINJAS_KEY=${ninjas_key}
ENVEOF
        ok "Wrote .env with your credentials"
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
                python3 -m venv "$SCRIPT_DIR/python/venv"
            fi
            source "$SCRIPT_DIR/python/venv/bin/activate"
            pip install -q -r "$SCRIPT_DIR/python/requirements.txt"
            pip install -q -e "$SDK_DIR/signalwire-agents-python"
            ok "Python SDK installed (editable mode) — activate with: source python/venv/bin/activate"
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
            (cd "$SDK_DIR/signalwire-agents-typescript" && npm install --silent && npm run build --silent)
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
        (cd "$SCRIPT_DIR/ruby" && bundle install --quiet)
        ok "Ruby SDK installed via Gemfile path directive"
    fi
    echo ""
fi

# ── Perl ─────────────────────────────────────────────────────────────────────

if lang_enabled perl; then
    info "Setting up Perl..."
    if check_tool perl Perl; then
        # Install cpanm if missing
        if ! command -v cpanm &>/dev/null; then
            info "Installing cpanminus..."
            if curl -sL https://cpanmin.us | perl - --notest App::cpanminus 2>/dev/null; then
                ok "cpanm installed"
            else
                warn "Could not install cpanm — install manually: curl -L https://cpanmin.us | perl - App::cpanminus"
            fi
        fi

        PERL_LOCAL="$SDK_DIR/signalwire-agents-perl/local"
        if command -v cpanm &>/dev/null; then
            cpanm --quiet --notest --local-lib "$PERL_LOCAL" --installdeps "$SDK_DIR/signalwire-agents-perl" 2>/dev/null || warn "cpanm installdeps for SDK failed"
            (cd "$SCRIPT_DIR/perl" && cpanm --quiet --notest --local-lib "$PERL_LOCAL" --installdeps . 2>/dev/null) || warn "cpanm installdeps for workshop failed"
        fi

        # Create symlink: perl/lib -> SDK lib directory
        ln -sfn "../sdks/signalwire-agents-perl/lib" "$SCRIPT_DIR/perl/lib"
        ok "Perl SDK symlinked at perl/lib"
        ok "Perl deps installed to sdks/signalwire-agents-perl/local"
    fi
    echo ""
fi

# ── Java ─────────────────────────────────────────────────────────────────────

if lang_enabled java; then
    info "Setting up Java..."
    GRADLE_CMD=""
    if command -v gradle &>/dev/null; then
        GRADLE_CMD="gradle"
    elif [ -f "$SDK_DIR/signalwire-agents-java/gradlew" ]; then
        chmod +x "$SDK_DIR/signalwire-agents-java/gradlew"
        GRADLE_CMD="$SDK_DIR/signalwire-agents-java/gradlew"
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
            (cd "$SDK_DIR/signalwire-agents-java" && $GRADLE_CMD jar --console=plain -q)
            mkdir -p "$SCRIPT_DIR/java/libs"
            cp "$SDK_DIR/signalwire-agents-java/build/libs/signalwire-agents-"*.jar \
               "$SCRIPT_DIR/java/libs/" 2>/dev/null || warn "Could not copy SDK jar"
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
        SDK_CPP="$SDK_DIR/signalwire-agents-cpp"
        if [ ! -f "$SDK_CPP/build/libsignalwire_agents.a" ]; then
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

# ── Summary ──────────────────────────────────────────────────────────────────

printf "${BOLD}════════════════════════════════════════${RESET}\n"
printf "${GREEN}Setup complete for: ${LANGS[*]}${RESET}\n\n"

printf "${BOLD}Next steps:${RESET}\n"
echo "  1. Edit .env with your SignalWire credentials and API keys"
if ! command -v ngrok &>/dev/null; then
    echo "  2. Install ngrok: https://ngrok.com/download"
    echo "  3. Start tunnel:  ngrok http 3000"
else
    echo "  2. Start tunnel:  ngrok http 3000"
fi
echo ""
printf "${BOLD}Run an agent:${RESET}\n"

for lang in "${LANGS[@]}"; do
    case "$lang" in
        python)     echo "  Python:     cd python && source venv/bin/activate && python steps/step04_hello_agent.py" ;;
        typescript) echo "  TypeScript: cd typescript && npx tsx steps/step04_hello_agent.ts" ;;
        go)         echo "  Go:         cd go && go run ./steps/step04_hello_agent" ;;
        ruby)       echo "  Ruby:       cd ruby && bundle exec ruby steps/step04_hello_agent.rb" ;;
        perl)       echo "  Perl:       cd perl && PERL5LIB=../sdks/signalwire-agents-perl/local/lib/perl5 perl steps/step04_hello_agent.pl" ;;
        java)       echo "  Java:       cd java && source env.sh && gradle run --console=plain" ;;
        cpp)        echo "  C++:        cd cpp && cp steps/step04_hello_agent.cpp agent.cpp && cd build && cmake .. && make && ./agent" ;;
    esac
done

echo ""
printf "${BOLD}Run tests:${RESET}\n"
echo "  ./test.sh              # test all languages"
echo "  ./test.sh python go    # test specific languages"
echo ""
