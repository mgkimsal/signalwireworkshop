# Build Your First AI Phone Agent -- C++ Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

## Prerequisites

- C++17 compiler (g++ 8+ or clang 7+)
- CMake 3.16+ (`cmake --version`)
- OpenSSL development libraries (`libssl-dev` / `openssl` via Homebrew)
- git (to clone the SDK)
- Completed [SignalWire Account Setup](../README.md#section-2-signalwire-account-setup)
- Completed [API Keys and ngrok Setup](../README.md#section-3-api-keys-and-ngrok-setup)

### Quick prerequisite check

```bash
g++ --version        # or clang++ --version
cmake --version
openssl version
```

If any of these fail, install them first:

- **macOS:** `xcode-select --install && brew install cmake openssl`
- **Ubuntu/Debian:** `sudo apt install build-essential cmake libssl-dev`
- **Fedora:** `sudo dnf install gcc-c++ cmake openssl-devel`

## Step Files

Each section has a corresponding step file in `steps/` with the complete working code for that checkpoint. If you get stuck, compare your code with the step file.

| Section | Step File |
|---------|-----------|
| Section 4: Hello World | `steps/step04_hello_agent.cpp` |
| Section 6: Hardcoded Jokes | `steps/step06_joke_agent.cpp` |
| Section 7: Live API Jokes | `steps/step07_joke_agent.cpp` |
| Section 8: Weather DataMap | `steps/step08_weather_joke_agent.cpp` |
| Section 9: Polish | `steps/step09_weather_joke_agent.cpp` |
| Section 10: Skills | `steps/step10_weather_joke_agent.cpp` |
| Section 11: Complete Agent | `steps/step11_complete_agent.cpp` |

---

## Section 3: Project Setup (10 min)

Your SignalWire account and external API keys should already be set up from the [shared setup](../README.md). Now let's build the SDK and create your project.

### Step 1: Clone and Build the SDK

The C++ SDK is a static library with all dependencies vendored (nlohmann/json, cpp-httplib). No package manager required.

```bash
# Clone the SDK (pick a location you'll remember)
git clone https://github.com/signalwire/signalwire-agents-cpp.git
cd signalwire-agents-cpp

# Build the static library
mkdir -p build && cd build
cmake ..
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
```

You should see `libsignalwire_agents.a` in the build directory. If the build fails, check that OpenSSL and pthreads are available.

### Step 2: Create Your Project Directory

```bash
mkdir workshop-agent
cd workshop-agent
```

### Step 3: Create Your Environment File

Create a file called `.env` in your project directory with all your keys:

```
# SignalWire Credentials
SIGNALWIRE_PROJECT_ID=your-project-id-here
SIGNALWIRE_API_TOKEN=your-token-here

# Authentication for your agent's HTTP endpoints
SWML_BASIC_AUTH_USER=workshop
SWML_BASIC_AUTH_PASSWORD=pickASecurePassword123

# API Ninjas (for dad jokes)
API_NINJAS_KEY=your-api-ninjas-key-here

# WeatherAPI (for weather lookups)
WEATHER_API_KEY=your-weatherapi-key-here
```

> **Important:** C++ does not have a built-in `.env` loader like Python's `dotenv`. You need to export these variables in your shell before running the agent. The easiest way:
>
> ```bash
> export $(grep -v '^#' .env | xargs)
> ```
>
> Run this command every time you open a new terminal, or add it to a shell script.

### Step 4: Set Up CMake

Create a `CMakeLists.txt` file. This tells CMake where to find the SDK and how to build your agent:

```cmake
cmake_minimum_required(VERSION 3.16)
project(workshop_agent LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Point to the SDK repo you cloned in Step 1
# Adjust the path if you cloned it somewhere else
set(SIGNALWIRE_SDK_DIR "$ENV{HOME}/signalwire-agents-cpp"
    CACHE PATH "Path to signalwire-agents-cpp repo root")

include_directories(${SIGNALWIRE_SDK_DIR}/include)
include_directories(${SIGNALWIRE_SDK_DIR}/deps)

set(SIGNALWIRE_SDK_LIB "${SIGNALWIRE_SDK_DIR}/build/libsignalwire_agents.a"
    CACHE FILEPATH "Path to libsignalwire_agents.a")

find_package(OpenSSL REQUIRED)
find_package(Threads REQUIRED)

add_executable(agent agent.cpp)
target_link_libraries(agent
    ${SIGNALWIRE_SDK_LIB}
    OpenSSL::SSL OpenSSL::Crypto
    Threads::Threads
)
```

Your project directory should now look like this:

```
workshop-agent/
├── .env
└── CMakeLists.txt
```

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

### Step 1: Build the Project Skeleton

```bash
mkdir -p build
```

### Step 2: Write Your First Agent

Create a file called `agent.cpp`:

`agent.cpp`

```cpp
// My first AI phone agent -- Hello World edition.

#include <signalwire/agent/agent_base.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>

// cpp-httplib is vendored in the SDK
#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

// Auto-detect ngrok tunnel and set SWML_PROXY_URL_BASE
std::string check_ngrok() {
    try {
        httplib::Client cli("127.0.0.1", 4040);
        cli.set_connection_timeout(1);
        if (auto res = cli.Get("/api/tunnels")) {
            auto tunnels = json::parse(res->body);
            for (auto& t : tunnels.value("tunnels", json::array())) {
                if (t.value("proto", "") == "https") {
                    auto url = t.value("public_url", "");
                    setenv("SWML_PROXY_URL_BASE", url.c_str(), 1);
                    std::cout << "ngrok detected: " << url << "\n";
                    return url;
                }
            }
        }
    } catch (...) {}

    if (auto* env = std::getenv("SWML_PROXY_URL_BASE"); env && env[0]) {
        std::cout << "Using SWML_PROXY_URL_BASE from env: " << env << "\n";
        return env;
    }
    std::cout << "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return "";
}

int main() {
    check_ngrok();

    agent::AgentBase agent("hello-agent");

    // Set up the voice
    agent.add_language({"English", "en-US", "rime.spore"});

    // Tell the AI who it is
    agent.prompt_add_section(
        "Role",
        "You are a friendly assistant named Buddy. "
        "You greet callers warmly, ask how their day is going, "
        "and have a brief pleasant conversation. "
        "Keep your responses short since this is a phone call."
    );

    // Post-prompt: summarize every call
    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Include what the caller wanted and how the conversation went."
    );

    // Save call summaries for debugging
    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        auto filepath = "calls/" + call_id + ".json";
        std::ofstream(filepath) << raw_data.dump(2);
        std::cout << "Call summary saved: " << filepath << "\n";
    });

    std::cout << "Starting hello-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
```

Let's break down what's happening:

- `check_ngrok()` queries ngrok's local API at `http://127.0.0.1:4040` to discover the tunnel URL. If ngrok is running, it sets `SWML_PROXY_URL_BASE` -- the environment variable the SDK uses to generate correct webhook URLs.
- `agent::AgentBase` is the foundation class for every agent
- `add_language()` sets up English speech recognition, and `rime.spore` is a warm, friendly text-to-speech voice
- `prompt_add_section()` gives the AI its instructions using the POM (Prompt Object Model)
- `set_post_prompt()` tells the AI to generate a summary after every call
- `on_summary()` receives post-prompt data and saves the JSON payload to a `calls/` folder. You can upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize and debug conversations.
- `agent.run()` starts a web server on port 3000

### Step 3: Build and Test

```bash
# Load environment variables
export $(grep -v '^#' .env | xargs)

# Build
cd build
cmake .. -DSIGNALWIRE_SDK_DIR=/path/to/signalwire-agents-cpp
make
cd ..
```

Run the agent:

```bash
./build/agent
```

You'll see output like:

```
No ngrok tunnel detected and SWML_PROXY_URL_BASE not set
Starting hello-agent at http://0.0.0.0:3000/
```

The "No ngrok tunnel detected" message is expected -- we haven't set up ngrok yet. That's coming in Section 5.

In a **separate terminal**, test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Use whatever values you set for `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` in your `.env` file.

You should see SWML JSON output containing your prompt text and voice settings.

> **Checkpoint:** You see SWML JSON output from curl. The JSON contains your prompt text and voice settings. If the build fails, check that `SIGNALWIRE_SDK_DIR` points to the right location and that you built the SDK first (`libsignalwire_agents.a` exists). If curl hangs, make sure the agent is running.

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#step-3-ngrok-account-and-static-domain) if you haven't installed ngrok yet.

### Step 1: Restart Your Agent

Now that ngrok is running, restart your agent (Ctrl+C the old one, then run it again):

```bash
./build/agent
```

This time you should see:

```
ngrok detected: https://your-domain.ngrok-free.app
Starting hello-agent at http://0.0.0.0:3000/
```

The `check_ngrok()` function found your tunnel automatically. No need to manually configure `SWML_PROXY_URL_BASE`.

### Step 2: Test Through the Tunnel

From another terminal:

```bash
curl -s -u workshop:pickASecurePassword123 https://your-domain.ngrok-free.app/ | python3 -m json.tool
```

You should get the same SWML JSON, but now through the public internet. Look at the `web_hook_url` values -- they should reference your ngrok domain.

### Step 3: Connect Your Phone Number

Now the exciting part. Go back to the SignalWire Dashboard:

1. Go to **Phone Numbers**
2. Click on the number you purchased
3. Select **Edit Settings**
4. Click **Select Resource**, then **+ add**
5. Create a new **Script**, we will be using a **SWML Script**
6. Under **Handle Calls Using**, select **External URL**
7. Enter your ngrok URL: `https://workshop:password123@your-domain.ngrok-free.app/`
8. Click **Save**

> **Don't forget the trailing slash** on the URL. Your agent is serving on `/`.

### Step 4: Call Your Agent

Pick up your phone and call the number you purchased. You should hear the agent greet you!

It can't do much yet -- just have a friendly chat -- but you're talking to an AI agent running on your laptop. That's pretty great.

> **Checkpoint:** You can call your phone number and have a conversation with your agent. It greets you warmly and chats. If the call fails, check: Is ngrok running? Is your agent running? Is the URL in SignalWire correct (with trailing slash)? Check the ngrok web interface at `http://127.0.0.1:4040` to see if requests are reaching your agent.

---

## Section 6: Your First SWAIG Function (15 min)

Your agent can talk, but it can't *do* anything. Let's fix that by teaching it to tell jokes.

SWAIG (SignalWire AI Gateway) functions are tools that the AI can decide to call during a conversation. See [the full explanation](../README.md#what-are-swaig-functions) for details.

### Step 1: Create the Joke Agent

Replace `agent.cpp` with the joke agent:

`agent.cpp`

```cpp
// Agent with a hardcoded joke function.

#include <signalwire/agent/agent_base.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <random>
#include <filesystem>

#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

std::string check_ngrok() {
    try {
        httplib::Client cli("127.0.0.1", 4040);
        cli.set_connection_timeout(1);
        if (auto res = cli.Get("/api/tunnels")) {
            auto tunnels = json::parse(res->body);
            for (auto& t : tunnels.value("tunnels", json::array())) {
                if (t.value("proto", "") == "https") {
                    auto url = t.value("public_url", "");
                    setenv("SWML_PROXY_URL_BASE", url.c_str(), 1);
                    std::cout << "ngrok detected: " << url << "\n";
                    return url;
                }
            }
        }
    } catch (...) {}

    if (auto* env = std::getenv("SWML_PROXY_URL_BASE"); env && env[0]) {
        std::cout << "Using SWML_PROXY_URL_BASE from env: " << env << "\n";
        return env;
    }
    std::cout << "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return "";
}

// Hardcoded jokes for our first function
static const std::vector<std::string> JOKES = {
    "Why do programmers prefer dark mode? Because light attracts bugs.",
    "I told my wife she was drawing her eyebrows too high. She looked surprised.",
    "What do you call a fake noodle? An impasta.",
    "Why don't scientists trust atoms? Because they make up everything.",
    "I'm reading a book about anti-gravity. It's impossible to put down.",
    "What did the ocean say to the beach? Nothing, it just waved.",
    "Why did the scarecrow win an award? He was outstanding in his field.",
    "I used to hate facial hair, but then it grew on me.",
};

int main() {
    check_ngrok();

    agent::AgentBase agent("joke-agent");

    agent.add_language({"English", "en-US", "rime.spore"});

    agent.prompt_add_section(
        "Role",
        "You are a friendly assistant named Buddy. "
        "You love telling jokes and making people laugh. "
        "Keep your responses short since this is a phone call."
    );

    agent.prompt_add_section("Guidelines",
        "Follow these guidelines:", {
            "When someone asks for a joke, use the tell_joke function",
            "After telling a joke, pause for a reaction before offering another",
            "Be enthusiastic and have fun with it",
        }
    );

    // Register the joke function
    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny joke. Use this whenever someone asks for a joke or humor.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;
            static std::mt19937 rng{std::random_device{}()};
            std::uniform_int_distribution<size_t> dist(0, JOKES.size() - 1);
            return swaig::FunctionResult("Here's a joke: " + JOKES[dist(rng)]);
        }
    );

    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Note which jokes were told and how the caller reacted."
    );

    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        std::ofstream("calls/" + call_id + ".json") << raw_data.dump(2);
        std::cout << "Call summary saved: calls/" << call_id << ".json\n";
    });

    std::cout << "Starting joke-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
```

Let's look at the new pieces:

- `swaig::FunctionResult` is how you return data from a SWAIG function. The AI takes this text and weaves it into its response.
- `define_tool()` registers the function. The `description` is critical -- it tells the AI *when* to call this function.
- `parameters` defines what the AI should extract from the conversation. Our joke function doesn't need any input, so it's an empty object.
- The tool handler is a lambda that takes `(const json& args, const json& raw)` and returns a `swaig::FunctionResult`.
- We use C++'s `<random>` for proper random selection instead of `rand()`.

### Step 2: Build and Test

```bash
cd build && cmake .. && make && cd ..
./build/agent
```

In another terminal, test the SWML output:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Look for `tell_joke` in the SWML JSON.

### Step 3: Run and Call

With ngrok still running, call your number and ask for a joke. Try phrases like:
- "Tell me a joke"
- "Make me laugh"
- "Got any jokes?"

The AI should recognize these as requests for humor and call your function.

> **Checkpoint:** When you call and ask for a joke, the agent tells you one from the hardcoded list. You can see function calls in your agent's terminal output. If the agent talks about jokes but doesn't actually tell one from the list, check that your `define_tool` description clearly instructs the AI to use the function.

---

## Section 7: Calling a Live API (15 min)

Hardcoded jokes get old fast. Let's replace them with fresh dad jokes from the API Ninjas Dad Jokes API. Every call will be a different joke.

### Step 1: Understanding the API

The API Ninjas Dad Jokes endpoint is simple:

- **URL:** `https://api.api-ninjas.com/v1/dadjokes`
- **Method:** GET
- **Auth:** `X-Api-Key` header with your API key
- **Response:** A JSON array with a `joke` field: `[{"joke": "..."}]`

You can test it right now in your terminal:

```bash
curl -s -H "X-Api-Key: YOUR_API_NINJAS_KEY" https://api.api-ninjas.com/v1/dadjokes | python3 -m json.tool
```

### Step 2: Update the Joke Agent

Replace `agent.cpp` -- we'll swap the hardcoded jokes with a live API call using cpp-httplib (already vendored in the SDK):

`agent.cpp`

```cpp
// Agent that tells fresh dad jokes from API Ninjas.

#include <signalwire/agent/agent_base.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <filesystem>

#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

std::string check_ngrok() {
    try {
        httplib::Client cli("127.0.0.1", 4040);
        cli.set_connection_timeout(1);
        if (auto res = cli.Get("/api/tunnels")) {
            auto tunnels = json::parse(res->body);
            for (auto& t : tunnels.value("tunnels", json::array())) {
                if (t.value("proto", "") == "https") {
                    auto url = t.value("public_url", "");
                    setenv("SWML_PROXY_URL_BASE", url.c_str(), 1);
                    std::cout << "ngrok detected: " << url << "\n";
                    return url;
                }
            }
        }
    } catch (...) {}

    if (auto* env = std::getenv("SWML_PROXY_URL_BASE"); env && env[0]) {
        std::cout << "Using SWML_PROXY_URL_BASE from env: " << env << "\n";
        return env;
    }
    std::cout << "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return "";
}

int main() {
    check_ngrok();

    agent::AgentBase agent("joke-agent");

    agent.add_language({"English", "en-US", "rime.spore"});

    agent.prompt_add_section(
        "Role",
        "You are a friendly assistant named Buddy. "
        "You love telling jokes and making people laugh. "
        "Keep your responses short since this is a phone call."
    );

    agent.prompt_add_section("Guidelines",
        "Follow these guidelines:", {
            "When someone asks for a joke, use the tell_joke function",
            "After telling a joke, pause for a reaction before offering another",
            "Be enthusiastic and have fun with it",
        }
    );

    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny dad joke. Use this whenever someone "
        "asks for a joke, humor, or to be entertained.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;

            auto* api_key = std::getenv("API_NINJAS_KEY");
            if (!api_key || !api_key[0]) {
                return swaig::FunctionResult(
                    "Sorry, I can't access my joke book right now. "
                    "My API key is missing.");
            }

            try {
                httplib::Client cli("https://api.api-ninjas.com");
                cli.set_connection_timeout(5);
                httplib::Headers headers = {{"X-Api-Key", api_key}};

                if (auto res = cli.Get("/v1/dadjokes", headers)) {
                    auto jokes = json::parse(res->body);
                    if (jokes.is_array() && !jokes.empty()) {
                        return swaig::FunctionResult(
                            "Here's a dad joke: " +
                            jokes[0].value("joke", ""));
                    }
                    return swaig::FunctionResult(
                        "I tried to find a joke but came up empty. "
                        "That's... kind of a joke itself?");
                }
            } catch (...) {}

            return swaig::FunctionResult(
                "Sorry, my joke service is taking a nap. "
                "Ask me again in a moment!");
        }
    );

    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Note which jokes were told and how the caller reacted."
    );

    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        std::ofstream("calls/" + call_id + ".json") << raw_data.dump(2);
        std::cout << "Call summary saved: calls/" << call_id << ".json\n";
    });

    std::cout << "Starting joke-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
```

What changed:

- Removed the `JOKES` vector and `<random>` includes
- The handler now calls the API Ninjas endpoint using `httplib::Client`
- We read the API key from the environment with `std::getenv()`
- There's error handling -- if the API is down or the key is wrong, the agent says something graceful instead of crashing

### Step 3: Build, Run, and Call

```bash
cd build && make && cd ..
./build/agent
```

Call your number and ask for jokes. Every joke is now fresh from the internet.

> **Checkpoint:** Every time you ask for a joke, you get a different one. If you're getting errors, make sure `API_NINJAS_KEY` is exported in your environment.

---

## Section 8: DataMap -- The Serverless Approach (15 min)

For the joke function, you wrote C++ code that runs on your server. That works great, but there's another way: **DataMap**.

DataMap lets you declare an API call and SignalWire executes it on their infrastructure -- your server never handles the request. See [the full explanation](../README.md#what-is-datamap) for details.

Think of it this way:

- **define_tool** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### Step 1: Create the Weather + Joke Agent

Let's create an agent that has both jokes (via your custom function) and weather (via DataMap). Replace `agent.cpp`:

`agent.cpp`

```cpp
// Agent with dad jokes (custom function) and weather (DataMap).

#include <signalwire/agent/agent_base.hpp>
#include <signalwire/datamap/datamap.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <filesystem>

#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

std::string check_ngrok() {
    try {
        httplib::Client cli("127.0.0.1", 4040);
        cli.set_connection_timeout(1);
        if (auto res = cli.Get("/api/tunnels")) {
            auto tunnels = json::parse(res->body);
            for (auto& t : tunnels.value("tunnels", json::array())) {
                if (t.value("proto", "") == "https") {
                    auto url = t.value("public_url", "");
                    setenv("SWML_PROXY_URL_BASE", url.c_str(), 1);
                    std::cout << "ngrok detected: " << url << "\n";
                    return url;
                }
            }
        }
    } catch (...) {}

    if (auto* env = std::getenv("SWML_PROXY_URL_BASE"); env && env[0]) {
        std::cout << "Using SWML_PROXY_URL_BASE from env: " << env << "\n";
        return env;
    }
    std::cout << "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return "";
}

int main() {
    check_ngrok();

    agent::AgentBase agent("weather-joke-agent");

    agent.add_language({"English", "en-US", "rime.spore"});

    agent.prompt_add_section(
        "Role",
        "You are a friendly assistant named Buddy. "
        "You help people with weather information and tell great jokes. "
        "Keep your responses short since this is a phone call."
    );

    agent.prompt_add_section("Guidelines",
        "Follow these guidelines:", {
            "When someone asks about weather, use the get_weather function",
            "When someone asks for a joke, use the tell_joke function",
            "Be warm, friendly, and conversational",
        }
    );

    // ---- Dad jokes: custom function (runs on our server) ----

    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny dad joke. Use this whenever someone "
        "asks for a joke or humor.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;

            auto* api_key = std::getenv("API_NINJAS_KEY");
            if (!api_key || !api_key[0]) {
                return swaig::FunctionResult(
                    "Sorry, my joke book is unavailable right now.");
            }

            try {
                httplib::Client cli("https://api.api-ninjas.com");
                cli.set_connection_timeout(5);
                httplib::Headers headers = {{"X-Api-Key", api_key}};

                if (auto res = cli.Get("/v1/dadjokes", headers)) {
                    auto jokes = json::parse(res->body);
                    if (jokes.is_array() && !jokes.empty()) {
                        return swaig::FunctionResult(
                            "Here's a dad joke: " +
                            jokes[0].value("joke", ""));
                    }
                    return swaig::FunctionResult(
                        "I couldn't find a joke this time. Try again!");
                }
            } catch (...) {}

            return swaig::FunctionResult(
                "My joke service is taking a break. "
                "Try again in a moment!");
        }
    );

    // ---- Weather: DataMap (runs on SignalWire's servers) ----

    std::string weather_key;
    if (auto* env = std::getenv("WEATHER_API_KEY")) weather_key = env;

    auto weather_dm = datamap::DataMap("get_weather")
        .description(
            "Get the current weather for a city. "
            "Use this when the caller asks about weather, "
            "temperature, or conditions.")
        .parameter("city", "string",
            "The city to get weather for", true)
        .webhook("GET",
            "https://api.weatherapi.com/v1/current.json"
            "?key=" + weather_key + "&q=${enc:args.city}")
        .output(swaig::FunctionResult(
            "Weather in ${args.city}: "
            "${response.current.condition.text}, "
            "${response.current.temp_f} degrees Fahrenheit, "
            "humidity ${response.current.humidity} percent. "
            "Feels like ${response.current.feelslike_f} degrees."))
        .fallback_output(swaig::FunctionResult(
            "Sorry, I couldn't get the weather for ${args.city}. "
            "Please check the city name and try again."));

    agent.register_swaig_function(weather_dm.to_swaig_function());

    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Note what the caller asked about (weather, jokes, etc.) "
        "and how the interaction went."
    );

    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        std::ofstream("calls/" + call_id + ".json") << raw_data.dump(2);
        std::cout << "Call summary saved: calls/" << call_id << ".json\n";
    });

    std::cout << "Starting weather-joke-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
```

Let's unpack the DataMap piece:

- `datamap::DataMap("get_weather")` -- creates a new DataMap function with that name
- `.description(...)` -- tells the AI when to use it (same as `define_tool`)
- `.parameter("city", "string", ...)` -- the AI will extract the city from the caller's request
- `.webhook("GET", url)` -- the HTTP request SignalWire will make. Notice `${enc:args.city}` -- that's the city parameter, URL-encoded, inserted right into the URL
- `.output(...)` -- a template for the response. `${response.current.temp_f}` pulls the temperature from the API's JSON response
- `.fallback_output(...)` -- what to say if the API call fails

The API key is baked into the URL at startup time (via string concatenation). The city gets substituted at call time (via `${enc:args.city}`).

### Step 2: Build and Test

```bash
cd build && make && cd ..
./build/agent
```

Test the SWML output:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Find the `get_weather` function in the JSON. Notice it has a `data_map` section instead of a `web_hook_url` -- that tells SignalWire to execute the API call directly.

### Step 3: Call and Test

Call your number and try:
- "What's the weather in New York?"
- "How's the weather in London?"
- "Tell me a joke"
- "What's the temperature in Tokyo?"

You now have an agent with two capabilities, built two different ways.

> **Checkpoint:** Your agent answers weather questions with live data AND tells fresh dad jokes. The weather responses include temperature, conditions, and humidity. If weather isn't working, double-check your `WEATHER_API_KEY` is exported -- DataMap sends the key directly to WeatherAPI, so it must be correct.

---

## Section 9: Polish and Personality (10 min)

Your agent works, but it sounds a bit robotic. Let's give it a personality and tune the conversation flow. Same file, better experience.

### Step 1: Upgrade the Prompts

Replace `agent.cpp` with this improved version -- same structure but enhanced prompts and AI parameters:

`agent.cpp`

```cpp
// Polished agent with personality, hints, and tuned parameters.

#include <signalwire/agent/agent_base.hpp>
#include <signalwire/datamap/datamap.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <filesystem>

#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

std::string check_ngrok() {
    try {
        httplib::Client cli("127.0.0.1", 4040);
        cli.set_connection_timeout(1);
        if (auto res = cli.Get("/api/tunnels")) {
            auto tunnels = json::parse(res->body);
            for (auto& t : tunnels.value("tunnels", json::array())) {
                if (t.value("proto", "") == "https") {
                    auto url = t.value("public_url", "");
                    setenv("SWML_PROXY_URL_BASE", url.c_str(), 1);
                    std::cout << "ngrok detected: " << url << "\n";
                    return url;
                }
            }
        }
    } catch (...) {}

    if (auto* env = std::getenv("SWML_PROXY_URL_BASE"); env && env[0]) {
        std::cout << "Using SWML_PROXY_URL_BASE from env: " << env << "\n";
        return env;
    }
    std::cout << "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return "";
}

int main() {
    check_ngrok();

    agent::AgentBase agent("weather-joke-agent");

    // Voice configuration
    agent.add_language({"English", "en-US", "rime.spore"});

    // AI parameters for better conversation flow
    agent.set_params({
        {"end_of_speech_timeout", 600},    // Wait 600ms of silence before responding
        {"attention_timeout", 15000},      // Prompt after 15s of silence
        {"attention_timeout_prompt",
            "Are you still there? I can help with weather, jokes, or math!"},
    });

    // Speech hints help the recognizer with tricky words
    agent.add_hints({"Buddy", "weather", "joke", "temperature", "forecast"});

    // Structured prompt with personality
    agent.prompt_add_section(
        "Personality",
        "You are Buddy, a cheerful and witty AI phone assistant. "
        "You have a warm, upbeat personality and you genuinely enjoy "
        "helping people. You're a bit of a dad joke enthusiast. "
        "Think of yourself as that friendly neighbor who always "
        "has a joke ready and knows what the weather is like."
    );

    agent.prompt_add_section("Voice Style",
        "Since this is a phone conversation, follow these rules:", {
            "Keep responses to 1-2 sentences when possible",
            "Use conversational language, not formal or robotic",
            "React to what the caller says before jumping to information",
            "If they laugh at a joke, acknowledge it warmly",
            "Use natural transitions between topics",
        }
    );

    agent.prompt_add_section("Capabilities",
        "You can help with the following:", {
            "Weather: current conditions for any city worldwide",
            "Jokes: endless supply of dad jokes, always fresh",
            "General chat: friendly conversation on any topic",
        }
    );

    // ---- Dad jokes: custom function ----

    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny dad joke. Use this whenever someone "
        "asks for a joke or humor.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;

            auto* api_key = std::getenv("API_NINJAS_KEY");
            if (!api_key || !api_key[0]) {
                return swaig::FunctionResult(
                    "Sorry, my joke book is unavailable right now.");
            }

            try {
                httplib::Client cli("https://api.api-ninjas.com");
                cli.set_connection_timeout(5);
                httplib::Headers headers = {{"X-Api-Key", api_key}};

                if (auto res = cli.Get("/v1/dadjokes", headers)) {
                    auto jokes = json::parse(res->body);
                    if (jokes.is_array() && !jokes.empty()) {
                        return swaig::FunctionResult(
                            "Here's a dad joke: " +
                            jokes[0].value("joke", ""));
                    }
                    return swaig::FunctionResult(
                        "I couldn't find a joke this time. Try again!");
                }
            } catch (...) {}

            return swaig::FunctionResult(
                "My joke service is taking a break. "
                "Try again in a moment!");
        }
    );

    // ---- Weather: DataMap ----

    std::string weather_key;
    if (auto* env = std::getenv("WEATHER_API_KEY")) weather_key = env;

    auto weather_dm = datamap::DataMap("get_weather")
        .description(
            "Get the current weather for a city. "
            "Use this when the caller asks about weather, "
            "temperature, or conditions.")
        .parameter("city", "string",
            "The city to get weather for", true)
        .webhook("GET",
            "https://api.weatherapi.com/v1/current.json"
            "?key=" + weather_key + "&q=${enc:args.city}")
        .output(swaig::FunctionResult(
            "Weather in ${args.city}: "
            "${response.current.condition.text}, "
            "${response.current.temp_f} degrees Fahrenheit, "
            "humidity ${response.current.humidity} percent. "
            "Feels like ${response.current.feelslike_f} degrees."))
        .fallback_output(swaig::FunctionResult(
            "Sorry, I couldn't get the weather for ${args.city}. "
            "Please check the city name and try again."));

    agent.register_swaig_function(weather_dm.to_swaig_function());

    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Note what the caller asked about (weather, jokes, etc.) "
        "and how the interaction went."
    );

    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        std::ofstream("calls/" + call_id + ".json") << raw_data.dump(2);
        std::cout << "Call summary saved: calls/" << call_id << ".json\n";
    });

    std::cout << "Starting weather-joke-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
```

What we improved:

- **`set_params()`** -- `end_of_speech_timeout` of 600ms means the agent waits a natural beat before responding (not jumping in too fast). `attention_timeout` of 15 seconds prompts the caller if they go quiet.
- **`add_hints()`** -- helps the speech recognizer with words it might mishear. "Buddy" could sound like "body" without a hint.
- **Richer prompts** -- the "Personality" section gives the AI a character to play. The "Voice Style" section has specific rules for phone conversation. The "Capabilities" section tells the AI what tools it has.

### Step 2: Build and Call

```bash
cd build && make && cd ..
./build/agent
```

The difference should be noticeable: the agent sounds more natural, has more personality, and handles pauses in conversation better.

> **Checkpoint:** Same capabilities (weather + jokes) but the conversation feels smoother and more natural. The agent has personality, uses varied responses, and handles silence gracefully. Compare the experience to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

### Step 1: Add DateTime and Math Skills

Edit `agent.cpp`. Add two lines after the DataMap registration:

```cpp
    agent.register_swaig_function(weather_dm.to_swaig_function());

    // Built-in skills -- one line each, zero configuration
    agent.add_skill("datetime", {{"default_timezone", "America/New_York"}});
    agent.add_skill("math");
```

Also update the "Capabilities" prompt section to mention the new abilities:

```cpp
    agent.prompt_add_section("Capabilities",
        "You can help with the following:", {
            "Weather: current conditions for any city worldwide",
            "Jokes: endless supply of dad jokes, always fresh",
            "Date and time: current time in any timezone",
            "Math: calculations, percentages, conversions",
            "General chat: friendly conversation on any topic",
        }
    );
```

That's it. Two lines of code just gave your agent the ability to tell time in any timezone and do math.

### Step 2: Compare the Approaches

Let's look at what it took to add each capability:

| Capability | Approach | Lines of Code | Your Server Handles It? |
|-----------|----------|---------------|------------------------|
| Dad Jokes | `define_tool` | ~30 lines | Yes |
| Weather | DataMap | ~15 lines | No (SignalWire) |
| DateTime | Skill | 1 line | No (built-in) |
| Math | Skill | 1 line | No (built-in) |

**When to use which:**

- **Skills** -- when one exists for what you need. Fastest path, zero maintenance
- **DataMap** -- when you need to call a REST API. No server code, SignalWire handles it
- **define_tool** -- when you need custom logic, database access, or complex processing

### Step 3: Build and Call

```bash
cd build && make && cd ..
./build/agent
```

Try asking:
- "What time is it?"
- "What time is it in Tokyo?"
- "What's 15% tip on a $47.50 bill?"
- "What's 144 divided by 12?"
- And of course: weather and jokes still work

> **Checkpoint:** Your agent now handles weather, jokes, time/date, and math. That's four capabilities, and two of them were a single line of code each. Verify all four work by calling and testing each one.

---

## Section 11: The Finished Agent (10 min)

Let's bring everything together into one clean, final version. This is the definitive `agent.cpp` -- combining all four capabilities with polished prompts and tuned parameters.

### The Complete Agent

Replace `agent.cpp`:

`agent.cpp`

```cpp
// Complete Workshop Agent
// -----------------------
// A polished AI phone assistant with four capabilities:
//   - Dad jokes via API Ninjas (custom define_tool)
//   - Weather via WeatherAPI (serverless DataMap)
//   - Date/time via built-in skill
//   - Math via built-in skill
//
// Build:  cd build && cmake .. && make
// Run:    ./build/agent

#include <signalwire/agent/agent_base.hpp>
#include <signalwire/datamap/datamap.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <filesystem>

#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

// ---- ngrok auto-detection ----

std::string check_ngrok() {
    try {
        httplib::Client cli("127.0.0.1", 4040);
        cli.set_connection_timeout(1);
        if (auto res = cli.Get("/api/tunnels")) {
            auto tunnels = json::parse(res->body);
            for (auto& t : tunnels.value("tunnels", json::array())) {
                if (t.value("proto", "") == "https") {
                    auto url = t.value("public_url", "");
                    setenv("SWML_PROXY_URL_BASE", url.c_str(), 1);
                    std::cout << "ngrok detected: " << url << "\n";
                    return url;
                }
            }
        }
    } catch (...) {}

    if (auto* env = std::getenv("SWML_PROXY_URL_BASE"); env && env[0]) {
        std::cout << "Using SWML_PROXY_URL_BASE from env: " << env << "\n";
        return env;
    }
    std::cout << "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return "";
}

// ---- Agent setup helpers ----

void configure_voice(agent::AgentBase& agent) {
    agent.add_language({"English", "en-US", "rime.spore"});
    agent.add_hints({
        "Buddy", "weather", "joke", "temperature",
        "forecast", "Fahrenheit", "Celsius",
    });
}

void configure_params(agent::AgentBase& agent) {
    agent.set_params({
        {"end_of_speech_timeout", 600},
        {"attention_timeout", 15000},
        {"attention_timeout_prompt",
            "Are you still there? I can help with weather, "
            "jokes, math, or just chat!"},
    });
}

void configure_prompts(agent::AgentBase& agent) {
    agent.prompt_add_section(
        "Personality",
        "You are Buddy, a cheerful and witty AI phone assistant. "
        "You have a warm, upbeat personality and you genuinely enjoy "
        "helping people. You're a bit of a dad joke enthusiast. "
        "Think of yourself as that friendly neighbor who always "
        "has a joke ready and knows what the weather is like."
    );

    agent.prompt_add_section("Voice Style",
        "Since this is a phone conversation:", {
            "Keep responses to 1-2 sentences when possible",
            "Use conversational language, not formal or robotic",
            "React naturally to what the caller says",
            "Use smooth transitions between topics",
        }
    );

    agent.prompt_add_section("Capabilities",
        "You can help with:", {
            "Weather: current conditions for any city worldwide",
            "Jokes: endless supply of fresh dad jokes",
            "Date and time: current time in any timezone",
            "Math: calculations, percentages, unit conversions",
            "General chat: friendly conversation on any topic",
        }
    );

    agent.prompt_add_section(
        "Greeting",
        "When the call starts, introduce yourself as Buddy and "
        "briefly mention what you can help with. Keep the greeting "
        "to one or two sentences -- don't list every capability."
    );
}

void register_joke_function(agent::AgentBase& agent) {
    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny dad joke. Use this whenever "
        "someone asks for a joke, humor, or to be entertained.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;

            auto* api_key = std::getenv("API_NINJAS_KEY");
            if (!api_key || !api_key[0]) {
                return swaig::FunctionResult(
                    "Sorry, my joke book is unavailable right now.");
            }

            try {
                httplib::Client cli("https://api.api-ninjas.com");
                cli.set_connection_timeout(5);
                httplib::Headers headers = {{"X-Api-Key", api_key}};

                if (auto res = cli.Get("/v1/dadjokes", headers)) {
                    auto jokes = json::parse(res->body);
                    if (jokes.is_array() && !jokes.empty()) {
                        return swaig::FunctionResult(
                            "Here's a dad joke: " +
                            jokes[0].value("joke", ""));
                    }
                    return swaig::FunctionResult(
                        "I couldn't find a joke this time. Try again!");
                }
            } catch (...) {}

            return swaig::FunctionResult(
                "My joke service is taking a break. "
                "Try again in a moment!");
        }
    );
}

void register_weather_datamap(agent::AgentBase& agent) {
    std::string weather_key;
    if (auto* env = std::getenv("WEATHER_API_KEY")) weather_key = env;

    auto weather_dm = datamap::DataMap("get_weather")
        .description(
            "Get the current weather for a city. Use this when "
            "the caller asks about weather, temperature, or conditions.")
        .parameter("city", "string",
            "The city to get weather for", true)
        .webhook("GET",
            "https://api.weatherapi.com/v1/current.json"
            "?key=" + weather_key + "&q=${enc:args.city}")
        .output(swaig::FunctionResult(
            "Weather in ${args.city}: "
            "${response.current.condition.text}, "
            "${response.current.temp_f} degrees Fahrenheit, "
            "humidity ${response.current.humidity} percent. "
            "Feels like ${response.current.feelslike_f} degrees."))
        .fallback_output(swaig::FunctionResult(
            "Sorry, I couldn't get the weather for ${args.city}. "
            "Please check the city name and try again."));

    agent.register_swaig_function(weather_dm.to_swaig_function());
}

void register_skills(agent::AgentBase& agent) {
    agent.add_skill("datetime", {{"default_timezone", "America/New_York"}});
    agent.add_skill("math");
}

void configure_post_prompt(agent::AgentBase& agent) {
    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Note what the caller asked about (weather, jokes, time, math, etc.) "
        "and how the interaction went."
    );

    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        auto filepath = "calls/" + call_id + ".json";
        std::ofstream(filepath) << raw_data.dump(2);
        std::cout << "Call summary saved: " << filepath << "\n";
    });
}

// ---- Main ----

int main() {
    check_ngrok();

    agent::AgentBase agent("complete-agent");

    configure_voice(agent);
    configure_params(agent);
    configure_prompts(agent);
    register_joke_function(agent);
    register_weather_datamap(agent);
    register_skills(agent);
    configure_post_prompt(agent);

    std::cout << "Starting complete-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
```

This is the same agent you've been building, just organized into clean helper functions. Every section from this workshop is represented:

| Section | What it added | Function |
|---------|--------------|----------|
| 4 | Hello world, voice, prompts | `configure_voice`, `configure_prompts` |
| 6-7 | Dad jokes (define_tool) | `register_joke_function` |
| 8 | Weather (DataMap) | `register_weather_datamap` |
| 9 | Personality, hints, params | `configure_params`, enhanced prompts |
| 10 | DateTime and math (skills) | `register_skills` |

### Build and Run

```bash
cd build && make && cd ..
./build/agent
```

### What to Try

Run through everything:

1. **Call and chat** -- the agent should greet you as Buddy
2. **Ask for a joke** -- fresh dad joke from API Ninjas
3. **Ask about weather** -- "What's the weather in Paris?"
4. **Ask the time** -- "What time is it in Tokyo?"
5. **Ask a math question** -- "What's 20% of 85?"
6. **Check your calls/ folder** -- you should see JSON files from each call

> **Checkpoint:** All four capabilities work in a single, polished agent. The conversation feels natural, the agent has personality, and call summaries are being saved. Congratulations -- you've built a complete AI phone agent in C++!

---

## What's Next?

You've built a working AI phone agent with four different capabilities using three different approaches. Here are some ideas for what to build next:

- **Add more tools** -- database lookups, appointment scheduling, order tracking
- **Try Contexts and Steps** -- build multi-step workflows with `define_contexts()`
- **Build a subclass** -- inherit from `AgentBase` for cleaner code organization
- **Add SIP routing** -- `agent.enable_sip_routing(true)` for internal extensions
- **Deploy for real** -- containerize with Docker and run on a cloud VM (no more ngrok)

Check out the [signalwire-agents-cpp examples](https://github.com/signalwire/signalwire-agents-cpp/tree/main/examples) for more patterns and the SDK README for the full API reference.
