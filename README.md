# Build Your First AI Phone Agent: A Hands-On Workshop

> **Duration:** ~2 hours | **Level:** Beginner | **Languages:** Python, TypeScript, Ruby, Go, Perl, Java, C++
>
> By the end of this workshop, you'll have a live AI assistant on a real phone number that tells jokes, reports weather, knows the time, and does math -- all built by you from scratch.

---

## Section 1: Welcome and What We're Building (5 min)

Welcome to the SignalWire AI Agents SDK workshop! Over the next two hours, you're going to build something that sounds complicated but is surprisingly approachable: **a voice AI agent that answers a real phone number**.

Here's what your finished agent will do:

- **Tell dad jokes** -- fresh ones from a live API, never the same joke twice
- **Report live weather** -- "What's the weather in Tokyo?" handled instantly, without your server lifting a finger
- **Tell time and date** -- any timezone, zero code required
- **Do math** -- "What's 15% tip on $47.50?" no problem
- **Sound natural** -- with a personality, smooth conversation flow, and filler phrases while it thinks

And you'll learn three different ways to give your agent capabilities:

1. **Custom functions** -- you write the handler, full control
2. **DataMap** -- declare an API call, SignalWire runs it serverlessly
3. **Skills** -- one line of code, instant capability

### Prerequisites

Before we start, make sure you have:

- [ ] **git** installed
- [ ] Your **language runtime** installed (see the [Platform Setup Guide](#platform-setup-guide) below for exact versions and install commands)
- [ ] A **terminal** -- Terminal/iTerm2 on macOS, any terminal on Linux, or **Windows Terminal + WSL2** on Windows
- [ ] A **text editor** or IDE you're comfortable with
- [ ] A **web browser** for signing up for services
- [ ] A **phone** to call your agent when it's live

No prior experience with voice, telephony, or AI APIs is needed. If you can write a basic class in your chosen language, you're ready.

### How This Workshop Works

This workshop is split into two parts:

1. **Shared setup** (this README) -- covers platform setup, SignalWire account creation, API keys, and ngrok. Every language needs this.
2. **Language-specific guide** -- covers project setup, coding, testing, and deployment for your chosen language.

Each section builds on the last. You'll write code, test it, and hit a checkpoint before moving on. If something isn't working at a checkpoint, stop and troubleshoot before continuing -- every section depends on the one before it.

Let's get started.

---

## Platform Setup Guide

This section walks you through setting up your development environment on **macOS**, **Linux (Ubuntu/Debian)**, or **Windows via WSL2**. You only need to follow the subsection for your platform. Once your environment is ready, the `setup.sh` script handles cloning SDKs, installing dependencies, and wiring everything together.

### Supported Language Versions

| Language | Minimum Version | Recommended |
|----------|----------------|-------------|
| Python | 3.10+ | 3.12 |
| Node.js (TypeScript) | 18+ | 20 LTS |
| Go | 1.22+ | 1.23 |
| Ruby | 3.0+ | 3.3 |
| Perl | 5.20+ | 5.38 |
| Java | 21+ | 21 LTS |
| C++ | C++17 compiler | GCC 12+ or Clang 15+ |

You only need the runtime(s) for the language(s) you plan to use. Most people pick one or two.

---

### macOS

macOS is the most straightforward platform. All tools are available through [Homebrew](https://brew.sh/).

#### 1. Install Xcode Command Line Tools

```bash
xcode-select --install
```

If you already have them, this will say so. These provide `git`, `make`, `clang`, and other essentials.

#### 2. Install Homebrew (if not already installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installing, follow the instructions it prints to add Homebrew to your PATH.

#### 3. Install Language Runtimes

Install only the languages you plan to use:

```bash
# Python
brew install python@3.12

# Node.js (for TypeScript)
brew install node@20

# Go
brew install go

# Ruby
brew install ruby

# Perl (ships with macOS, but brew gives you a newer version + cpanm)
brew install perl
brew install cpanminus

# Java 21
brew install openjdk@21

# C++ (clang ships with Xcode CLT; cmake is needed for the build)
brew install cmake
```

#### 4. Java PATH Setup (if using Java)

Homebrew's OpenJDK isn't on the system PATH by default. The `setup.sh` and `test.sh` scripts auto-detect it, but if you want it available everywhere:

```bash
# Add to your ~/.zshrc or ~/.bash_profile:
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
```

#### 5. Install jq (required for test.sh)

```bash
brew install jq
```

#### 6. Clone and Run Setup

```bash
git clone https://github.com/signalwire-demos/workshop.git workshop
cd workshop
./setup.sh              # all languages
./setup.sh python go    # or pick specific ones
```

---

### Linux (Ubuntu / Debian)

These instructions target Ubuntu 22.04+ and Debian 12+, which are also the most common WSL distributions. Other distributions will need equivalent packages from their package managers.

#### 1. Install Base Dependencies

```bash
sudo apt update
sudo apt install -y git curl wget jq build-essential
```

This gives you `git`, `curl`, `jq`, `make`, `gcc`, `g++`, and standard build tools.

#### 2. Install Language Runtimes

Install only the languages you plan to use:

**Python:**

```bash
sudo apt install -y python3 python3-venv python3-pip
```

On Ubuntu 22.04 this gives Python 3.10; on Ubuntu 24.04 it gives 3.12. Both work.

> **If `python3 -m venv` fails** with `ensurepip is not available`, install the version-specific venv package:
> ```bash
> # Check your Python version, then install the matching venv package:
> python3 --version                          # e.g. Python 3.12.x
> sudo apt install -y python3.12-venv        # match the major.minor
> ```

**Node.js (for TypeScript):**

The default `apt` Node.js package is often too old. Use NodeSource:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

Or use [nvm](https://github.com/nvm-sh/nvm) if you prefer to manage Node versions:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.bashrc
nvm install 20
```

**Go:**

The `apt` version of Go is usually too old. Install from the official tarball:

```bash
GO_VERSION=1.26.1
# Detect architecture (amd64 or arm64)
GO_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
wget "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

# Add to ~/.bashrc or ~/.zshrc:
export PATH="/usr/local/go/bin:$PATH"
```

> **ARM64 users (Apple Silicon via WSL, Ampere VMs, etc.):** The commands above auto-detect your architecture. If you previously installed the wrong (amd64) binary and get `cannot execute binary file: Exec format error`, re-run the commands above — they'll replace it with the correct one.

Reload your shell (`source ~/.bashrc`) and verify: `go version`

**Ruby:**

```bash
sudo apt install -y ruby-full
sudo gem install bundler
```

**Perl:**

```bash
sudo apt install -y perl cpanminus
```

Perl ships with Ubuntu, but `cpanminus` makes dependency installation painless.

**Java 21:**

```bash
sudo apt install -y openjdk-21-jdk
```

If your Ubuntu version doesn't have `openjdk-21-jdk`, add the Adoptium repository:

```bash
sudo apt install -y wget apt-transport-https
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo tee /etc/apt/keyrings/adoptium.asc
echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
  | sudo tee /etc/apt/sources.list.d/adoptium.list
sudo apt update
sudo apt install -y temurin-21-jdk
```

You also need Gradle. The easiest way is [SDKMAN](https://sdkman.io/):

```bash
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install gradle
```

Or use the `gradlew` wrapper included in the Java SDK (the setup script handles this automatically).

**C++:**

```bash
sudo apt install -y cmake g++ libcurl4-openssl-dev nlohmann-json3-dev
```

The C++ SDK uses CMake and depends on libcurl and nlohmann-json.

#### 3. Verify Installations

```bash
python3 --version    # 3.10+
node --version       # 18+
go version           # 1.22+
ruby --version       # 3.0+
perl --version       # 5.20+
java --version       # 21+
cmake --version      # 3.16+
```

#### 4. Clone and Run Setup

```bash
git clone https://github.com/signalwire-demos/workshop.git workshop
cd workshop
./setup.sh              # all languages
./setup.sh python go    # or pick specific ones
```

> **Note on port utilities:** Some minimal Linux installs don't include `lsof`. The workshop scripts automatically fall back to `ss` (included in all modern Linux distributions) for port detection, so this is handled for you. No extra packages needed.

---

### Windows (WSL2)

Windows users must use **Windows Subsystem for Linux (WSL2)** -- the workshop scripts are bash and won't run in PowerShell or CMD. WSL2 runs a real Linux kernel and has near-native performance.

#### 1. Install WSL2

Open **PowerShell as Administrator**. First, see what distros are available:

```powershell
wsl -l --online
```

Pick one (Ubuntu-24.04 is recommended) and install it:

```powershell
wsl --install Ubuntu-24.04
```

Restart your computer when prompted. After restarting, the Ubuntu terminal will open and ask you to create a username and password. Do so -- this is your Linux user account.

> **Already have WSL with an older distro?** Check what's installed and which WSL version it's using:
> ```powershell
> wsl -l -v
> ```
> If the VERSION column shows `1`, upgrade it to WSL2. Use the exact name from the NAME column:
> ```powershell
> wsl --set-version Ubuntu-24.04 2
> ```

#### 2. Open Your WSL Terminal

You can use any of these:
- **Windows Terminal** (recommended) -- open it and select the Ubuntu tab
- **Ubuntu** app from the Start menu
- VS Code's integrated terminal with the [WSL extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl)

Everything from this point forward happens inside the WSL terminal, not PowerShell.

#### 3. Install Dependencies

Follow the **Linux (Ubuntu / Debian)** instructions above in their entirety. WSL2 Ubuntu is a full Ubuntu distribution -- every command works identically.

```bash
# Start with base dependencies
sudo apt update
sudo apt install -y git curl wget jq build-essential

# Then install your chosen language runtimes (see Linux section above)
```

#### 4. Clone the Repository -- MUST Be Inside WSL's Filesystem

> **STOP -- read this before you clone.** Do NOT clone into `/mnt/c/...` (your Windows drives). It will fail with permission errors like `chmod on .git/config.lock failed: Operation not permitted`, and even if you work around that, I/O will be 5-10x slower. Always clone into your WSL home directory (`~`).

```bash
cd ~
git clone https://github.com/signalwire-demos/workshop.git workshop
cd workshop
```

If you're currently in a `/mnt/c/` path, just `cd ~` first. Your WSL home directory lives on the Linux filesystem where everything works normally.

> **If you already cloned onto `/mnt/c/`**, delete that copy and re-clone into `~`:
> ```bash
> rm -rf /mnt/c/Users/yourname/Desktop/workshop   # delete the broken clone
> cd ~
> git clone https://github.com/signalwire-demos/workshop.git workshop
> ```

> **If you cloned with Windows Git** (outside WSL) and see `/bin/bash^M: bad interpreter` errors, that's CRLF line endings. Fix it from inside WSL:
> ```bash
> sudo apt install -y dos2unix
> dos2unix setup.sh test.sh
> ```

#### 5. Run Setup

```bash
./setup.sh              # all languages
./setup.sh python go    # or pick specific ones
```

#### 6. WSL Networking

WSL2 shares your Windows machine's network. Ports opened in WSL are accessible from Windows and vice versa:

- Your agent running on port 3000 in WSL is accessible at `http://localhost:3000` from a Windows browser
- ngrok running inside WSL can tunnel `localhost:3000` normally
- If localhost doesn't work (rare, some older WSL2 builds), try the WSL IP: `ip addr show eth0 | grep inet`

#### 7. File Editing

You can edit WSL files from Windows using VS Code:

```bash
# From inside your WSL workshop directory:
code .
```

This opens VS Code with the WSL extension, editing files directly on the Linux filesystem. Don't use Windows Notepad or other editors that save with CRLF.

---

### What `setup.sh` Does

The `setup.sh` script automates the entire SDK setup process. Here's what it does for each language:

| Step | What Happens |
|------|-------------|
| **Environment** | Creates `.env` from your inputs (API keys, credentials) and symlinks it into each language directory |
| **Clone SDKs** | Shallow-clones each SDK repo into `sdks/` |
| **Python** | Creates a venv, installs the SDK in editable mode |
| **TypeScript** | Runs `npm install` and `npm run build` for the SDK, then `npm install` in the workshop dir |
| **Go** | Runs `go mod tidy` (the SDK is linked via `go.mod` replace directive) |
| **Ruby** | Runs `bundle install` (the SDK is linked via Gemfile path directive) |
| **Perl** | Installs cpanm if missing, installs deps to the SDK's `local/` directory, symlinks `perl/lib` to the SDK |
| **Java** | Auto-detects Java 21 (Homebrew on macOS, `/usr/lib/jvm` on Linux, `JAVA_HOME`, or system default), builds the SDK jar with Gradle, copies it to `java/libs/` |
| **C++** | Builds the SDK static library with CMake |

You can run it for all languages or just the ones you need:

```bash
./setup.sh                     # everything
./setup.sh python typescript   # just these two
./setup.sh java                # just Java
```

If you hit a problem with one language, fix it and re-run `setup.sh` for just that language -- it's safe to run multiple times.

---

### Running Tests

After setup, verify everything works:

```bash
./test.sh                      # test all languages
./test.sh python               # test one language
./test.sh python typescript    # test specific languages
STEPS="04 06" ./test.sh go     # test specific steps
```

The test script uses `swaig-test` (a CLI tool bundled with each SDK) to validate your agents produce correct SWML output and expose the right functions. File-based languages (Python, TypeScript) are tested without a server; URL-based languages (Go, Ruby, Perl, Java, C++) start the agent, test it over HTTP, and shut it down.

---

### Platform-Specific Troubleshooting

| Problem | Platform | Solution |
|---------|----------|----------|
| `command not found: brew` | macOS | Install Homebrew (see above), then restart your terminal |
| `python3: command not found` | Linux/WSL | `sudo apt install python3 python3-venv python3-pip` |
| `ensurepip is not available` (venv creation fails) | Linux/WSL | `sudo apt install python3.XX-venv` — replace `XX` with your Python minor version (e.g. `python3.12-venv`) |
| `chmod on .git/config.lock failed: Operation not permitted` | WSL | You cloned onto `/mnt/c/`. Delete it and re-clone into `~` (see WSL section above) |
| `node: command not found` after installing | Linux/WSL | If using nvm, run `source ~/.bashrc`; if using NodeSource, check `/usr/bin/node` exists |
| `go: command not found` after installing | Linux/WSL | Add `export PATH="/usr/local/go/bin:$PATH"` to `~/.bashrc` and `source ~/.bashrc` |
| `cannot execute binary file: Exec format error` (Go) | Linux/WSL | Wrong architecture — you installed amd64 on arm64 or vice versa. Re-install using the auto-detect commands in the Go section above |
| `Could not find gem 'dotenv'` (Ruby) | Linux/WSL | Run `./setup.sh ruby` — bundler hasn't installed gems yet |
| Java version too old | Linux/WSL | `sudo apt install openjdk-21-jdk` or use Adoptium (see above); `setup.sh` scans `/usr/lib/jvm` automatically |
| Java version too old | macOS | `brew install openjdk@21`; `setup.sh` auto-detects brew OpenJDK |
| `/bin/bash^M: bad interpreter` | WSL | Line ending issue. Run `dos2unix setup.sh test.sh` or re-clone from inside WSL |
| Port 3000 already in use | All | `test.sh` handles this automatically. Manual fix: `lsof -ti :3000 \| xargs kill` (macOS) or `ss -tlnp sport = :3000` to find the PID (Linux) |
| `lsof: command not found` | Linux/WSL | Not a problem -- the scripts fall back to `ss` automatically |
| `cmake: command not found` | Linux/WSL | `sudo apt install cmake` |
| `gradle: command not found` | Linux/WSL | Use SDKMAN (`sdk install gradle`) or let `setup.sh` use the bundled `gradlew` wrapper |
| Slow `npm install` or `go mod tidy` | WSL | Make sure you cloned inside WSL's filesystem (`~/workshop`), not on `/mnt/c/` |
| `localhost:3000` not reachable from Windows | WSL | Try `curl localhost:3000` from inside WSL first. If that works but the Windows browser can't reach it, check your WSL version (`wsl -l -v` should show VERSION 2) |
| Permission denied running `setup.sh` | All | `chmod +x setup.sh test.sh` |

---

## Section 2: SignalWire Account Setup (10 min)

SignalWire is the platform that connects your AI agent to the phone network. Their AI Agents SDK is what we'll use to build our agent, and their cloud handles all the telephony, speech-to-text, text-to-speech, and AI orchestration.

### Step 1: Create a SignalWire Account

1. Go to [signalwire.com](https://signalwire.com) and click **Sign Up** or **Get Started**
2. Fill in your details and create an account
3. You'll receive trial credits -- that's plenty for this workshop

### Step 2: Get Your Credentials

Once you're logged in to the SignalWire Dashboard:

1. Your **Space Name** is in the URL: `https://YOUR-SPACE.signalwire.com` -- note it down
2. Click on **API** in the left sidebar
3. You'll see your **Project ID** -- copy it
4. Create a new **API Token** if one doesn't exist -- copy it

> **Keep these safe.** You'll need your Project ID, API Token, and Space Name in a few minutes.

### Step 3: Buy a Phone Number

1. In the dashboard, go to **Phone Numbers** > **Buy a Number**
2. Search for a number in your area code (or any area code you like)
3. Buy one number -- trial credits cover this

> **Don't configure the phone number yet.** We'll point it at your agent after we set up ngrok in Section 5. For now, just make sure you have a number purchased.

Write down your phone number. You'll need it later.

---

## Section 3: API Keys and ngrok Setup (10 min)

Your agent will use two external APIs: one for weather data and one for jokes. Both have generous free tiers. You'll also need ngrok to expose your local agent to the internet.

### Step 1: WeatherAPI Key

1. Go to [weatherapi.com](https://www.weatherapi.com/) and sign up for a free account
2. After signing in, your API key is shown on the dashboard
3. Copy your API key

> **Free tier:** 1 million calls per month. More than enough.

### Step 2: API Ninjas Key

1. Go to [api-ninjas.com](https://api-ninjas.com/) and create a free account
2. Go to **My Account** to find your API key
3. Copy your API key

> **Free tier:** 10,000 calls per month. Plenty for development.

### Step 3: ngrok Account and Static Domain

1. Go to [ngrok.com](https://ngrok.com/) and sign up for a free account
2. From the ngrok dashboard, copy your **Authtoken**
3. Go to **Domains** in the left sidebar and create a free static domain
   - It will look something like `your-name-here.ngrok-free.app`
   - Write this down -- it's your permanent tunnel URL

> **Why a static domain?** Without one, ngrok gives you a random URL every time you restart. A static domain means your SignalWire phone number configuration won't break between sessions.

### Step 4: Create Your Environment File

Copy the `.env.example` file from the workshop root into your project directory and fill in your values:

```
# SignalWire Credentials
SIGNALWIRE_PROJECT_ID=your-project-id-here
SIGNALWIRE_API_TOKEN=your-api-token-here
SIGNALWIRE_SPACE=your-space.signalwire.com

# Agent Authentication
SWML_BASIC_AUTH_USER=workshop
SWML_BASIC_AUTH_PASSWORD=pickASecurePassword123

# Weather API
WEATHER_API_KEY=your-weatherapi-key-here

# API Ninjas
API_NINJAS_KEY=your-api-ninjas-key-here
```

Replace every placeholder with your actual values. See [`.env.example`](.env.example) for the full template.

> **Note:** You might notice there's no `SWML_PROXY_URL_BASE` here. The agent code will auto-detect your ngrok tunnel at startup -- no need to configure it manually. If you're not using ngrok (e.g., deploying to a cloud server), you can add `SWML_PROXY_URL_BASE=https://your-server.example.com` to this file as a fallback.

> **Important:** The `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` are credentials that SignalWire will use to authenticate with your agent. Choose whatever you want, but remember them -- you'll enter them into the SignalWire dashboard later.

---

## Section 4: ngrok Setup and Going Live

Your agent will run locally, but SignalWire's cloud can't reach `localhost`. We need ngrok to create a public tunnel.

### Step 1: Install ngrok

**macOS:**
```bash
brew install ngrok
```

**Linux / WSL:**
```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
  && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list \
  && sudo apt update && sudo apt install ngrok
```

> **Windows users:** Install ngrok inside your WSL terminal using the Linux command above — not with `choco` or the Windows installer. Your agent runs in WSL, so ngrok needs to be there too.

Or download directly from [ngrok.com/download](https://ngrok.com/download).

### Step 2: Add Your Auth Token

```bash
ngrok config add-authtoken YOUR_NGROK_AUTHTOKEN
```

### Step 3: Start the Tunnel

In a terminal:

```bash
ngrok http --url=your-domain.ngrok-free.app 3000
```

Replace `your-domain.ngrok-free.app` with the static domain you created in Section 3.

You should see ngrok's status display showing your tunnel is active, forwarding from your static domain to `localhost:3000`.

> **Leave ngrok running.** You'll need this tunnel active throughout the workshop. Open a new terminal for everything else.

### Step 4: Connect Your Phone Number (After Your Agent Is Running)

Once your agent is running (you'll do this in the language-specific guide), go to the SignalWire Dashboard:

1. Go to **Phone Numbers**
2. Click on the number you purchased
3. Select **Edit Settings**
4. Click **Select Resource**, then  **+ add**
5. Create a new **Script**, we will be using a **SWML Script**
6. Under **Handle Calls Using**, select **External URL**
7. Enter your ngrok URL: `https://workshop:password123@your-domain.ngrok-free.app/`
8. Click **Save**

> **Don't forget the trailing slash** on the URL. Your agent is serving on `/`.

---

## Choose Your Language

You've completed the shared setup. Now pick your language and follow the language-specific guide to build your agent:

| Language | Guide | SDK |
|----------|-------|-----|
| **Python** | [python/README.md](python/README.md) | `signalwire-agents` (PyPI) |
| **TypeScript** | [typescript/README.md](typescript/README.md) | `signalwire-agents` (npm) |
| **Ruby** | [ruby/README.md](ruby/README.md) | `signalwire-agents` (RubyGems) |
| **Go** | [go/README.md](go/README.md) | `github.com/signalwire/signalwire-agents-go` |
| **Perl** | [perl/README.md](perl/README.md) | `SignalWire::Agents` (CPAN) |
| **Java** | [java/README.md](java/README.md) | `com.signalwire:signalwire-agents` (Maven) |
| **C++** | [cpp/README.md](cpp/README.md) | `signalwire-agents-cpp` |

Each language-specific guide covers:

- **Project setup** -- dependencies, project structure, build configuration
- **Hello World agent** -- your first agent, proving everything works
- **SWAIG functions** -- custom tool handlers
- **DataMap** -- serverless API calls
- **Skills** -- one-line capabilities
- **The complete agent** -- everything polished and put together
- **Testing** -- verifying each step before moving on

Step files are provided as checkpoints in each language directory's `steps/` folder, so you can compare your code at any point.

---

## Key Concepts

Before you dive into your language-specific guide, here are the core concepts you'll encounter. These work the same way across every language -- only the syntax changes.

### What Are SWAIG Functions?

SWAIG (SignalWire AI Gateway) functions are tools that the AI can decide to call during a conversation. When a caller says "tell me a joke," the AI recognizes it should call your `tell_joke` function, your handler code runs, and the result is spoken back to the caller.

It works like this:

1. Caller says something
2. AI decides which function (if any) to call
3. Your handler runs and returns a result
4. AI uses the result in its response

You define the function with a name, description (so the AI knows when to use it), parameters (what info the AI should extract from the conversation), and a handler (your code).

### What Is DataMap?

DataMap lets you declare an API call -- URL, parameters, response template -- and **SignalWire executes it on their infrastructure**. Your server never handles the request. It's faster (no round-trip to your server), and it works even if your server goes down.

Think of it this way:

- **Custom function** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### What Are Skills?

Skills are pre-built capabilities that ship with the SDK. Adding one is a single function call -- no handler to write, no API to call, no DataMap to configure. The SDK does everything.

### Three Ways to Add Capabilities

| Capability | Approach | Your Server Handles It? | When to Use |
|-----------|----------|------------------------|-------------|
| Dad Jokes | Custom function | Yes | Custom logic, database access, complex processing |
| Weather | DataMap | No (SignalWire) | REST API calls, no server code needed |
| DateTime | Skill | No (built-in) | When a pre-built skill exists for what you need |
| Math | Skill | No (built-in) | Fastest path, zero maintenance |

---

## Cross-Language API Reference

The SignalWire AI Agents SDK is available in all seven languages. The concepts are identical -- only the syntax differs. Here's a side-by-side comparison of the core API calls:

### Creating an Agent

| Language | Syntax |
|----------|--------|
| Python | `AgentBase(name="...")` |
| TypeScript | `new AgentBase({name: "..."})` |
| Ruby | `AgentBase.new(name: "...")` |
| Go | `agent.NewAgentBase(agent.WithName("..."))` |
| Perl | `AgentBase->new(name => "...")` |
| Java | `AgentBase.builder().name("...").build()` |
| C++ | `AgentBase("name", "/route")` |

### Adding a Prompt Section

| Language | Syntax |
|----------|--------|
| Python | `prompt_add_section("Title", "body")` |
| TypeScript | `promptAddSection("Title", "body")` |
| Ruby | `prompt_add_section("Title", "body")` |
| Go | `PromptAddSection("Title", "body")` |
| Perl | `prompt_add_section("Title", "body")` |
| Java | `promptAddSection("Title", "body")` |
| C++ | `prompt_add_section("Title", "body")` |

### Defining a Tool (Custom Function)

| Language | Syntax |
|----------|--------|
| Python | `define_tool(name, desc, params, handler)` |
| TypeScript | `defineTool(name, desc, params, handler)` |
| Ruby | `define_tool(name:, description:, ...)` |
| Go | `DefineTool(name, desc, params, handler)` |
| Perl | `define_tool(name =>, ...)` |
| Java | `defineTool(name, desc, params, handler)` |
| C++ | `define_tool(name, desc, params, handler)` |

### Adding a Skill

| Language | Syntax |
|----------|--------|
| Python | `add_skill("datetime")` |
| TypeScript | `addSkill("datetime")` |
| Ruby | `add_skill("datetime")` |
| Go | `AddSkill("datetime")` |
| Perl | `add_skill("datetime")` |
| Java | `addSkill("datetime")` |
| C++ | `add_skill("datetime")` |

### Running the Agent

| Language | Syntax |
|----------|--------|
| Python | `agent.run()` |
| TypeScript | `agent.run()` |
| Ruby | `agent.run` |
| Go | `agent.Run()` |
| Perl | `$agent->run` |
| Java | `agent.run()` |
| C++ | `agent.run()` |

---

## Workshop Structure

Here's how the workshop files are organized:

```
workshop/
├── README.md              # This file -- shared setup and concepts
├── .env.example           # Environment variable template
├── python/
│   ├── README.md          # Python-specific guide
│   └── steps/             # Checkpoint files for each section
├── typescript/
│   ├── README.md          # TypeScript-specific guide
│   └── steps/             # Checkpoint files for each section
├── ruby/
│   ├── README.md          # Ruby-specific guide
│   └── steps/             # Checkpoint files for each section
├── go/
│   ├── README.md          # Go-specific guide
│   └── steps/             # Checkpoint files for each section
├── perl/
│   ├── README.md          # Perl-specific guide
│   └── steps/             # Checkpoint files for each section
├── java/
│   ├── README.md          # Java-specific guide
│   └── steps/             # Checkpoint files for each section
└── cpp/
    ├── README.md          # C++-specific guide
    └── steps/             # Checkpoint files for each section
```

---

## Section 12: Where to Go From Here

Once you've completed the language-specific guide and your agent is working, here's what's possible next.

### What You've Learned

- **AgentBase** -- the foundation for every agent
- **Prompts** -- structured personality and instructions
- **Custom functions** -- handler functions the AI can call
- **DataMap** -- serverless API calls that run on SignalWire's infrastructure
- **Skills** -- pre-built capabilities, one line each
- **AI parameters** -- tuning conversation flow and behavior
- **Speech hints and fillers** -- making conversations sound natural
- **ngrok auto-detection** -- querying the local ngrok API to streamline development
- **Post-prompt and summaries** -- saving call data for debugging with the Post-Prompt Viewer

### What's Possible Next

The agent you built today is a starting point. Here's a taste of what the SDK can do:

**Contexts and Workflows** -- guide conversations through structured steps. Imagine an appointment scheduler that walks through date, time, service type, and confirmation -- each step with its own prompt and available functions.

**State Management** -- track information across the call with global data. Remember the caller's name, build up an order, track verification status.

**Prefab Agents** -- pre-built agent types designed for specific use cases, like collecting structured data from callers with built-in validation and retry logic.

**Multi-Agent Servers** -- run multiple agents on different routes from one server. A sales agent on `/sales`, support on `/support`, with SIP routing to direct calls.

**DataSphere and Vector Search** -- connect your agent to knowledge bases. Upload documents and your agent can search them to answer questions.

**Call Recording and Post-Call Processing** -- record calls, generate summaries, extract structured data after each call.

**Transfer and Conference** -- transfer callers to humans, join conference rooms, or hand off between AI agents.

### SDK Repositories

| Language | Repository |
|----------|-----------|
| Python | [github.com/signalwire/signalwire-agents-python](https://github.com/signalwire/signalwire-agents-python) |
| TypeScript | [github.com/signalwire/signalwire-agents-typescript](https://github.com/signalwire/signalwire-agents-typescript) |
| Ruby | [github.com/signalwire/signalwire-agents-ruby](https://github.com/signalwire/signalwire-agents-ruby) |
| Go | [github.com/signalwire/signalwire-agents-go](https://github.com/signalwire/signalwire-agents-go) |
| Perl | [github.com/signalwire/signalwire-agents-perl](https://github.com/signalwire/signalwire-agents-perl) |
| Java | [github.com/signalwire/signalwire-agents-java](https://github.com/signalwire/signalwire-agents-java) |
| C++ | [github.com/signalwire/signalwire-agents-cpp](https://github.com/signalwire/signalwire-agents-cpp) |

### Other Resources

- **SignalWire Documentation:** [developer.signalwire.com](https://developer.signalwire.com) -- platform docs, SWML reference, REST APIs
- **SignalWire Community:** [signalwire.community](https://signalwire.community) -- forums, Q&A, and community projects
- **Post-Prompt Viewer:** [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) -- upload call JSON files to visualize and debug conversations

### Congratulations

You went from zero to a phone-callable AI assistant with four capabilities, built three different ways. You understand the core concepts of the SignalWire AI Agents SDK, and you have a working codebase to experiment with.

The agent running on your laptop right now is the same technology powering production voice AI systems. The patterns you learned today -- custom functions, DataMap, skills, structured prompts -- scale from this workshop project to enterprise deployments.

Go build something great.

---

## Quick Reference

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `SWML_BASIC_AUTH_USER` | Username for agent authentication |
| `SWML_BASIC_AUTH_PASSWORD` | Password for agent authentication |
| `SWML_PROXY_URL_BASE` | Auto-detected from ngrok; set manually only if not using ngrok |
| `WEATHER_API_KEY` | WeatherAPI.com API key |
| `API_NINJAS_KEY` | API Ninjas API key |

### Troubleshooting (Shared)

| Problem | Solution |
|---------|----------|
| Can't reach agent from internet | Is ngrok running? Check `http://127.0.0.1:4040` |
| SignalWire can't reach agent | Verify SWML URL has trailing slash, auth matches |
| Weather returns errors | Check `WEATHER_API_KEY` in `.env` |
| Jokes return errors | Check `API_NINJAS_KEY` in `.env` |
| Agent doesn't call functions | Check function `description` -- AI needs clear guidance |
| Speech recognition is wrong | Add hints for commonly misheard words |
| Agent responds too fast | Increase `end_of_speech_timeout` in params |
| Agent goes silent | Decrease `attention_timeout` in params |
