# Build Your First AI Phone Agent -- Ruby Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

## Prerequisites

- Ruby 3.0+ (`ruby --version`)
- Bundler (`gem install bundler` if needed)
- Completed [SignalWire Account Setup](../README.md#section-2-signalwire-account-setup)
- Completed [API Keys and ngrok Setup](../README.md#section-3-api-keys-and-ngrok-setup)

## Step Files

Each section has a corresponding step file in `steps/` with the complete working code for that checkpoint. If you get stuck, compare your code with the step file.

| Section | Step File |
|---------|-----------|
| Section 4: Hello World | `steps/step04_hello_agent.rb` |
| Section 6: Hardcoded Jokes | `steps/step06_joke_agent.rb` |
| Section 7: Live API Jokes | `steps/step07_joke_agent.rb` |
| Section 8: Weather DataMap | `steps/step08_weather_joke_agent.rb` |
| Section 9: Polish | `steps/step09_weather_joke_agent.rb` |
| Section 10: Skills | `steps/step10_weather_joke_agent.rb` |
| Section 11: Complete Agent | `steps/step11_complete_agent.rb` |

---

## Section 3: Project Setup (5 min)

> [!NOTE]
> **Docker users:** The setup script has already run inside the container. Just run `cd ruby` and skip to Section 4.
> The instructions below are for native installs only.

From the workshop root directory, run:

```bash
./setup.sh ruby
cd ruby
```

This installs dependencies and creates your `.env` file (if one doesn't exist).

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

### Key Concepts

- `require 'dotenv/load'` reads your `.env` file so environment variables are available
- `check_ngrok` queries ngrok's local API at `http://127.0.0.1:4040` to discover the tunnel URL and automatically sets `SWML_PROXY_URL_BASE`. If ngrok isn't running yet (Section 5), it prints a message and moves on.
- `SignalWireAgents::AgentBase` is the foundation class for every agent
- `add_language()` sets up English speech recognition; `rime.spore` is a warm, friendly TTS voice
- `prompt_add_section()` gives the AI its instructions
- `set_post_prompt()` tells the AI to generate a summary after every call
- `on_summary` saves the full JSON payload to a `calls/` folder -- upload these to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to debug conversations
- `agent.run` starts a WEBrick HTTP server on port 3000

See [steps/step04_hello_agent.rb](steps/step04_hello_agent.rb)

### Test with swaig-test

Before we run the server, let's verify the agent's configuration is valid:

```bash
ruby bin/swaig-test hello_agent.rb --dump-swml
```

You should see a JSON document -- this is the SWML (SignalWire Markup Language) that tells the SignalWire platform how to run your agent. Look for your prompt text in the output.

You can also test with curl. First, run the agent:

```bash
ruby hello_agent.rb
```

The "No ngrok tunnel detected" message is expected -- we haven't set up ngrok yet (Section 5).

In a **separate terminal** (keep the agent running), test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | ruby -rjson -e 'puts JSON.pretty_generate(JSON.parse(STDIN.read))'
```

Use whatever values you set for `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` in your `.env` file.

> **Checkpoint:** You see SWML JSON output from both `swaig-test` and curl. The JSON contains your prompt text and voice settings. If not, double-check that your `.env` is loaded (is `require 'dotenv/load'` before your other requires?) and that `bundle install` completed successfully.

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#section-4-ngrok-setup-and-going-live) if you haven't installed ngrok yet.

### Step 1: Restart Your Agent

Now that ngrok is running, restart your agent (Ctrl+C the old one, then run it again):

```bash
ruby hello_agent.rb
```

This time you should see:

```
ngrok detected: https://your-domain.ngrok-free.app
INFO: SWML Basic Auth user: workshop
[2026-03-17] INFO  WEBrick::HTTPServer#start: pid=12345 port=3000
```

The `check_ngrok` function we wrote earlier just found your tunnel automatically. No need to manually configure `SWML_PROXY_URL_BASE` -- the agent discovers it on every startup.

### Step 2: Test Through the Tunnel

From another terminal:

```bash
curl -s -u workshop:pickASecurePassword123 https://your-domain.ngrok-free.app/ | ruby -rjson -e 'puts JSON.pretty_generate(JSON.parse(STDIN.read))'
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

### What's New

- `SignalWireAgents::Swaig::FunctionResult` is how you return data from a SWAIG function. The AI takes this text and weaves it into its response.
- `define_tool()` registers the function with a block handler. The `description` is critical -- it tells the AI *when* to call this function.
- `parameters` defines what the AI should extract from the conversation. Our joke function doesn't need any input, so it's an empty hash.
- `function_fillers` are phrases the agent says while your function executes, so there's no awkward silence.

See [steps/step06_joke_agent.rb](steps/step06_joke_agent.rb)

### Test the Function

Stop your previous agent (Ctrl+C) and test the new one:

```bash
ruby bin/swaig-test joke_agent.rb --list-tools
```

You should see `tell_joke` listed. Now test executing it:

```bash
ruby bin/swaig-test joke_agent.rb --exec tell_joke
```

You should see a joke from the list. Run it a few times -- you'll get different jokes.

### Run and Call

```bash
ruby joke_agent.rb
```

With ngrok still running, call your number and ask for a joke. Try phrases like:
- "Tell me a joke"
- "Make me laugh"
- "Got any jokes?"

The AI should recognize these as requests for humor and call your function.

> **Checkpoint:** When you call and ask for a joke, the agent tells you one from the hardcoded list. You can see function calls in your agent's terminal output. If the agent talks about jokes but doesn't actually tell one from the list, check that your `define_tool` description clearly instructs the AI to use the function.

---

## Section 7: Calling a Live API (15 min)

Hardcoded jokes get old fast. Let's replace them with fresh dad jokes from the API Ninjas Dad Jokes API. Every call will be a different joke.

### What Changed

- Removed the `JOKES` array
- The handler now calls the API Ninjas endpoint using Ruby's built-in `Net::HTTP`
- We read the API key from the environment (your `.env` file)
- There's error handling -- if the API is down or the key is wrong, the agent says something graceful instead of crashing
- We use `next` inside the block to return early (since `return` would exit the enclosing method)

See [steps/step07_joke_agent.rb](steps/step07_joke_agent.rb)

### Test It

```bash
ruby bin/swaig-test joke_agent.rb --exec tell_joke
```

Run it several times. Every joke should be different. If you see an error about the API key, make sure `API_NINJAS_KEY` is set in your `.env` file.

### Call and Test

Restart your agent:

```bash
ruby joke_agent.rb
```

Call your number and ask for jokes. Every joke is now fresh from the internet.

> **Checkpoint:** Every time you ask for a joke, you get a different one. Running `swaig-test --exec tell_joke` multiple times confirms this. If you're getting the same joke every time, the API might be caching -- wait a moment and try again.

---

## Section 8: DataMap -- The Serverless Approach (15 min)

For the joke function, you wrote Ruby code that runs on your server. That works great, but there's another way: **DataMap**.

DataMap lets you declare an API call and SignalWire executes it on their infrastructure -- your server never handles the request. See [the full explanation](../README.md#what-is-datamap) for details.

Think of it this way:

- **define_tool** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### Key Concepts

- `DataMap.new('get_weather')` creates a named serverless function
- `.parameter('city', 'string', ...)` -- the AI extracts the city from the caller's request
- `.webhook('GET', url)` -- the HTTP request SignalWire will make. `${enc:args.city}` is the city parameter, URL-encoded, inserted into the URL
- `.output(...)` -- a response template. `${response.current.temp_f}` pulls values from the API's JSON response
- `.fallback_output(...)` -- what to say if the API call fails
- The API key is baked into the URL at startup (string interpolation). The city gets substituted at call time (`${enc:args.city}`).

See [steps/step08_weather_joke_agent.rb](steps/step08_weather_joke_agent.rb)

### Test It

```bash
ruby bin/swaig-test weather_joke_agent.rb --list-tools
```

You should see both `tell_joke` and `get_weather`. Now look at how the DataMap appears in the SWML:

```bash
ruby bin/swaig-test weather_joke_agent.rb --dump-swml
```

Find the `get_weather` function in the JSON. Notice it has a `data_map` section instead of a `web_hook_url` -- that tells SignalWire to execute the API call directly.

Test the joke function still works:

```bash
ruby bin/swaig-test weather_joke_agent.rb --exec tell_joke
```

> **Note:** You can't test DataMap functions locally with `--exec` because they run on SignalWire's infrastructure, not your server. You'll test weather by calling your agent.

### Call and Test

Stop any running agent and start the new one:

```bash
ruby weather_joke_agent.rb
```

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

### What We Improved

- **`set_params()`** -- `end_of_speech_timeout` of 600ms means the agent waits a natural beat before responding (not jumping in too fast). `attention_timeout` of 15 seconds prompts the caller if they go quiet.
- **`add_hints()`** -- helps the speech recognizer with words it might mishear. "Buddy" could sound like "body" without a hint.
- **Richer prompts** -- the "Personality" section gives the AI a character to play. The "Voice Style" section has specific rules for phone conversation. The "Capabilities" section tells the AI what tools it has.
- **More fillers** -- multiple options per function so the agent doesn't say the same thing every time.

See [steps/step09_weather_joke_agent.rb](steps/step09_weather_joke_agent.rb)

### Test and Call

```bash
ruby bin/swaig-test weather_joke_agent.rb --dump-swml
```

Look at the SWML -- you'll see the `hints` array, the `params` section with your timeouts, and the richer prompt. Restart and call:

```bash
ruby weather_joke_agent.rb
```

The difference should be noticeable: the agent sounds more natural, has more personality, and handles pauses in conversation better.

> **Checkpoint:** Same capabilities (weather + jokes) but the conversation feels smoother and more natural. The agent has personality, uses varied filler phrases, and handles silence gracefully. Compare the experience to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

Add two lines after the `register_swaig_function` call, and update the "Capabilities" prompt to mention date/time and math:

```ruby
agent.add_skill('datetime', 'default_timezone' => 'America/New_York')
agent.add_skill('math')
```

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

See [steps/step10_weather_joke_agent.rb](steps/step10_weather_joke_agent.rb)

### Test the New Skills

```bash
ruby bin/swaig-test weather_joke_agent.rb --list-tools
```

You should see your original two functions plus the skill functions: `get_current_time`, `get_current_date`, and `calculate`.

```bash
ruby bin/swaig-test weather_joke_agent.rb --exec get_current_time
ruby bin/swaig-test weather_joke_agent.rb --exec calculate --expression "15/100 * 47.50"
```

### Call and Test

Restart the agent and call:

```bash
ruby weather_joke_agent.rb
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

Let's bring everything together into one clean, final version. This is the definitive `complete_agent.rb` -- combining all four capabilities with polished prompts and tuned parameters.

### What's in the Complete Agent

The code is organized into clear comment-separated sections:

- **Voice and speech** -- voice, fillers, hints
- **AI parameters** -- conversation flow tuning
- **Prompts** -- personality and instructions
- **Dad jokes** -- custom SWAIG function with block handler
- **Weather** -- serverless DataMap
- **Skills** -- built-in datetime and math
- **Post-prompt** -- call summaries saved to `calls/`

This flat, script-style organization is idiomatic Ruby -- no need for a class hierarchy when a single file tells the whole story.

> **Debugging with Post-Prompt Viewer:** After each call, check your `calls/` folder -- you'll find a JSON file for every conversation. Upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize the full conversation flow, see what functions were called, and read the AI-generated summary. It's the fastest way to debug and improve your agent.

See [steps/step11_complete_agent.rb](steps/step11_complete_agent.rb)

### Test Everything

```bash
# Verify configuration
ruby bin/swaig-test complete_agent.rb --dump-swml

# List all tools
ruby bin/swaig-test complete_agent.rb --list-tools

# Test individual functions
ruby bin/swaig-test complete_agent.rb --exec tell_joke
ruby bin/swaig-test complete_agent.rb --exec get_current_time
ruby bin/swaig-test complete_agent.rb --exec calculate --expression "20 * 1.15"
```

### Go Live

```bash
ruby complete_agent.rb
```

Call your number and run through all the capabilities:

1. "Hey, what time is it?" -- datetime skill
2. "What's the weather in Paris?" -- DataMap weather
3. "Tell me a joke!" -- API Ninjas dad jokes
4. "What's 18% tip on $86?" -- math skill
5. "Thanks Buddy, you're great!" -- personality shines

> **Checkpoint:** All four capabilities work end-to-end through a phone call. Your agent has personality, handles pauses naturally, and uses filler phrases while thinking. This is your complete, polished AI phone assistant. Congratulations -- you built this!

---

## Quick Reference

### Common swaig-test Commands

```bash
ruby bin/swaig-test your_agent.rb --dump-swml          # View full SWML configuration
ruby bin/swaig-test your_agent.rb --list-tools         # List registered functions
ruby bin/swaig-test your_agent.rb --exec func_name     # Execute a function
ruby bin/swaig-test your_agent.rb --exec calc --expression "2+2"  # With arguments
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

```ruby
# 1. Custom function (full control, runs on your server)
agent.define_tool(name: 'my_tool', description: '...', parameters: {}) do |args, raw_data|
  SignalWireAgents::Swaig::FunctionResult.new('result text')
end

# 2. DataMap (serverless, runs on SignalWire)
dm = SignalWireAgents::DataMap.new('name')
     .description('...')
     .parameter('param', 'string', 'desc', required: true)
     .webhook('GET', 'https://...')
     .output(SignalWireAgents::Swaig::FunctionResult.new('template'))
agent.register_swaig_function(dm.to_swaig_function)

# 3. Skill (pre-built, one line)
agent.add_skill('skill_name', 'config_key' => 'value')
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| Agent won't start | Check `bundle install` completed and dependencies are installed |
| Can't reach agent from internet | Is ngrok running? Check `http://127.0.0.1:4040` |
| SignalWire can't reach agent | Verify SWML URL has trailing slash, auth matches |
| Weather returns errors | Check `WEATHER_API_KEY` in `.env` |
| Jokes return errors | Check `API_NINJAS_KEY` in `.env` |
| Agent doesn't call functions | Check function `description` -- AI needs clear guidance |
| Speech recognition is wrong | Add `add_hints()` for commonly misheard words |
| Agent responds too fast | Increase `end_of_speech_timeout` in `set_params()` |
| Agent goes silent | Decrease `attention_timeout` in `set_params()` |
