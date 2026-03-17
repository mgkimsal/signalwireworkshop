#!/usr/bin/env bash
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

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        warn "Required tool '$1' not found – $2 setup may fail"
        return 1
    fi
    return 0
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
        git clone "${REPO_BASE}/signalwire-agents-${lang}.git" "$target"
    fi
}

# ── Clone SDKs ───────────────────────────────────────────────────────────────

mkdir -p "$SDK_DIR"

for lang in "${LANGS[@]}"; do
    clone_sdk "$lang"
done

# ── Python ───────────────────────────────────────────────────────────────────

if lang_enabled python; then
    info "Setting up Python SDK..."
    if check_tool python3 python; then
        # Create venv if it doesn't exist
        if [ ! -d "$SCRIPT_DIR/python/venv" ]; then
            info "Creating Python venv..."
            python3 -m venv "$SCRIPT_DIR/python/venv"
        fi
        source "$SCRIPT_DIR/python/venv/bin/activate"
        pip install -r "$SCRIPT_DIR/python/requirements.txt"
        pip install -e "$SDK_DIR/signalwire-agents-python"
        info "Python SDK installed (editable mode) in python/venv"
    fi
fi

# ── TypeScript ───────────────────────────────────────────────────────────────

if lang_enabled typescript; then
    info "Setting up TypeScript SDK..."
    if check_tool node typescript && check_tool npm typescript; then
        (cd "$SDK_DIR/signalwire-agents-typescript" && npm install && npm run build)
        (cd "$SCRIPT_DIR/typescript" && npm install)
        info "TypeScript SDK built and linked"
    fi
fi

# ── Go ───────────────────────────────────────────────────────────────────────

if lang_enabled go; then
    info "Setting up Go SDK..."
    if check_tool go go; then
        (cd "$SCRIPT_DIR/go" && go mod tidy)
        info "Go SDK linked via go.mod replace directive"
    fi
fi

# ── Ruby ─────────────────────────────────────────────────────────────────────

if lang_enabled ruby; then
    info "Setting up Ruby SDK..."
    if check_tool ruby ruby && check_tool bundle ruby; then
        (cd "$SCRIPT_DIR/ruby" && bundle install)
        info "Ruby SDK installed via Gemfile path directive"
    fi
fi

# ── Perl ─────────────────────────────────────────────────────────────────────

if lang_enabled perl; then
    info "Setting up Perl SDK..."
    if check_tool perl perl; then
        # Install SDK dependencies
        if command -v cpanm &>/dev/null; then
            cpanm --installdeps "$SDK_DIR/signalwire-agents-perl" || warn "cpanm installdeps for SDK failed"
            (cd "$SCRIPT_DIR/perl" && cpanm --installdeps .) || warn "cpanm installdeps for workshop failed"
        else
            warn "cpanm not found – install cpanminus for automatic dependency installation"
        fi
        # Create symlink: perl/lib -> SDK lib directory
        ln -sfn "../sdks/signalwire-agents-perl/lib" "$SCRIPT_DIR/perl/lib"
        info "Perl SDK symlinked at perl/lib"
    fi
fi

# ── Java ─────────────────────────────────────────────────────────────────────

if lang_enabled java; then
    info "Setting up Java SDK..."
    if check_tool gradle java || check_tool "$SDK_DIR/signalwire-agents-java/gradlew" java; then
        GRADLE_CMD="gradle"
        if [ -x "$SDK_DIR/signalwire-agents-java/gradlew" ]; then
            GRADLE_CMD="$SDK_DIR/signalwire-agents-java/gradlew"
        fi
        # Build SDK jar
        (cd "$SDK_DIR/signalwire-agents-java" && $GRADLE_CMD jar)
        # Copy jar to workshop libs/
        mkdir -p "$SCRIPT_DIR/java/libs"
        cp "$SDK_DIR/signalwire-agents-java/build/libs/signalwire-agents-"*.jar \
           "$SCRIPT_DIR/java/libs/" 2>/dev/null || warn "Could not copy SDK jar"
        info "Java SDK jar built and copied to java/libs/"
    fi
fi

# ── C++ ──────────────────────────────────────────────────────────────────────

if lang_enabled cpp; then
    info "Setting up C++ SDK..."
    if check_tool cmake cpp; then
        SDK_CPP="$SDK_DIR/signalwire-agents-cpp"
        if [ ! -f "$SDK_CPP/build/libsignalwire_agents.a" ]; then
            mkdir -p "$SDK_CPP/build"
            (cd "$SDK_CPP/build" && cmake .. && make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)")
            info "C++ SDK built"
        else
            info "C++ SDK already built"
        fi
    fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
info "Setup complete for: ${LANGS[*]}"
info "Each language directory is now wired to use the local SDK from sdks/"
