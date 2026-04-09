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

> [!NOTE]
> **Docker users:** The setup script has already run inside the container. Just run `cd cpp` and skip to Section 4.
> The instructions below are for native installs only.

Your SignalWire account and external API keys should already be set up from the [shared setup](../README.md). Run the automated setup script from the **workshop root**:

```bash
./setup.sh cpp
```

This clones and builds the SDK, creates your project structure, and sets up the CMake build system.

Then build and run the first step:

```bash
cd cpp
cp steps/step04_hello_agent.cpp agent.cpp
cd build && cmake .. && make && ./agent
```

> **Note:** C++ does not have a built-in `.env` loader. The setup script will remind you to export your environment variables. The easiest way:
>
> ```bash
> export $(grep -v '^#' .env | xargs)
> ```
>
> Run this command every time you open a new terminal.

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

> See [steps/step04_hello_agent.cpp](steps/step04_hello_agent.cpp)

Let's break down what's happening in the step file:

- `check_ngrok()` queries ngrok's local API at `http://127.0.0.1:4040` to discover the tunnel URL. If ngrok is running, it sets `SWML_PROXY_URL_BASE` -- the environment variable the SDK uses to generate correct webhook URLs.
- `agent::AgentBase` is the foundation class for every agent
- `add_language()` sets up English speech recognition, and `rime.spore` is a warm, friendly text-to-speech voice
- `prompt_add_section()` gives the AI its instructions using the POM (Prompt Object Model)
- `set_post_prompt()` tells the AI to generate a summary after every call
- `on_summary()` receives post-prompt data and saves the JSON payload to a `calls/` folder. You can upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize and debug conversations.
- `agent.run()` starts a web server on port 3000

### Build and Test

```bash
cp steps/step04_hello_agent.cpp agent.cpp && cd build && make && ./agent
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

> **Checkpoint:** You see SWML JSON output from curl. The JSON contains your prompt text and voice settings. If the build fails, check that `SIGNALWIRE_SDK_DIR` points to the right location and that you built the SDK first (`libsignalwire.a` exists). If curl hangs, make sure the agent is running.

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#section-4-ngrok-setup-and-going-live) if you haven't installed ngrok yet.

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

### Understanding the Code

> See [steps/step06_joke_agent.cpp](steps/step06_joke_agent.cpp)

Key concepts in this step:

- `swaig::FunctionResult` is how you return data from a SWAIG function. The AI takes this text and weaves it into its response.
- `define_tool()` registers the function. The `description` is critical -- it tells the AI *when* to call this function.
- `parameters` defines what the AI should extract from the conversation. Our joke function doesn't need any input, so it's an empty object.
- The tool handler is a lambda that takes `(const json& args, const json& raw)` and returns a `swaig::FunctionResult`.
- We use C++'s `<random>` for proper random selection instead of `rand()`.

### Build and Test

```bash
cp steps/step06_joke_agent.cpp agent.cpp && cd build && make && ./agent
```

In another terminal, test the SWML output:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Look for `tell_joke` in the SWML JSON.

### Run and Call

With ngrok still running, call your number and ask for a joke. Try phrases like:
- "Tell me a joke"
- "Make me laugh"
- "Got any jokes?"

The AI should recognize these as requests for humor and call your function.

> **Checkpoint:** When you call and ask for a joke, the agent tells you one from the hardcoded list. You can see function calls in your agent's terminal output. If the agent talks about jokes but doesn't actually tell one from the list, check that your `define_tool` description clearly instructs the AI to use the function.

---

## Section 7: Calling a Live API (15 min)

Hardcoded jokes get old fast. Let's replace them with fresh dad jokes from the API Ninjas Dad Jokes API. Every call will be a different joke.

### Understanding the API

The API Ninjas Dad Jokes endpoint is simple:

- **URL:** `https://api.api-ninjas.com/v1/dadjokes`
- **Method:** GET
- **Auth:** `X-Api-Key` header with your API key
- **Response:** A JSON array with a `joke` field: `[{"joke": "..."}]`

You can test it right now in your terminal:

```bash
curl -s -H "X-Api-Key: YOUR_API_NINJAS_KEY" https://api.api-ninjas.com/v1/dadjokes | python3 -m json.tool
```

### Understanding the Code

> See [steps/step07_joke_agent.cpp](steps/step07_joke_agent.cpp)

What changed from Section 6:

- Removed the `JOKES` vector and `<random>` includes
- The handler now calls the API Ninjas endpoint using `httplib::Client`
- We read the API key from the environment with `std::getenv()`
- There's error handling -- if the API is down or the key is wrong, the agent says something graceful instead of crashing

### Build, Run, and Call

```bash
cp steps/step07_joke_agent.cpp agent.cpp && cd build && make && ./agent
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

### Understanding the Code

> See [steps/step08_weather_joke_agent.cpp](steps/step08_weather_joke_agent.cpp)

The DataMap piece works like this:

- `datamap::DataMap("get_weather")` -- creates a new DataMap function with that name
- `.description(...)` -- tells the AI when to use it (same as `define_tool`)
- `.parameter("city", "string", ...)` -- the AI will extract the city from the caller's request
- `.webhook("GET", url)` -- the HTTP request SignalWire will make. Notice `${enc:args.city}` -- that's the city parameter, URL-encoded, inserted right into the URL
- `.output(...)` -- a template for the response. `${response.current.temp_f}` pulls the temperature from the API's JSON response
- `.fallback_output(...)` -- what to say if the API call fails

The API key is baked into the URL at startup time (via string concatenation). The city gets substituted at call time (via `${enc:args.city}`).

### Build and Test

```bash
cp steps/step08_weather_joke_agent.cpp agent.cpp && cd build && make && ./agent
```

Test the SWML output:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Find the `get_weather` function in the JSON. Notice it has a `data_map` section instead of a `web_hook_url` -- that tells SignalWire to execute the API call directly.

### Call and Test

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

### Understanding the Code

> See [steps/step09_weather_joke_agent.cpp](steps/step09_weather_joke_agent.cpp)

What we improved over Section 8:

- **`set_params()`** -- `end_of_speech_timeout` of 600ms means the agent waits a natural beat before responding (not jumping in too fast). `attention_timeout` of 15 seconds prompts the caller if they go quiet.
- **`add_hints()`** -- helps the speech recognizer with words it might mishear. "Buddy" could sound like "body" without a hint.
- **Richer prompts** -- the "Personality" section gives the AI a character to play. The "Voice Style" section has specific rules for phone conversation. The "Capabilities" section tells the AI what tools it has.

### Build and Call

```bash
cp steps/step09_weather_joke_agent.cpp agent.cpp && cd build && make && ./agent
```

The difference should be noticeable: the agent sounds more natural, has more personality, and handles pauses in conversation better.

> **Checkpoint:** Same capabilities (weather + jokes) but the conversation feels smoother and more natural. The agent has personality, uses varied responses, and handles silence gracefully. Compare the experience to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

### Understanding the Code

> See [steps/step10_weather_joke_agent.cpp](steps/step10_weather_joke_agent.cpp)

The key additions are just two lines:

```cpp
agent.add_skill("datetime", {{"default_timezone", "America/New_York"}});
agent.add_skill("math");
```

That's it. Two lines of code just gave your agent the ability to tell time in any timezone and do math.

### Compare the Approaches

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

### Build and Call

```bash
cp steps/step10_weather_joke_agent.cpp agent.cpp && cd build && make && ./agent
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

> See [steps/step11_complete_agent.cpp](steps/step11_complete_agent.cpp)

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
cp steps/step11_complete_agent.cpp agent.cpp && cd build && make && ./agent
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

Check out the [signalwire-cpp examples](https://github.com/signalwire/signalwire-cpp/tree/main/examples) for more patterns and the SDK README for the full API reference.

---

## Quick Reference

### Switching Steps

To jump to any step, copy the step file and rebuild:

```bash
cp steps/stepXX_name.cpp agent.cpp && cd build && make && ./agent
```

### Environment Variables

```bash
# Load all variables from .env
export $(grep -v '^#' .env | xargs)
```

### Build Commands

```bash
# Full rebuild (after CMake changes)
cd build && cmake .. && make && ./agent

# Quick rebuild (code changes only)
cd build && make && ./agent
```

### Troubleshooting

| Problem | Fix |
|---------|-----|
| `libsignalwire.a` not found | Rebuild the SDK: `cd signalwire-cpp/build && cmake .. && make` |
| OpenSSL not found | macOS: `brew install openssl`; Linux: `apt install libssl-dev` |
| `cmake ..` fails | Check `SIGNALWIRE_SDK_DIR` points to the SDK repo root |
| Agent starts but ngrok not detected | Make sure ngrok is running: `ngrok http 3000 --url your-domain.ngrok-free.app` |
| Curl returns 401 | Check `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` match your curl credentials |
| Weather not working | Verify `WEATHER_API_KEY` is exported in your shell |
| Jokes not working | Verify `API_NINJAS_KEY` is exported in your shell |
| Call doesn't connect | Check the SignalWire dashboard URL has a trailing slash and correct credentials |
