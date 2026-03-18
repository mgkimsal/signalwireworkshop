#!/usr/bin/env bash
#
# Workshop Agent Test Framework
# ─────────────────────────────
# Uses each SDK's swaig-test tool to validate agents:
#   - Python/TypeScript: file-based (no server needed)
#   - Go/Ruby/Perl/Java/C++: URL-based (starts agent, then swaig-test against it)
#
# Usage:
#   ./test.sh                     # test all languages, all steps
#   ./test.sh python              # test all steps for Python only
#   ./test.sh python typescript   # test multiple languages
#   STEPS="04 06" ./test.sh go    # test specific steps
#   PORT=4000 ./test.sh           # use a different port (URL-based langs)
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="$SCRIPT_DIR/sdks"
PORT="${PORT:-3000}"
TIMEOUT="${TIMEOUT:-15}"          # seconds to wait for agent startup
# Read auth from .env if it exists, otherwise use defaults
if [ -f "$SCRIPT_DIR/.env" ]; then
    AUTH_USER=$(grep '^SWML_BASIC_AUTH_USER=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2- || echo "testing")
    AUTH_PASS=$(grep '^SWML_BASIC_AUTH_PASSWORD=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2- || echo "testing")
fi
AUTH_USER="${AUTH_USER:-testing}"
AUTH_PASS="${AUTH_PASS:-testing}"

ALL_LANGS=(python typescript go ruby perl java cpp)
ALL_STEPS=(04 06 07 08 09 10 11)

# Override via env or args
STEPS=("${STEPS[@]:-${ALL_STEPS[@]}}")
if [ $# -gt 0 ]; then
    LANGS=("$@")
else
    LANGS=("${ALL_LANGS[@]}")
fi

# ── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Counters ─────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
SKIP=0
FAILURES=()

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$*"; }
pass()  { printf "${GREEN}[PASS]${RESET}  %s\n" "$*"; ((PASS++)); }
fail()  {
    printf "${RED}[FAIL]${RESET}  %s\n" "$*"
    ((FAIL++))
    FAILURES+=("$*")
}
skip()  { printf "${YELLOW}[SKIP]${RESET}  %s\n" "$*"; ((SKIP++)); }

# Portable "find PIDs on a TCP port" — works on macOS + Linux + WSL
_pids_on_port() {
    local port="$1"
    if command -v lsof &>/dev/null; then
        lsof -ti :"$port" 2>/dev/null || true
    elif command -v ss &>/dev/null; then
        ss -tlnp "sport = :$port" 2>/dev/null \
            | grep -o 'pid=[0-9]*' | cut -d= -f2 || true
    elif command -v fuser &>/dev/null; then
        fuser "$port/tcp" 2>/dev/null | tr -s ' ' '\n' | grep -o '[0-9]*' || true
    fi
}

wait_for_port() {
    local port="$1" seconds="$2" agent_pid="${3:-}"
    for ((i=0; i<seconds; i++)); do
        if curl -s -o /dev/null -w '' "http://127.0.0.1:${port}/" 2>/dev/null; then
            return 0
        fi
        # If agent process already exited, don't keep waiting
        if [ -n "$agent_pid" ] && ! kill -0 "$agent_pid" 2>/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 1
}

kill_agent() {
    local pid="$1"
    if kill -0 "$pid" 2>/dev/null; then
        # Kill the entire process group — the agent runs in a subshell,
        # so killing just the subshell PID leaves the actual process orphaned.
        kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null || true
    fi
    # Belt-and-suspenders: kill anything still on our port
    local leftover
    leftover=$(_pids_on_port "$PORT")
    if [ -n "$leftover" ]; then
        kill $leftover 2>/dev/null || true
        sleep 1
    fi
}

ensure_port_free() {
    local pid
    pid=$(_pids_on_port "$PORT")
    if [ -n "$pid" ]; then
        printf "${YELLOW}[WARN]${RESET}  Port %s in use (pid %s) — killing\n" "$PORT" "$pid"
        kill $pid 2>/dev/null || true
        sleep 1
        # Check again
        pid=$(_pids_on_port "$PORT")
        if [ -n "$pid" ]; then
            kill -9 $pid 2>/dev/null || true
            sleep 1
        fi
    fi
    return 0
}

# ── Step name mapping ────────────────────────────────────────────────────────

step_name() {
    case "$1" in
        04) echo "hello_agent" ;;
        06) echo "joke_agent" ;;
        07) echo "joke_agent" ;;
        08) echo "weather_joke_agent" ;;
        09) echo "weather_joke_agent" ;;
        10) echo "weather_joke_agent" ;;
        11) echo "complete_agent" ;;
    esac
}

# ── Step expectations ────────────────────────────────────────────────────────
# What functions and skills each step should have

# Required functions per step — must be present to pass.
# Pipe-separated alternatives: "a|b|c" means any one match is OK.
# Skills expand to different function names per SDK:
#   Python: get_current_time + get_current_date + calculate
#   TypeScript: get_datetime + calculate
#   Go: get_datetime + calculate
step_expected_functions() {
    case "$1" in
        04)     echo "" ;;
        06|07)  echo "tell_joke" ;;
        08|09)  echo "tell_joke get_weather" ;;
        10|11)  echo "tell_joke get_weather get_current_time|get_current_date|get_datetime calculate" ;;
    esac
}

# ── Locate step files ───────────────────────────────────────────────────────

agent_file() {
    local lang="$1" step="$2" name
    name="$(step_name "$step")"
    case "$lang" in
        python)     echo "$SCRIPT_DIR/python/steps/step${step}_${name}.py" ;;
        typescript) echo "$SCRIPT_DIR/typescript/steps/step${step}_${name}.ts" ;;
        go)         echo "$SCRIPT_DIR/go/steps/step${step}_${name}/main.go" ;;
        ruby)       echo "$SCRIPT_DIR/ruby/steps/step${step}_${name}.rb" ;;
        perl)       echo "$SCRIPT_DIR/perl/steps/step${step}_${name}.pl" ;;
        java)
            local cls
            case "$name" in
                hello_agent)        cls="Step${step}HelloAgent" ;;
                joke_agent)         cls="Step${step}JokeAgent" ;;
                weather_joke_agent) cls="Step${step}WeatherJokeAgent" ;;
                complete_agent)     cls="Step${step}CompleteAgent" ;;
            esac
            echo "$SCRIPT_DIR/java/steps/${cls}.java"
            ;;
        cpp)        echo "$SCRIPT_DIR/cpp/steps/step${step}_${name}.cpp" ;;
    esac
}

# ── swaig-test invocation per language ───────────────────────────────────────

# File-based: Python, TypeScript
# These load the agent file directly — no server needed.

swaig_test_file_dump_swml() {
    local lang="$1" file="$2"
    case "$lang" in
        python)
            (cd "$SCRIPT_DIR/python" && source venv/bin/activate && \
             python3 -m signalwire_agents.cli.test_swaig "$file" --dump-swml --raw 2>/dev/null | sed -n '/^{/,$ p')
            ;;
        typescript)
            (cd "$SCRIPT_DIR/typescript" && \
             npx tsx "$SDK_DIR/signalwire-agents-typescript/src/cli/swaig-test.ts" "$file" --dump-swml --raw 2>/dev/null | sed -n '/^{/,$ p')
            ;;
    esac
}

swaig_test_file_list_tools() {
    local lang="$1" file="$2"
    case "$lang" in
        python)
            (cd "$SCRIPT_DIR/python" && source venv/bin/activate && \
             python3 -m signalwire_agents.cli.test_swaig "$file" --list-tools 2>/dev/null)
            ;;
        typescript)
            (cd "$SCRIPT_DIR/typescript" && \
             npx tsx "$SDK_DIR/signalwire-agents-typescript/src/cli/swaig-test.ts" "$file" --list-tools 2>/dev/null)
            ;;
    esac
}

# URL-based: Go, Ruby, Perl, Java, C++
# These test a running agent via HTTP.

swaig_test_url() {
    local lang="$1" action="$2"
    local url="http://${AUTH_USER}:${AUTH_PASS}@127.0.0.1:${PORT}/"
    local cmd
    case "$lang" in
        go)
            cmd="cd '$SDK_DIR/signalwire-agents-go' && go run ./cmd/swaig-test --url '$url' $action"
            ;;
        ruby)
            cmd="'$SDK_DIR/signalwire-agents-ruby/bin/swaig-test' --url '$url' $action"
            ;;
        perl)
            cmd="PERL5LIB='$SDK_DIR/signalwire-agents-perl/local/lib/perl5' perl '$SDK_DIR/signalwire-agents-perl/bin/swaig-test' --url '$url' $action"
            ;;
        java)
            cmd="'$SDK_DIR/signalwire-agents-java/bin/swaig-test' --url '$url' $action"
            ;;
        cpp)
            cmd="'$SDK_DIR/signalwire-agents-cpp/bin/swaig-test' '$url' $action"
            ;;
    esac
    # portable timeout: macOS lacks `timeout`, use perl fallback
    local tlimit="${SWAIG_TEST_TIMEOUT:-30}"
    if command -v timeout &>/dev/null; then
        timeout "$tlimit" bash -c "$cmd" 2>/dev/null
    else
        perl -e "alarm $tlimit; exec @ARGV" bash -c "$cmd" 2>/dev/null
    fi
}

# Start agent for URL-based testing

start_agent() {
    local lang="$1" file="$2" logfile="$3"
    # IMPORTANT: redirect subshell stdout/stderr to logfile so that
    # pid=$(start_agent ...) doesn't hang waiting for the subshell to close its fds
    case "$lang" in
        go)
            local stepdir
            stepdir="$(dirname "$file")"
            (cd "$SCRIPT_DIR/go" && exec go run "$stepdir") >>"$logfile" 2>&1 &
            ;;
        ruby)
            (cd "$SCRIPT_DIR/ruby" && exec bundle exec ruby "$file") >>"$logfile" 2>&1 &
            ;;
        perl)
            (cd "$SCRIPT_DIR/perl" && PERL5LIB="$SDK_DIR/signalwire-agents-perl/local/lib/perl5${PERL5LIB:+:$PERL5LIB}" exec perl "$file") >>"$logfile" 2>&1 &
            ;;
        java)
            local cls
            cls=$(grep -o 'public class [A-Za-z0-9_]*' "$file" | head -1 | awk '{print $3}')
            rm -f "$SCRIPT_DIR/java/src/main/java/"*.java
            mkdir -p "$SCRIPT_DIR/java/src/main/java"
            cp "$file" "$SCRIPT_DIR/java/src/main/java/${cls}.java"
            (cd "$SCRIPT_DIR/java" && exec gradle run -PmainClass="$cls" --console=plain </dev/null) >>"$logfile" 2>&1 &
            ;;
        cpp)
            mkdir -p "$SCRIPT_DIR/cpp/build"
            cp "$file" "$SCRIPT_DIR/cpp/agent.cpp"
            (cd "$SCRIPT_DIR/cpp/build" && cmake .. -DAGENT_SOURCE="$SCRIPT_DIR/cpp/agent.cpp" >>"$logfile" 2>&1 && \
             make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" >>"$logfile" 2>&1 && \
             exec ./agent) >>"$logfile" 2>&1 &
            ;;
    esac
    echo $!
}

# ── Validation ───────────────────────────────────────────────────────────────

# Check that SWML JSON contains expected content
# Real SWML structure:
#   .sections.main[] -> { ai: { prompt: { pom: [...] }, languages: [...], swaig: { functions: [...] } } }
validate_swml() {
    local step="$1" swml="$2" label="$3"

    # Must be valid JSON
    if ! echo "$swml" | jq . >/dev/null 2>&1; then
        fail "$label: response is not valid JSON"
        return 1
    fi

    # Extract the ai object from sections.main[]
    local ai
    ai=$(echo "$swml" | jq '[.sections.main[] | select(.ai) | .ai] | first' 2>/dev/null)
    if [ -z "$ai" ] || [ "$ai" = "null" ]; then
        fail "$label: SWML missing AI section in sections.main[]"
        return 1
    fi

    # Must have prompt
    local has_prompt
    has_prompt=$(echo "$ai" | jq '.prompt != null' 2>/dev/null || echo "false")
    if [ "$has_prompt" != "true" ]; then
        fail "$label: SWML AI section missing prompt"
        return 1
    fi

    # Must have languages
    local has_langs
    has_langs=$(echo "$ai" | jq '(.languages | length) > 0' 2>/dev/null || echo "false")
    if [ "$has_langs" != "true" ]; then
        fail "$label: SWML AI section missing languages"
        return 1
    fi

    # Check expected functions
    local expected_fns
    expected_fns=$(step_expected_functions "$step")
    local fn_names
    fn_names=$(echo "$ai" | jq -r '.SWAIG.functions[]?.function // empty' 2>/dev/null || true)

    if [ -n "$expected_fns" ]; then
        for fn_spec in $expected_fns; do
            local matched=false matched_name=""
            IFS='|' read -ra alts <<< "$fn_spec"
            for alt in "${alts[@]}"; do
                if echo "$fn_names" | grep -qx "$alt"; then
                    matched=true
                    matched_name="$alt"
                    break
                fi
            done
            if [ "$matched" = true ]; then
                printf "  ${DIM}  ✓ swml function: %s${RESET}\n" "$matched_name"
            else
                fail "$label: SWML missing function '$fn_spec'"
                return 1
            fi
        done
    fi

    pass "$label (swml)"
    return 0
}

# Check that --list-tools output contains expected functions
validate_tools() {
    local step="$1" tools_output="$2" label="$3"
    local expected_fns

    expected_fns=$(step_expected_functions "$step")

    # If no functions expected, just check we got output
    if [ -z "$expected_fns" ]; then
        pass "$label (tools: none expected)"
        return 0
    fi

    local all_ok=true

    for fn_spec in $expected_fns; do
        local matched=false matched_name=""
        IFS='|' read -ra alts <<< "$fn_spec"
        for alt in "${alts[@]}"; do
            if echo "$tools_output" | grep -qi "$alt"; then
                matched=true
                matched_name="$alt"
                break
            fi
        done
        if [ "$matched" = true ]; then
            printf "  ${DIM}  ✓ tool: %s${RESET}\n" "$matched_name"
        else
            printf "  ${RED}  ✗ tool: %s (missing)${RESET}\n" "$fn_spec"
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        pass "$label (tools)"
    else
        fail "$label (tools): missing expected functions"
    fi
}

# ── Prerequisite checks ─────────────────────────────────────────────────────

check_prereqs() {
    local lang="$1"
    case "$lang" in
        python)
            command -v python3 &>/dev/null && [ -d "$SCRIPT_DIR/python/venv" ]
            ;;
        typescript)
            command -v node &>/dev/null && command -v npx &>/dev/null
            ;;
        go)
            command -v go &>/dev/null
            ;;
        ruby)
            command -v ruby &>/dev/null && command -v bundle &>/dev/null
            ;;
        perl)
            command -v perl &>/dev/null
            ;;
        java)
            command -v gradle &>/dev/null || [ -x "$SCRIPT_DIR/java/gradlew" ]
            ;;
        cpp)
            command -v cmake &>/dev/null && command -v make &>/dev/null
            ;;
    esac
}

check_sdk() {
    local lang="$1"
    [ -d "$SDK_DIR/signalwire-agents-${lang}" ]
}

# ── Test: file-based (Python, TypeScript) ────────────────────────────────────

test_file_based() {
    local lang="$1" step="$2" file="$3"
    local label="${lang}/step${step}"

    # --dump-swml
    local swml
    swml=$(swaig_test_file_dump_swml "$lang" "$file")
    if [ -z "$swml" ]; then
        fail "$label: swaig-test --dump-swml returned empty output"
        return
    fi

    # Save for debugging
    echo "$swml" > "$LOGDIR/${lang}_step${step}_swml.json"

    validate_swml "$step" "$swml" "$label"

    # --list-tools
    local tools
    tools=$(swaig_test_file_list_tools "$lang" "$file")
    echo "$tools" > "$LOGDIR/${lang}_step${step}_tools.txt"

    validate_tools "$step" "$tools" "$label"
}

# ── Test: URL-based (Go, Ruby, Perl, Java, C++) ─────────────────────────────

test_url_based() {
    local lang="$1" step="$2" file="$3"
    local label="${lang}/step${step}"

    # Ensure port is free
    if ! ensure_port_free; then
        fail "$label: port $PORT not available"
        return
    fi

    local logfile="$LOGDIR/${lang}_step${step}_server.log"
    > "$logfile"

    # Start agent
    local pid
    pid=$(start_agent "$lang" "$file" "$logfile")

    # Wait for HTTP (bail early if process already crashed)
    # Java/C++ need longer — gradle daemon cold start + compilation
    local timeout="$TIMEOUT"
    case "$lang" in java|cpp) timeout=30 ;; esac
    if ! wait_for_port "$PORT" "$timeout" "$pid"; then
        fail "$label: agent did not start within ${TIMEOUT}s (see $logfile)"
        kill_agent "$pid"
        sleep 1
        return
    fi

    # --dump-swml via SDK swaig-test (strip any non-JSON preamble)
    local swml
    swml=$(swaig_test_url "$lang" "--dump-swml" | sed -n '/^[{[]/,$ p')
    if [ -z "$swml" ]; then
        fail "$label: swaig-test --dump-swml returned empty output"
        kill_agent "$pid"
        sleep 1
        return
    fi

    echo "$swml" > "$LOGDIR/${lang}_step${step}_swml.json"
    validate_swml "$step" "$swml" "$label"

    # --list-tools via SDK swaig-test
    local tools
    tools=$(swaig_test_url "$lang" "--list-tools")
    echo "$tools" > "$LOGDIR/${lang}_step${step}_tools.txt"
    validate_tools "$step" "$tools" "$label"

    # Cleanup
    kill_agent "$pid"
    sleep 1
}

# ── Main ─────────────────────────────────────────────────────────────────────

# Export all vars from .env — these MUST override any inherited env vars
# (e.g. user may have sourced env.sh with different credentials)
if [ -f "$SCRIPT_DIR/.env" ]; then
    while IFS='=' read -r key val; do
        export "$key=$val"
    done < <(grep -v '^\s*#' "$SCRIPT_DIR/.env" | grep -v '^\s*$')
fi
# Force auth to match what we read from .env at the top
export SWML_BASIC_AUTH_USER="$AUTH_USER"
export SWML_BASIC_AUTH_PASSWORD="$AUTH_PASS"

LOGDIR="$SCRIPT_DIR/.test-logs"
mkdir -p "$LOGDIR"

printf "\n${BOLD}SignalWire Workshop Agent Tests${RESET}\n"
printf "═══════════════════════════════════════════════════════\n"
printf "Languages:  %s\n" "${LANGS[*]}"
printf "Steps:      %s\n" "${STEPS[*]}"
printf "Mode:       file-based (python, typescript)\n"
printf "            url-based  (go, ruby, perl, java, cpp) on port %s\n" "$PORT"
printf "═══════════════════════════════════════════════════════\n\n"

for lang in "${LANGS[@]}"; do
    printf "${BOLD}── %s ──${RESET}\n" "$lang"

    if ! check_sdk "$lang"; then
        skip "$lang: SDK not cloned (run ./setup.sh $lang first)"
        continue
    fi

    if ! check_prereqs "$lang"; then
        skip "$lang: required toolchain not installed"
        continue
    fi

    # Pre-flight: ensure build artifacts exist
    case "$lang" in
        java)
            # Auto-detect brew openjdk on macOS
            if command -v brew &>/dev/null; then
                brew_jdk="$(brew --prefix openjdk 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
                if [ -d "$brew_jdk" ]; then
                    export JAVA_HOME="$brew_jdk"
                    export PATH="$JAVA_HOME/bin:$PATH"
                fi
            fi
            # Auto-detect Java 21+ on Linux
            if [ -d /usr/lib/jvm ]; then
                linux_jdk=$(find /usr/lib/jvm -maxdepth 1 -type d \( -name '*java-2[1-9]*' -o -name '*java-[3-9][0-9]*' \) 2>/dev/null \
                    | sort -V | tail -1)
                if [ -n "$linux_jdk" ] && [ -d "$linux_jdk" ]; then
                    export JAVA_HOME="$linux_jdk"
                    export PATH="$JAVA_HOME/bin:$PATH"
                fi
            fi
            if ! ls "$SCRIPT_DIR/java/libs/signalwire-agents-"*.jar &>/dev/null; then
                info "Building Java SDK jar..."
                gcmd="gradle"
                [ -x "$SDK_DIR/signalwire-agents-java/gradlew" ] && gcmd="$SDK_DIR/signalwire-agents-java/gradlew"
                if (cd "$SDK_DIR/signalwire-agents-java" && $gcmd jar --console=plain -q 2>/dev/null); then
                    mkdir -p "$SCRIPT_DIR/java/libs"
                    cp "$SDK_DIR/signalwire-agents-java/build/libs/signalwire-agents-"*.jar "$SCRIPT_DIR/java/libs/"
                else
                    skip "$lang: failed to build SDK jar"
                    continue
                fi
            fi
            ;;
        cpp)
            if [ ! -f "$SDK_DIR/signalwire-agents-cpp/build/libsignalwire_agents.a" ]; then
                info "Building C++ SDK..."
                mkdir -p "$SDK_DIR/signalwire-agents-cpp/build"
                if ! (cd "$SDK_DIR/signalwire-agents-cpp/build" && cmake .. -q 2>/dev/null && \
                      make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" 2>/dev/null); then
                    skip "$lang: failed to build SDK"
                    continue
                fi
            fi
            ;;
    esac

    for step in "${STEPS[@]}"; do
        label="${lang}/step${step}"
        file="$(agent_file "$lang" "$step")"

        if [ ! -f "$file" ]; then
            skip "$label: step file not found ($(basename "$file"))"
            continue
        fi

        case "$lang" in
            python|typescript)
                test_file_based "$lang" "$step" "$file"
                ;;
            go|ruby|perl|java|cpp)
                test_url_based "$lang" "$step" "$file"
                ;;
        esac
    done
    echo ""
done

# ── Summary ──────────────────────────────────────────────────────────────────

printf "${BOLD}═══════════════════════════════════════════════════════${RESET}\n"
printf "${GREEN}Passed: %d${RESET}  ${RED}Failed: %d${RESET}  ${YELLOW}Skipped: %d${RESET}\n" "$PASS" "$FAIL" "$SKIP"

if [ ${#FAILURES[@]} -gt 0 ]; then
    printf "\n${RED}Failures:${RESET}\n"
    for f in "${FAILURES[@]}"; do
        printf "  • %s\n" "$f"
    done
fi

printf "\nLogs & SWML output: %s\n" "$LOGDIR"

# Exit with failure if any tests failed
[ "$FAIL" -eq 0 ]
