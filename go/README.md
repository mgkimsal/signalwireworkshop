# Build Your First AI Phone Agent -- Go Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

## Prerequisites

- Go 1.22+ (`go version`)
- Completed [SignalWire Account Setup](../README.md#section-2-signalwire-account-setup)
- Completed [API Keys and ngrok Setup](../README.md#section-3-api-keys-and-ngrok-setup)

## Step Files

Each section has a corresponding step file in `steps/` with the complete working code for that checkpoint. If you get stuck, compare your code with the step file.

| Section | Step File |
|---------|-----------|
| Section 4: Hello World | `steps/step04_hello_agent/main.go` |
| Section 6: Hardcoded Jokes | `steps/step06_joke_agent/main.go` |
| Section 7: Live API Jokes | `steps/step07_joke_agent/main.go` |
| Section 8: Weather DataMap | `steps/step08_weather_joke_agent/main.go` |
| Section 9: Polish | `steps/step09_weather_joke_agent/main.go` |
| Section 10: Skills | `steps/step10_weather_joke_agent/main.go` |
| Section 11: Complete Agent | `steps/step11_complete_agent/main.go` |

---

## Section 3: Project Setup (5 min)

> [!NOTE]
> **Docker users:** The setup script has already run inside the container. Just run `cd go` and skip to Section 4.
> The instructions below are for native installs only.

Your SignalWire account and external API keys should already be set up from the [shared setup](../README.md). From the workshop root, run:

```bash
./setup.sh go
```

Then enter the project directory:

```bash
cd go
```

This installs dependencies, creates a `.env` file (if one doesn't exist), and initializes the Go module.

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

See [steps/step04_hello_agent/main.go](steps/step04_hello_agent/main.go)

Here's what the code does:

- `loadEnv()` reads your `.env` file and sets environment variables. This is a minimal implementation included in every step so each file is self-contained. For production, consider the `godotenv` package.
- `checkNgrok()` queries ngrok's local API at `http://127.0.0.1:4040` to discover the tunnel URL. If ngrok is running, it automatically sets `SWML_PROXY_URL_BASE` -- the environment variable the SDK uses to generate correct webhook URLs. If ngrok isn't running yet (it isn't -- we'll set it up in Section 5), it prints a helpful message and moves on.
- `agent.NewAgentBase()` creates the agent using functional options -- `WithName` sets the agent name and `WithRoute` sets the HTTP path.
- `AddLanguage()` configures English speech recognition. `rime.spore` is a warm, friendly text-to-speech voice.
- `PromptAddSection()` gives the AI its instructions. The three parameters are: title, body text, and an optional slice of bullet points (nil here).
- `SetPostPrompt()` tells the AI to generate a summary after every call. When the call ends, SignalWire sends the summary data to your agent's `/post_prompt` endpoint.
- `OnSummary()` receives that data via a callback and saves the full JSON payload to a `calls/` folder. Each file is named by call ID. You can upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize and debug your agent's conversations.
- `a.Run()` starts a web server on port 3000.

### Test Your Agent

Build and run the agent:

```bash
go run .
```

The "No ngrok tunnel detected" message is expected -- we haven't set up ngrok yet. That's coming in Section 5.

In a **separate terminal** (keep the agent running), test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Use whatever values you set for `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` in your `.env` file.

You should see SWML JSON. Your agent is serving its configuration correctly.

> **Checkpoint:** You see SWML JSON output from curl. The JSON contains your prompt text and voice settings. If not, double-check that your `.env` file is in the same directory where you run `go run .`, and that the file format is correct (one `KEY=value` per line).

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#section-4-ngrok-setup-and-going-live) if you haven't installed ngrok yet.

### Step 1: Restart Your Agent

Now that ngrok is running, restart your agent (Ctrl+C the old one, then run it again):

```bash
go run .
```

This time you should see:

```
ngrok detected: https://your-domain.ngrok-free.app
Starting hello-agent on :3000/ ...
```

The `checkNgrok()` function we wrote earlier just found your tunnel automatically. No need to manually configure `SWML_PROXY_URL_BASE` -- the agent discovers it on every startup.

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

### Create the Joke Agent

Replace your `main.go` with the joke agent version.

See [steps/step06_joke_agent/main.go](steps/step06_joke_agent/main.go)

What's new in this step:

- We import `swaig` for `swaig.NewFunctionResult()` -- this is how you return data from a SWAIG function. The AI takes this text and weaves it into its response.
- `agent.ToolDefinition` is a struct with `Name`, `Description`, and `Handler`. The `Description` is critical -- it tells the AI *when* to call this function.
- The `Handler` is a `func(args map[string]any, rawData map[string]any) *swaig.FunctionResult` -- it receives the parsed arguments and raw request data, and returns a result.
- `function_fillers` in the language config are phrases the agent says while your function executes, so there's no awkward silence.
- `PromptAddSection` with a third argument (a `[]string`) adds bullet points under the section body.

### Run and Call

```bash
go run .
```

With ngrok still running, call your number and ask for a joke. Try phrases like:
- "Tell me a joke"
- "Make me laugh"
- "Got any jokes?"

The AI should recognize these as requests for humor and call your function.

> **Checkpoint:** When you call and ask for a joke, the agent tells you one from the hardcoded list. You can see function calls in your agent's terminal output. If the agent talks about jokes but doesn't actually tell one from the list, check that your `ToolDefinition.Description` clearly instructs the AI to use the function.

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

### Update the Joke Handler

Replace your `main.go` with the live API version.

See [steps/step07_joke_agent/main.go](steps/step07_joke_agent/main.go)

What changed from the hardcoded version:

- Removed the `jokes` slice and `math/rand` import
- Added `io` and `net/http` for the API call
- The handler calls `fetchDadJoke()` which makes a real HTTP request
- We read the API key from the environment (your `.env` file)
- There's explicit error handling at every step -- if the API is down or the key is wrong, the agent says something graceful instead of crashing

### Run and Call

Restart your agent and call:

```bash
go run .
```

Call your number and ask for jokes. Every joke is now fresh from the internet.

> **Checkpoint:** Every time you ask for a joke, you get a different one. If you're getting an error about the API key, make sure `API_NINJAS_KEY` is set in your `.env` file.

---

## Section 8: DataMap -- The Serverless Approach (15 min)

For the joke function, you wrote Go code that runs on your server. That works great, but there's another way: **DataMap**.

DataMap lets you declare an API call and SignalWire executes it on their infrastructure -- your server never handles the request. See [the full explanation](../README.md#what-is-datamap) for details.

Think of it this way:

- **DefineTool** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### Create the Weather + Joke Agent

Add weather (via DataMap) alongside jokes (via your custom function).

See [steps/step08_weather_joke_agent/main.go](steps/step08_weather_joke_agent/main.go)

Here's how the DataMap piece works:

- `datamap.New("get_weather")` -- creates a new DataMap builder with that function name
- `.Description(...)` -- tells the AI when to use it (same purpose as `ToolDefinition.Description`)
- `.Parameter("city", "string", "...", true, nil)` -- the AI will extract the city from the caller's request. The `true` means it's required; the `nil` means no enum constraint.
- `.Webhook("GET", url, nil, "", false, nil)` -- the HTTP request SignalWire will make. Notice `${enc:args.city}` -- that's the city parameter, URL-encoded, inserted right into the URL. The remaining parameters are: headers, form param name, input-args-as-params flag, and required args.
- `.Output(...)` -- a template for the response. `${response.current.temp_f}` pulls the temperature from the API's JSON response.
- `.FallbackOutput(...)` -- what to say if the API call fails.
- `a.RegisterSwaigFunction(weatherDM.ToSwaigFunction())` -- registers the DataMap as a SWAIG function on the agent.

The API key is baked into the URL at startup time (via `fmt.Sprintf`). The city gets substituted at call time (via `${enc:args.city}`).

### Test It

```bash
go run .
```

Test with curl to see the SWML:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Find the `get_weather` function in the JSON. Notice it has a `data_map` section instead of a `web_hook_url` -- that tells SignalWire to execute the API call directly.

> **Note:** You can't test DataMap functions locally because they run on SignalWire's infrastructure, not your server. You'll test weather by calling your agent.

### Call and Test

Call your number and try:
- "What's the weather in New York?"
- "How's the weather in London?"
- "Tell me a joke"
- "What's the temperature in Tokyo?"

You now have an agent with two capabilities, built two different ways.

> **Checkpoint:** Your agent answers weather questions with live data AND tells fresh dad jokes. The weather responses include temperature, conditions, and humidity. If weather isn't working, double-check your `WEATHER_API_KEY` in `.env` -- DataMap sends the key directly to WeatherAPI, so it must be correct.

---

## Section 9: Polish and Personality (10 min)

Your agent works, but it sounds a bit robotic. Let's give it a personality and tune the conversation flow. Same file, better experience.

### Upgrade the Prompts

See [steps/step09_weather_joke_agent/main.go](steps/step09_weather_joke_agent/main.go)

What we improved over the previous step:

- **`SetParam()`** -- `end_of_speech_timeout` of 600ms means the agent waits a natural beat before responding (not jumping in too fast). `attention_timeout` of 15 seconds prompts the caller if they go quiet.
- **`AddHints()`** -- helps the speech recognizer with words it might mishear. "Buddy" could sound like "body" without a hint.
- **Richer prompts** -- the "Personality" section gives the AI a character to play. The "Voice Style" section has specific rules for phone conversation. The "Capabilities" section tells the AI what tools it has.
- **Per-tool fillers** -- the `Fillers` field on `ToolDefinition` provides multiple phrases so the agent doesn't say the same thing every time while fetching a joke.

### Test and Call

```bash
go run .
```

Restart and call. The difference should be noticeable: the agent sounds more natural, has more personality, and handles pauses in conversation better.

> **Checkpoint:** Same capabilities (weather + jokes) but the conversation feels smoother and more natural. The agent has personality, uses varied filler phrases, and handles silence gracefully. Compare the experience to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

### Add DateTime and Math Skills

See [steps/step10_weather_joke_agent/main.go](steps/step10_weather_joke_agent/main.go)

The key additions are just two lines:

```go
a.AddSkill("datetime", map[string]any{"default_timezone": "America/New_York"})
a.AddSkill("math", nil)
```

That's it. Two lines of code just gave your agent the ability to tell time in any timezone and do math.

### Compare the Approaches

Let's look at what it took to add each capability:

| Capability | Approach | Lines of Code | Your Server Handles It? |
|-----------|----------|---------------|------------------------|
| Dad Jokes | `DefineTool` | ~30 lines | Yes |
| Weather | DataMap | ~15 lines | No (SignalWire) |
| DateTime | Skill | 1 line | No (built-in) |
| Math | Skill | 1 line | No (built-in) |

**When to use which:**

- **Skills** -- when one exists for what you need. Fastest path, zero maintenance
- **DataMap** -- when you need to call a REST API. No server code, SignalWire handles it
- **DefineTool** -- when you need custom logic, database access, or complex processing

### Call and Test

Restart the agent and call:

```bash
go run .
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

Let's bring everything together into one clean, final version. This is the definitive `complete_agent` -- combining all four capabilities with polished prompts and tuned parameters.

### The Complete Agent

See [steps/step11_complete_agent/main.go](steps/step11_complete_agent/main.go)

The final version organizes everything into clean helper functions:

- `configureVoice()` -- voice, fillers, hints
- `configureParams()` -- AI behavior tuning
- `configurePrompts()` -- personality and instructions
- `registerJokeTool()` -- custom SWAIG function
- `registerWeatherDataMap()` -- serverless DataMap
- `registerSkills()` -- built-in skills
- `configurePostPrompt()` -- call summaries saved to `calls/`

This pattern (small, focused functions that each configure one aspect of the agent) is idiomatic Go and the standard way to organize larger agents.

> **Debugging with Post-Prompt Viewer:** After each call, check your `calls/` folder -- you'll find a JSON file for every conversation. Upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize the full conversation flow, see what functions were called, and read the AI-generated summary. It's the fastest way to debug and improve your agent.

### Test Everything

```bash
go run .
```

Test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

### Go Live

Call your number and run through all the capabilities:

1. "Hey, what time is it?" -- datetime skill
2. "What's the weather in Paris?" -- DataMap weather
3. "Tell me a joke!" -- API Ninjas dad jokes
4. "What's 18% tip on $86?" -- math skill
5. "Thanks Buddy, you're great!" -- personality shines

> **Checkpoint:** All four capabilities work end-to-end through a phone call. Your agent has personality, handles pauses naturally, and uses filler phrases while thinking. This is your complete, polished AI phone assistant. Congratulations -- you built this!

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

### Three Ways to Add Capabilities

```go
// 1. Custom function (full control, runs on your server)
a.DefineTool(agent.ToolDefinition{
	Name:        "my_tool",
	Description: "...",
	Handler: func(args map[string]any, rawData map[string]any) *swaig.FunctionResult {
		return swaig.NewFunctionResult("result text")
	},
})

// 2. DataMap (serverless, runs on SignalWire)
dm := datamap.New("name").
	Description("...").
	Parameter("param", "string", "desc", true, nil).
	Webhook("GET", "https://api.example.com?q=${args.param}", nil, "", false, nil).
	Output(swaig.NewFunctionResult("..."))
a.RegisterSwaigFunction(dm.ToSwaigFunction())

// 3. Skill (pre-built, one line)
a.AddSkill("skill_name", map[string]any{"key": "value"})
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| Agent won't compile | Run `go mod tidy` to resolve dependencies |
| Can't reach agent from internet | Is ngrok running? Check `http://127.0.0.1:4040` |
| SignalWire can't reach agent | Verify SWML URL has trailing slash, auth matches |
| Weather returns errors | Check `WEATHER_API_KEY` in `.env` |
| Jokes return errors | Check `API_NINJAS_KEY` in `.env` |
| Agent doesn't call functions | Check function `Description` -- AI needs clear guidance |
| Speech recognition is wrong | Add `AddHints()` for commonly misheard words |
| Agent responds too fast | Increase `end_of_speech_timeout` via `SetParam()` |
| Agent goes silent | Decrease `attention_timeout` via `SetParam()` |
| `.env` not loading | Make sure `.env` is in the directory where you run `go run .` |
