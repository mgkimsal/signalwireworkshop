# Build Your First AI Phone Agent -- Java Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

## Prerequisites

- Java 21+ (`java --version`)
- Gradle wrapper included (`./gradlew`) -- no system Gradle install needed
- Completed [SignalWire Account Setup](../README.md#section-2-signalwire-account-setup)
- Completed [API Keys and ngrok Setup](../README.md#section-3-api-keys-and-ngrok-setup)

## Step Files

Each section has a corresponding step file in `steps/` with the complete working code for that checkpoint. If you get stuck, compare your code with the step file.

| Section | Step File |
|---------|-----------|
| Section 4: Hello World | `steps/Step04HelloAgent.java` |
| Section 6: Hardcoded Jokes | `steps/Step06JokeAgent.java` |
| Section 7: Live API Jokes | `steps/Step07JokeAgent.java` |
| Section 8: Weather DataMap | `steps/Step08WeatherJokeAgent.java` |
| Section 9: Polish | `steps/Step09WeatherJokeAgent.java` |
| Section 10: Skills | `steps/Step10WeatherJokeAgent.java` |
| Section 11: Complete Agent | `steps/Step11CompleteAgent.java` |

### Running a Step File

Each step file's name (e.g. `Step04HelloAgent.java`) differs from the public class inside (e.g. `HelloAgent`). Java requires the filename to match the class name, so copy and rename:

```bash
cp steps/Step04HelloAgent.java src/main/java/HelloAgent.java
./gradlew run -PmainClass=HelloAgent
```

The class names are: `HelloAgent`, `JokeAgent`, `WeatherJokeAgent`, `CompleteAgent`.

---

## Section 3: Project Setup (5 min)

> [!NOTE]
> **Docker users:** The setup script has already run inside the container. Just run `cd java` and skip to Section 4.
> The instructions below are for native installs only.

From the **workshop root**, run `./setup.sh java`, then `cd java`. This builds the SDK jar and creates a `.env` file (if one doesn't exist) with your environment variables.

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

### What This Agent Does

- `checkNgrok()` uses `java.net.http.HttpClient` to query ngrok's local API at `http://127.0.0.1:4040` and discover the tunnel URL. If ngrok is running, it sets the `SWML_PROXY_URL_BASE` system property. If ngrok isn't running yet (it isn't -- we'll set it up in Section 5), it prints a helpful message and moves on.
- `AgentBase.builder()` uses the builder pattern to create an agent with a name and route
- `addLanguage()` sets up English speech recognition, and `rime.spore` is a warm, friendly text-to-speech voice
- `promptAddSection()` gives the AI its instructions
- `setPostPrompt()` tells the AI to generate a summary after every call. When the call ends, SignalWire sends the summary data to your agent's `/post_prompt` endpoint.
- `onSummary()` receives that data and saves the full JSON payload to a `calls/` folder. Each file is named by call ID. You can upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize and debug your agent's conversations.
- `agent.run()` starts a web server on port 3000

See [steps/Step04HelloAgent.java](steps/Step04HelloAgent.java) for the complete code.

### Build and Run

```bash
cp steps/Step04HelloAgent.java src/main/java/HelloAgent.java
./gradlew run -PmainClass=HelloAgent
```

You'll see "No ngrok tunnel detected" -- that's expected, we set up ngrok in Section 5.

### Test with curl

In a **separate terminal** (keep the agent running), test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Use whatever values you set for `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` in your `.env` file.

You should see SWML JSON output. Your agent is serving its configuration correctly.

> **Checkpoint:** You see SWML JSON output from curl. The JSON contains your prompt text and voice settings. If not, double-check that your `.env` file has the correct values and that `./gradlew build` succeeded without errors.

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#section-4-ngrok-setup-and-going-live) if you haven't installed ngrok yet.

### Step 1: Restart Your Agent

Now that ngrok is running, restart your agent (Ctrl+C the old one, then run it again). This time you should see `ngrok detected: https://your-domain.ngrok-free.app` -- the `checkNgrok()` method discovers the tunnel automatically.

```bash
./gradlew run -PmainClass=HelloAgent
```

### Step 2: Test Through the Tunnel

From another terminal:

```bash
curl -s -u workshop:pickASecurePassword123 https://your-domain.ngrok-free.app/ | python3 -m json.tool
```

You should get the same SWML JSON, but now it's coming through the public internet. Look at the `web_hook_url` values in the JSON -- they should reference your ngrok domain, confirming the auto-detection worked.

### Step 3: Connect Your Phone Number

Now the exciting part. Go back to the SignalWire Dashboard:

1. Go to **Phone Numbers**
2. Click on the number you purchased
3. Select **Edit Settings**
4. Click **Select Resource**, then  **+ add**
5. Create a new **Script**, we will be using a **SWML Script**
6. Under **Handle Calls Using**, select **External URL**
7. Enter your ngrok URL: `https://workshop:password123@your-domain.ngrok-free.app/`
8. Click **Save**

> **Don't forget the trailing slash** on the URL. Your agent is serving on `/`.

### Step 4: Call Your Agent

Pick up your phone and call the number you purchased. You should hear the agent greet you!

It can't do much yet -- just have a friendly chat -- but you're talking to an AI agent running on your laptop. That's pretty great for 45 minutes of work.

> **Checkpoint:** You can call your phone number and have a conversation with your agent. It greets you warmly and chats. If the call fails, check: Is ngrok running? Is your agent running? Is the URL in SignalWire correct (with trailing slash)? Check the ngrok web interface at `http://127.0.0.1:4040` to see if requests are reaching your agent.

---

## Section 6: Your First SWAIG Function (15 min)

Your agent can talk, but it can't *do* anything. Let's fix that by teaching it to tell jokes.

SWAIG (SignalWire AI Gateway) functions are tools that the AI can decide to call during a conversation. See [the full explanation](../README.md#what-are-swaig-functions) for details.

### Key Concepts

- `FunctionResult` is how you return data from a SWAIG function. The AI takes this text and weaves it into its response.
- `defineTool()` registers the function. The `description` is critical -- it tells the AI *when* to call this function.
- The parameters map defines what the AI should extract from the conversation. Our joke function doesn't need any input, so it's an empty object.
- The tool handler is a lambda `(toolArgs, rawData) -> { ... }` -- Java's functional interface makes this clean.

See [steps/Step06JokeAgent.java](steps/Step06JokeAgent.java) for the complete code.

### Test and Run

```bash
cp steps/Step06JokeAgent.java src/main/java/JokeAgent.java
./gradlew run -PmainClass=JokeAgent
```

Verify with curl that `tell_joke` appears in the SWML JSON, then call your number. Try phrases like:
- "Tell me a joke"
- "Make me laugh"
- "Got any jokes?"

The AI should recognize these as requests for humor and call your function.

> **Checkpoint:** When you call and ask for a joke, the agent tells you one from the hardcoded list. You can see function calls in your agent's terminal output. If the agent talks about jokes but doesn't actually tell one from the list, check that your `defineTool` description clearly instructs the AI to use the function.

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

### What Changed

- Removed the `JOKES` list and `ThreadLocalRandom` import
- Added a shared `HttpClient` instance (Java's built-in HTTP client, thread-safe and reusable)
- The `tellJoke` method calls the API Ninjas endpoint using `HttpRequest` and `HttpResponse`
- We read the API key from `System.getenv()` (your `.env` file)
- Gson (included as a transitive dependency from `@signalwire/sdk`) parses the JSON response
- There's error handling -- if the API is down or the key is wrong, the agent says something graceful instead of crashing
- The handler is now a method reference `JokeAgent::tellJoke` instead of an inline lambda

See [steps/Step07JokeAgent.java](steps/Step07JokeAgent.java) for the complete code.

### Test and Call

```bash
cp steps/Step07JokeAgent.java src/main/java/JokeAgent.java
./gradlew run -PmainClass=JokeAgent
```

Call your number and ask for jokes. Every joke is now fresh from the internet.

> **Checkpoint:** Every time you ask for a joke, you get a different one. If you're getting errors, make sure `API_NINJAS_KEY` is set in your `.env` file.

---

## Section 8: DataMap -- The Serverless Approach (15 min)

For the joke function, you wrote Java code that runs on your server. That works great, but there's another way: **DataMap**.

DataMap lets you declare an API call and SignalWire executes it on their infrastructure -- your server never handles the request. See [the full explanation](../README.md#what-is-datamap) for details.

Think of it this way:

- **defineTool** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### Key Concepts

- `new DataMap("get_weather")` -- creates a new DataMap function with that name
- `.description(...)` -- tells the AI when to use it (same as `defineTool`)
- `.parameter("city", "string", ..., true)` -- the AI will extract the city from the caller's request. The `true` marks it as required.
- `.webhook("GET", url)` -- the HTTP request SignalWire will make. Notice `${enc:args.city}` -- that's the city parameter, URL-encoded, inserted right into the URL
- `.output(...)` -- a template for the response. `${response.current.temp_f}` pulls the temperature from the API's JSON response
- `.fallbackOutput(...)` -- what to say if the API call fails

The API key is baked into the URL at startup time (via string concatenation). The city gets substituted at call time (via `${enc:args.city}`).

See [steps/Step08WeatherJokeAgent.java](steps/Step08WeatherJokeAgent.java) for the complete code.

### Test It

```bash
cp steps/Step08WeatherJokeAgent.java src/main/java/WeatherJokeAgent.java
./gradlew run -PmainClass=WeatherJokeAgent
```

Fetch the SWML with curl and find the `get_weather` function. Notice it has a `data_map` section instead of a `web_hook_url` -- that tells SignalWire to execute the API call directly.

> **Note:** You can't test DataMap functions locally because they run on SignalWire's infrastructure, not your server. You'll test weather by calling your agent.

### Call and Test

Call your number and try:
- "What's the weather in New York?"
- "How's the weather in London?"
- "Tell me a joke"
- "What's the temperature in Tokyo?"

You now have an agent with two capabilities, built two different ways.

> **Checkpoint:** Your agent answers weather questions with live data AND tells fresh dad jokes. The weather responses include temperature, conditions, and humidity. If weather isn't working, double-check your `WEATHER_API_KEY` in your environment -- DataMap sends the key directly to WeatherAPI, so it must be correct.

---

## Section 9: Polish and Personality (10 min)

Your agent works, but it sounds a bit robotic. Let's give it a personality and tune the conversation flow. Same file, better experience.

### What We Improved

- **`setParams()`** -- `end_of_speech_timeout` of 600ms means the agent waits a natural beat before responding (not jumping in too fast). `attention_timeout` of 15 seconds prompts the caller if they go quiet.
- **`addHints()`** -- helps the speech recognizer with words it might mishear. "Buddy" could sound like "body" without a hint.
- **Richer prompts** -- the "Personality" section gives the AI a character to play. The "Voice Style" section has specific rules for phone conversation. The "Capabilities" section tells the AI what tools it has.

See [steps/Step09WeatherJokeAgent.java](steps/Step09WeatherJokeAgent.java) for the complete code.

### Test and Call

```bash
cp steps/Step09WeatherJokeAgent.java src/main/java/WeatherJokeAgent.java
./gradlew run -PmainClass=WeatherJokeAgent
```

The difference should be noticeable: more natural speech, personality, and better pause handling.

> **Checkpoint:** Same capabilities (weather + jokes) but the conversation feels smoother and more natural. The agent has personality, uses varied filler phrases, and handles silence gracefully. Compare the experience to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

### How It Works

Add two lines after registering the weather DataMap:

```java
// Built-in skills -- one line each, zero configuration
agent.addSkill("datetime", Map.of("default_timezone", "America/New_York"));
agent.addSkill("math", Map.of());
```

Also update the "Capabilities" prompt section to mention the new abilities.

That's it. Two lines of code just gave your agent the ability to tell time in any timezone and do math.

### Compare the Approaches

| Capability | Approach | Lines of Code | Your Server Handles It? |
|-----------|----------|---------------|------------------------|
| Dad Jokes | `defineTool` | ~30 lines | Yes |
| Weather | DataMap | ~15 lines | No (SignalWire) |
| DateTime | Skill | 1 line | No (built-in) |
| Math | Skill | 1 line | No (built-in) |

**When to use which:**

- **Skills** -- when one exists for what you need. Fastest path, zero maintenance
- **DataMap** -- when you need to call a REST API. No server code, SignalWire handles it
- **defineTool** -- when you need custom logic, database access, or complex processing

See [steps/Step10WeatherJokeAgent.java](steps/Step10WeatherJokeAgent.java) for the complete code.

### Test the New Skills

```bash
cp steps/Step10WeatherJokeAgent.java src/main/java/WeatherJokeAgent.java
./gradlew run -PmainClass=WeatherJokeAgent
```

Verify the skill functions appear in the SWML output alongside your existing tools. Call your number and try:
- "What time is it?"
- "What time is it in Tokyo?"
- "What's 15% tip on a $47.50 bill?"
- "What's 144 divided by 12?"
- And of course: weather and jokes still work

> **Checkpoint:** Your agent now handles weather, jokes, time/date, and math. That's four capabilities, and two of them were a single line of code each. Verify all four work by calling and testing each one.

---

## Section 11: The Finished Agent (10 min)

Let's bring everything together into one clean, final version. This is the definitive `CompleteAgent.java` -- combining all four capabilities with polished prompts and tuned parameters.

### What's in the Complete Agent

The agent is organized with clean static methods:

- `checkNgrok()` -- ngrok auto-detection
- `tellJoke()` -- custom SWAIG function for dad jokes
- `registerWeatherDataMap()` -- serverless DataMap for weather
- `saveSummary()` -- call summaries saved to `calls/`

The `main()` method wires everything together in a clear, readable sequence: voice, params, prompts, tools, DataMap, skills, post-prompt.

> **Debugging with Post-Prompt Viewer:** After each call, check your `calls/` folder -- you'll find a JSON file for every conversation. Upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize the full conversation flow, see what functions were called, and read the AI-generated summary. It's the fastest way to debug and improve your agent.

See [steps/Step11CompleteAgent.java](steps/Step11CompleteAgent.java) for the complete code.

### Test Everything

```bash
cp steps/Step11CompleteAgent.java src/main/java/CompleteAgent.java
./gradlew run -PmainClass=CompleteAgent
```

Call your number and run through all the capabilities:

1. "Hey, what time is it?" -- datetime skill
2. "What's the weather in Paris?" -- DataMap weather
3. "Tell me a joke!" -- API Ninjas dad jokes
4. "What's 18% tip on $86?" -- math skill
5. "Thanks Buddy, you're great!" -- personality shines

> **Checkpoint:** All four capabilities work end-to-end through a phone call. Your agent has personality, handles pauses naturally, and uses filler phrases while thinking. This is your complete, polished AI phone assistant. Congratulations -- you built this!

---

## Your Files

Upload files from `calls/` to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize your conversations.

---

## Quick Reference

### Common Commands

```bash
# Build
./gradlew build

# Run (default main class)
./gradlew run

# Run a specific class
./gradlew run -PmainClass=CompleteAgent

# Fetch SWML from a running agent
curl -s -u workshop:PASS http://localhost:3000/ | python3 -m json.tool
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `SWML_BASIC_AUTH_USER` | Username for agent authentication |
| `SWML_BASIC_AUTH_PASSWORD` | Password for agent authentication |
| `SWML_PROXY_URL_BASE` | Auto-detected from ngrok; set manually only if not using ngrok |
| `WEATHER_API_KEY` | WeatherAPI.com API key |
| `API_NINJAS_KEY` | API Ninjas API key |

### Three Ways to Add Capabilities

```java
// 1. Custom function (full control, runs on your server)
agent.defineTool("name", "description", paramsMap, (args, raw) -> {
    return new FunctionResult("response text");
});

// 2. DataMap (serverless, runs on SignalWire)
var dm = new DataMap("name")
    .description("...").parameter(...).webhook(...).output(...);
agent.registerSwaigFunction(dm.toSwaigFunction());

// 3. Skill (pre-built, one line)
agent.addSkill("skill_name", Map.of("config_key", "value"));
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `./gradlew build` fails | Check `java --version` is 21+, check `build.gradle` syntax |
| Agent won't start | Check env vars are set in your `.env` file |
| Can't reach agent from internet | Is ngrok running? Check `http://127.0.0.1:4040` |
| SignalWire can't reach agent | Verify SWML URL has trailing slash, auth matches |
| Weather returns errors | Check `WEATHER_API_KEY` in your environment |
| Jokes return errors | Check `API_NINJAS_KEY` in your environment |
| Agent doesn't call functions | Check function `description` -- AI needs clear guidance |
| Speech recognition is wrong | Add `addHints()` for commonly misheard words |
| Agent responds too fast | Increase `end_of_speech_timeout` in `setParams()` |
| Agent goes silent | Decrease `attention_timeout` in `setParams()` |
