# Build Your First AI Phone Agent -- Perl Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

## Prerequisites

- Perl 5.26+ (`perl -v`)
- cpanm (`cpanm --version` -- install via `curl -L https://cpanmin.us | perl - --sudo App::cpanminus` if needed)
- Completed [SignalWire Account Setup](../README.md#section-2-signalwire-account-setup)
- Completed [API Keys and ngrok Setup](../README.md#section-3-api-keys-and-ngrok-setup)

## Step Files

Each section has a corresponding step file in `steps/` with the complete working code for that checkpoint. If you get stuck, compare your code with the step file.

| Section | Step File |
|---------|-----------|
| Section 4: Hello World | `steps/step04_hello_agent.pl` |
| Section 6: Hardcoded Jokes | `steps/step06_joke_agent.pl` |
| Section 7: Live API Jokes | `steps/step07_joke_agent.pl` |
| Section 8: Weather DataMap | `steps/step08_weather_joke_agent.pl` |
| Section 9: Polish | `steps/step09_weather_joke_agent.pl` |
| Section 10: Skills | `steps/step10_weather_joke_agent.pl` |
| Section 11: Complete Agent | `steps/step11_complete_agent.pl` |

---

## Section 3: Project Setup (5 min)

From the workshop root directory, run the setup script and change into the Perl project:

```bash
./setup.sh perl
cd perl
```

This installs dependencies, creates your `.env` template, and sets up the project structure. Fill in your actual API keys in the `.env` file before continuing.

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

### Step 1: Install Dependencies

```bash
cpanm --installdeps .
```

If you install into a local directory (`cpanm -l local --installdeps .`), set `PERL5LIB=local/lib/perl5:lib` when running your agent. All our examples include `use lib 'lib'` so the SDK is found automatically.

### Step 2: Write Your First Agent

Create a file called `hello_agent.pl`.

See [steps/step04_hello_agent.pl](steps/step04_hello_agent.pl)

Key concepts in the code:

- The `.env` loader parses `KEY=VALUE` lines into `%ENV` (Perl has no built-in dotenv).
- `check_ngrok()` queries ngrok's local API to auto-discover the tunnel URL and set `SWML_PROXY_URL_BASE`. If ngrok isn't running yet (Section 5), it prints a message and moves on.
- `HelloAgent` extends `SignalWire::Agent::AgentBase` using Moo. Configuration happens in `BUILD`.
- `add_language()` sets the voice, language code, and speech fillers.
- `prompt_add_section()` gives the AI its instructions.
- `set_post_prompt()` tells the AI to generate a summary after every call.
- `on_summary()` saves the full JSON payload to a `calls/` folder. Upload these to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to debug conversations.
- `$agent->run` starts a Plack HTTP server on port 3000.

### Step 3: Test with swaig-test

```bash
perl bin/swaig-test hello_agent.pl --dump-swml
```

You should see a SWML JSON document containing your prompt text. You can also run `perl hello_agent.pl`, then in a separate terminal:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | perl -MJSON -e 'print JSON->new->pretty->encode(decode_json(join "", <>))'
```

> **Checkpoint:** You see SWML JSON from both `swaig-test` and curl, containing your prompt and voice settings.

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#step-3-ngrok-account-and-static-domain) if you haven't installed ngrok yet.

### Step 1: Restart Your Agent

With ngrok running, restart your agent (`perl hello_agent.pl`). This time you should see `ngrok detected: https://your-domain.ngrok-free.app` -- the `check_ngrok()` function auto-discovers the tunnel on every startup.

### Step 2: Test Through the Tunnel

```bash
curl -s -u workshop:pickASecurePassword123 https://your-domain.ngrok-free.app/ | perl -MJSON -e 'print JSON->new->pretty->encode(decode_json(join "", <>))'
```

The `web_hook_url` values in the JSON should reference your ngrok domain.

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

Call the number you purchased. You should hear Buddy greet you! It can't do much yet -- just friendly chat -- but you're talking to an AI agent running on your laptop.

> **Checkpoint:** You can call and have a conversation. If the call fails, check: Is ngrok running? Is your agent running? Is the URL in SignalWire correct (with trailing slash)? Check `http://127.0.0.1:4040` for request logs.

---

## Section 6: Your First SWAIG Function (15 min)

Your agent can talk, but it can't *do* anything. Let's fix that by teaching it to tell jokes.

SWAIG (SignalWire AI Gateway) functions are tools that the AI can decide to call during a conversation. See [the full explanation](../README.md#what-are-swaig-functions) for details.

### Step 1: Create the Joke Agent

Create a new file called `joke_agent.pl`.

See [steps/step06_joke_agent.pl](steps/step06_joke_agent.pl)

Key concepts:

- `FunctionResult->new("text")` returns data from a SWAIG function -- the AI weaves this into its response.
- `define_tool()` registers the function. The `description` tells the AI *when* to call it.
- `parameters` defines what the AI extracts from conversation. Our joke function needs no input, so it's empty.
- `function_fillers` are phrases spoken while your function executes, avoiding awkward silence.
- The handler is a `sub` receiving `($args, $raw_data)` and returning a `FunctionResult`.

### Step 2: Test and Call

```bash
perl bin/swaig-test joke_agent.pl --list-tools          # Should show tell_joke
perl bin/swaig-test joke_agent.pl --exec tell_joke       # Run a few times for different jokes
perl joke_agent.pl                                       # Then call your number
```

Try "Tell me a joke", "Make me laugh", or "Got any jokes?"

> **Checkpoint:** The agent tells jokes from the hardcoded list. If it talks about jokes but doesn't use the function, check the `define_tool` description.

---

## Section 7: Calling a Live API (15 min)

Hardcoded jokes get old fast. Let's replace them with fresh dad jokes from the API Ninjas Dad Jokes API. Every call will be a different joke.

### Step 1: Understanding the API

The API Ninjas Dad Jokes endpoint: `GET https://api.api-ninjas.com/v1/dadjokes` with an `X-Api-Key` header. Returns `[{"joke": "..."}]`.

### Step 2: Update the Joke Agent

Replace `joke_agent.pl` with the live API version.

See [steps/step07_joke_agent.pl](steps/step07_joke_agent.pl)

What changed:

- Removed the `@JOKES` array -- the handler now calls API Ninjas via `HTTP::Tiny`
- API key read from `$ENV{API_NINJAS_KEY}` (loaded from `.env`)
- Graceful error handling if the API is down or the key is wrong
- Safe JSON parsing with `eval { decode_json(...) }`

### Step 3: Test and Call

```bash
perl bin/swaig-test joke_agent.pl --exec tell_joke       # Run several times -- every joke is different
perl joke_agent.pl                                       # Then call your number
```

> **Checkpoint:** Every joke is different. If you see API key errors, check `API_NINJAS_KEY` in `.env`.

---

## Section 8: DataMap -- The Serverless Approach (15 min)

For the joke function, you wrote Perl code that runs on your server. That works great, but there's another way: **DataMap**.

DataMap lets you declare an API call and SignalWire executes it on their infrastructure -- your server never handles the request. See [the full explanation](../README.md#what-is-datamap) for details.

Think of it this way:

- **define_tool** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### Step 1: Create the Weather + Joke Agent

Create `weather_joke_agent.pl` that has both jokes (via your custom function) and weather (via DataMap).

See [steps/step08_weather_joke_agent.pl](steps/step08_weather_joke_agent.pl)

Key DataMap concepts:

- `DataMap->new('get_weather')` creates the function; `->description(...)` tells the AI when to use it.
- `->parameter('city', 'string', ...)` -- the AI extracts the city from conversation.
- `->webhook('GET', $url)` -- SignalWire makes this HTTP request. `${enc:args.city}` is URL-encoded parameter substitution.
- `->output(...)` -- response template. `${response.current.temp_f}` pulls from the API's JSON.
- `->fallback_output(...)` -- what to say if the API call fails.

The API key is baked into the URL at startup (Perl interpolation). The city is substituted at call time (`${enc:args.city}`).

> **Perl tip:** Use `\${enc:args.city}` (backslash) or single-quoted strings to prevent Perl from interpreting `${args.*}` and `${response.*}` templates as variables.

### Step 2: Test and Call

```bash
perl bin/swaig-test weather_joke_agent.pl --list-tools   # Should show tell_joke and get_weather
perl bin/swaig-test weather_joke_agent.pl --dump-swml    # get_weather has data_map instead of web_hook_url
perl bin/swaig-test weather_joke_agent.pl --exec tell_joke
```

> **Note:** DataMap functions can't be tested locally with `--exec` -- they run on SignalWire's infrastructure. Test weather by calling your agent.

```bash
perl weather_joke_agent.pl
```

Try: "What's the weather in New York?", "Tell me a joke", "What's the temperature in Tokyo?"

> **Checkpoint:** Weather returns live data (temperature, conditions, humidity) AND jokes still work. If weather fails, check `WEATHER_API_KEY` in `.env`.

---

## Section 9: Polish and Personality (10 min)

Your agent works, but it sounds a bit robotic. Let's give it a personality and tune the conversation flow. Same file, better experience.

### Step 1: Upgrade the Prompts

Edit `weather_joke_agent.pl` to add personality, AI parameters, and speech hints.

See [steps/step09_weather_joke_agent.pl](steps/step09_weather_joke_agent.pl)

What we improved:

- **`set_params()`** -- `end_of_speech_timeout` (600ms) adds a natural pause before responding; `attention_timeout` (15s) prompts the caller if they go quiet.
- **`add_hints()`** -- helps the speech recognizer with tricky words ("Buddy" could sound like "body").
- **Richer prompts** -- "Personality" gives the AI a character; "Voice Style" has phone-specific rules; "Capabilities" lists available tools.
- **More fillers** -- multiple options per function for variety.

### Step 2: Test and Call

```bash
perl bin/swaig-test weather_joke_agent.pl --dump-swml    # Check hints, params, richer prompt
perl weather_joke_agent.pl                               # Restart and call
```

> **Checkpoint:** Same capabilities but the conversation feels smoother and more natural. Compare to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

### Step 1: Add DateTime and Math Skills

Edit `weather_joke_agent.pl`. Add two lines inside `BUILD`, after the `_register_weather_datamap()` call:

```perl
        $self->_register_joke_function();
        $self->_register_weather_datamap();

        # Built-in skills -- one line each, zero configuration
        $self->add_skill('datetime', { default_timezone => 'America/New_York' });
        $self->add_skill('math');
```

Also update the "Capabilities" prompt section to mention the new abilities.

See [steps/step10_weather_joke_agent.pl](steps/step10_weather_joke_agent.pl)

### Step 2: Compare the Approaches

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

### Step 3: Test the New Skills

```bash
perl bin/swaig-test weather_joke_agent.pl --list-tools
```

You should see your original two functions plus the skill functions: `get_current_time`, `get_current_date`, and `calculate`.

```bash
perl bin/swaig-test weather_joke_agent.pl --exec get_current_time
perl bin/swaig-test weather_joke_agent.pl --exec calculate --expression "15/100 * 47.50"
```

### Step 4: Call and Test

Restart the agent and call:

```bash
perl weather_joke_agent.pl
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

Let's bring everything together into one clean, final version. This is the definitive `complete_agent.pl` -- combining all four capabilities with polished prompts and tuned parameters.

### The Complete Agent

Create `complete_agent.pl`.

See [steps/step11_complete_agent.pl](steps/step11_complete_agent.pl)

### What's Different?

Same agent, now organized into clean private methods: `_configure_voice()`, `_configure_params()`, `_configure_prompts()`, `_register_joke_function()`, `_register_weather_datamap()`, `_register_skills()`, `_configure_post_prompt()`. This `_configure_*` / `_register_*` pattern is the standard way to organize larger agents.

> **Debugging:** After each call, check `calls/` for JSON files. Upload them to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize conversations and debug.

### Test Everything

```bash
# Verify configuration
perl bin/swaig-test complete_agent.pl --dump-swml

# List all tools
perl bin/swaig-test complete_agent.pl --list-tools

# Test individual functions
perl bin/swaig-test complete_agent.pl --exec tell_joke
perl bin/swaig-test complete_agent.pl --exec get_current_time
perl bin/swaig-test complete_agent.pl --exec calculate --expression "20 * 1.15"
```

### Go Live

```bash
perl complete_agent.pl
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
perl bin/swaig-test your_agent.pl --dump-swml          # View full SWML configuration
perl bin/swaig-test your_agent.pl --list-tools         # List registered functions
perl bin/swaig-test your_agent.pl --exec func_name     # Execute a function
perl bin/swaig-test your_agent.pl --exec calc --expression "2+2"  # With arguments
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

```perl
# 1. Custom function (full control, runs on your server)
$self->define_tool(name => '...', description => '...', parameters => {...}, handler => sub { ... });

# 2. DataMap (serverless, runs on SignalWire)
my $dm = SignalWire::DataMap->new('name')->description('...')->parameter(...)->webhook(...)->output(...);
$self->register_swaig_function($dm->to_swaig_function);

# 3. Skill (pre-built, one line)
$self->add_skill('skill_name', { config => 'value' });
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| Agent won't start | Check `PERL5LIB` includes `lib` and dependencies are installed |
| Module not found | Run `cpanm --installdeps .` and check `use lib 'lib'` is in your script |
| Can't reach agent from internet | Is ngrok running? Check `http://127.0.0.1:4040` |
| SignalWire can't reach agent | Verify SWML URL has trailing slash, auth matches |
| Weather returns errors | Check `WEATHER_API_KEY` in `.env` |
| Jokes return errors | Check `API_NINJAS_KEY` in `.env` |
| Agent doesn't call functions | Check function `description` -- AI needs clear guidance |
| Speech recognition is wrong | Add `add_hints()` for commonly misheard words |
| Agent responds too fast | Increase `end_of_speech_timeout` in `set_params()` |
| Agent goes silent | Decrease `attention_timeout` in `set_params()` |
| String interpolation issues | Use `\$` or single quotes to prevent Perl from expanding `${args.*}` templates |
