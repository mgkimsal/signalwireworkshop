# Build Your First AI Phone Agent -- Java Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

## Prerequisites

- Java 21+ (`java --version`)
- Gradle 8+ (`gradle --version`) -- or use the Gradle wrapper (`./gradlew`)
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

---

## Section 3: Project Setup (5 min)

Your SignalWire account and external API keys should already be set up from the [shared setup](../README.md). Now let's create the project.

### Step 1: Create Your Project Directory

Open a terminal and set up your project:

```bash
mkdir workshop-agent
cd workshop-agent
```

### Step 2: Set Your Environment Variables

Java doesn't have a built-in `.env` loader like Python's `dotenv`. Instead, set your environment variables before running the agent. Create a file called `env.sh` that you'll source before each run:

```bash
#!/bin/bash
# SignalWire Credentials
export SIGNALWIRE_PROJECT_ID=your-project-id-here
export SIGNALWIRE_API_TOKEN=your-api-token-here
export SIGNALWIRE_SPACE=your-space.signalwire.com

# Agent Authentication
export SWML_BASIC_AUTH_USER=workshop
export SWML_BASIC_AUTH_PASSWORD=pickASecurePassword123

# Weather API
export WEATHER_API_KEY=your-weatherapi-key-here

# API Ninjas
export API_NINJAS_KEY=your-api-ninjas-key-here
```

Replace every placeholder with your actual values. Then load them:

```bash
source env.sh
```

> **Note:** You might notice there's no `SWML_PROXY_URL_BASE` here. Our agent code will auto-detect your ngrok tunnel at startup -- no need to configure it manually. If you're not using ngrok (e.g., deploying to a cloud server), you can add `export SWML_PROXY_URL_BASE=https://your-server.example.com` to this file as a fallback.

> **Important:** The `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` are credentials that SignalWire will use to authenticate with your agent. Choose whatever you want, but remember them -- you'll enter them into the SignalWire dashboard later.

### Step 3: Create build.gradle

Create a `build.gradle` file:

```groovy
plugins {
    id 'java'
    id 'application'
}

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

repositories {
    mavenCentral()
}

dependencies {
    implementation 'com.signalwire:signalwire-agents:1.0.0'
}

application {
    mainClass = 'HelloAgent'
}
```

And a `settings.gradle` file:

```
rootProject.name = 'workshop-agent'
```

### Step 4: Set Up the Source Directory

Gradle expects your Java files in `src/main/java/`:

```bash
mkdir -p src/main/java
```

Your project directory should now look like this:

```
workshop-agent/
├── env.sh
├── build.gradle
├── settings.gradle
└── src/
    └── main/
        └── java/
```

### Step 5: Build

```bash
gradle build
```

You should see `BUILD SUCCESSFUL`. If you see errors about Java version, make sure `java --version` shows 21 or later.

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

### Step 1: Write Your First Agent

Create a file called `src/main/java/HelloAgent.java`:

`src/main/java/HelloAgent.java`

```java
import com.signalwire.agents.agent.AgentBase;
import com.signalwire.agents.swaig.FunctionResult;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

public class HelloAgent {

    private static final Gson gson = new Gson();

    /**
     * Auto-detect ngrok tunnel and set SWML_PROXY_URL_BASE.
     */
    static void checkNgrok() {
        try {
            var client = HttpClient.newBuilder()
                    .connectTimeout(Duration.ofSeconds(1))
                    .build();
            var request = HttpRequest.newBuilder()
                    .uri(URI.create("http://127.0.0.1:4040/api/tunnels"))
                    .timeout(Duration.ofSeconds(1))
                    .GET()
                    .build();
            var response = client.send(request, HttpResponse.BodyHandlers.ofString());
            Map<String, Object> json = gson.fromJson(response.body(),
                    new TypeToken<Map<String, Object>>() {}.getType());
            @SuppressWarnings("unchecked")
            var tunnels = (List<Map<String, Object>>) json.get("tunnels");
            if (tunnels != null) {
                for (var t : tunnels) {
                    if ("https".equals(t.get("proto"))) {
                        var url = (String) t.get("public_url");
                        System.setProperty("SWML_PROXY_URL_BASE", url);
                        System.out.println("ngrok detected: " + url);
                        return;
                    }
                }
            }
        } catch (Exception e) {
            // ngrok not running -- that's fine
        }
        var current = System.getenv("SWML_PROXY_URL_BASE");
        if (current != null && !current.isEmpty()) {
            System.out.println("Using SWML_PROXY_URL_BASE from env: " + current);
        } else {
            System.out.println("No ngrok tunnel detected and SWML_PROXY_URL_BASE not set");
        }
    }

    public static void main(String[] args) throws Exception {
        checkNgrok();

        var agent = AgentBase.builder()
                .name("hello-agent")
                .route("/")
                .port(3000)
                .build();

        // Set up the voice
        agent.addLanguage("English", "en-US", "rime.spore");

        // Tell the AI who it is
        agent.promptAddSection("Role",
                "You are a friendly assistant named Buddy. "
                + "You greet callers warmly, ask how their day is going, "
                + "and have a brief pleasant conversation. "
                + "Keep your responses short since this is a phone call.");

        // Post-prompt: summarize every call
        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Include what the caller wanted and how the conversation went.");

        // Save call summaries to calls/ folder for debugging
        agent.onSummary((summary, rawData) -> {
            try {
                Files.createDirectories(Path.of("calls"));
                var callId = rawData != null && rawData.containsKey("call_id")
                        ? (String) rawData.get("call_id")
                        : LocalDateTime.now().format(
                                DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
                var filepath = Path.of("calls", callId + ".json");
                Files.writeString(filepath, gson.toJson(rawData));
                System.out.println("Call summary saved: " + filepath);
            } catch (IOException e) {
                System.err.println("Failed to save call summary: " + e.getMessage());
            }
        });

        System.out.println("Starting hello agent on port 3000...");
        agent.run();
    }
}
```

Let's break down what's happening:

- `checkNgrok()` uses `java.net.http.HttpClient` to query ngrok's local API at `http://127.0.0.1:4040` and discover the tunnel URL. If ngrok is running, it sets the `SWML_PROXY_URL_BASE` system property. If ngrok isn't running yet (it isn't -- we'll set it up in Section 5), it prints a helpful message and moves on.
- `AgentBase.builder()` uses the builder pattern to create an agent with a name and route
- `addLanguage()` sets up English speech recognition, and `rime.spore` is a warm, friendly text-to-speech voice
- `promptAddSection()` gives the AI its instructions
- `setPostPrompt()` tells the AI to generate a summary after every call. When the call ends, SignalWire sends the summary data to your agent's `/post_prompt` endpoint.
- `onSummary()` receives that data and saves the full JSON payload to a `calls/` folder. Each file is named by call ID. You can upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize and debug your agent's conversations.
- `agent.run()` starts a web server on port 3000

### Step 2: Build and Run

```bash
source env.sh
gradle build
gradle run
```

You'll see output like:

```
No ngrok tunnel detected and SWML_PROXY_URL_BASE not set
Starting hello agent on port 3000...
INFO: SWML Basic Auth user: workshop
```

The "No ngrok tunnel detected" message is expected -- we haven't set up ngrok yet. That's coming in Section 5.

### Step 3: Test with curl

In a **separate terminal** (keep the agent running), test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Use whatever values you set for `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` in your `env.sh` file.

You should see SWML JSON output. Your agent is serving its configuration correctly.

> **Checkpoint:** You see SWML JSON output from curl. The JSON contains your prompt text and voice settings. If not, double-check that your environment variables are set (`source env.sh`) and that `gradle build` succeeded without errors.

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#step-3-ngrok-account-and-static-domain) if you haven't installed ngrok yet.

### Step 1: Restart Your Agent

Now that ngrok is running, restart your agent (Ctrl+C the old one, then run it again):

```bash
gradle run
```

This time you should see:

```
ngrok detected: https://your-domain.ngrok-free.app
Starting hello agent on port 3000...
INFO: SWML Basic Auth user: workshop
```

The `checkNgrok()` method we wrote earlier just found your tunnel automatically. No need to manually configure `SWML_PROXY_URL_BASE` -- the agent discovers it on every startup.

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

### Step 1: Create the Joke Agent

Create a new file called `src/main/java/JokeAgent.java`:

`src/main/java/JokeAgent.java`

```java
import com.signalwire.agents.agent.AgentBase;
import com.signalwire.agents.swaig.FunctionResult;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

public class JokeAgent {

    private static final Gson gson = new Gson();

    private static final List<String> JOKES = List.of(
            "Why do programmers prefer dark mode? Because light attracts bugs.",
            "I told my wife she was drawing her eyebrows too high. She looked surprised.",
            "What do you call a fake noodle? An impasta.",
            "Why don't scientists trust atoms? Because they make up everything.",
            "I'm reading a book about anti-gravity. It's impossible to put down.",
            "What did the ocean say to the beach? Nothing, it just waved.",
            "Why did the scarecrow win an award? He was outstanding in his field.",
            "I used to hate facial hair, but then it grew on me."
    );

    // ... checkNgrok() same as before (see step file) ...

    public static void main(String[] args) throws Exception {
        // checkNgrok();

        var agent = AgentBase.builder()
                .name("joke-agent")
                .route("/")
                .port(3000)
                .build();

        agent.addLanguage("English", "en-US", "rime.spore");

        agent.promptAddSection("Role",
                "You are a friendly assistant named Buddy. "
                + "You love telling jokes and making people laugh. "
                + "Keep your responses short since this is a phone call.");

        agent.promptAddSection("Guidelines", "Follow these guidelines:", List.of(
                "When someone asks for a joke, use the tell_joke function",
                "After telling a joke, pause for a reaction before offering another",
                "Be enthusiastic and have fun with it"
        ));

        // Register the joke function with hardcoded jokes
        agent.defineTool(
                "tell_joke",
                "Tell the caller a funny joke. Use this whenever someone asks for a joke or humor.",
                Map.of("type", "object", "properties", Map.of()),
                (toolArgs, rawData) -> {
                    var joke = JOKES.get(ThreadLocalRandom.current().nextInt(JOKES.size()));
                    return new FunctionResult("Here's a joke: " + joke);
                }
        );

        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Note which jokes were told and how the caller reacted.");

        // ... onSummary same as before ...

        System.out.println("Starting joke agent on port 3000...");
        agent.run();
    }
}
```

Let's look at the new pieces:

- `FunctionResult` is how you return data from a SWAIG function. The AI takes this text and weaves it into its response.
- `defineTool()` registers the function. The `description` is critical -- it tells the AI *when* to call this function.
- The parameters map defines what the AI should extract from the conversation. Our joke function doesn't need any input, so it's an empty object.
- The tool handler is a lambda `(toolArgs, rawData) -> { ... }` -- Java's functional interface makes this clean.

### Step 2: Test the Function

Update `mainClass` in `build.gradle` to `'JokeAgent'`, or run with:

```bash
gradle run -PmainClass=JokeAgent
```

In another terminal, test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Look for `tell_joke` in the SWML JSON output.

### Step 3: Run and Call

With ngrok still running, call your number and ask for a joke. Try phrases like:
- "Tell me a joke"
- "Make me laugh"
- "Got any jokes?"

The AI should recognize these as requests for humor and call your function.

> **Checkpoint:** When you call and ask for a joke, the agent tells you one from the hardcoded list. You can see function calls in your agent's terminal output. If the agent talks about jokes but doesn't actually tell one from the list, check that your `defineTool` description clearly instructs the AI to use the function.

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

### Step 2: Update the Joke Handler

Replace the hardcoded jokes with a live API call using `java.net.http.HttpClient`. Edit `JokeAgent.java` -- replace the handler lambda and add the HTTP client:

`src/main/java/JokeAgent.java`

```java
import com.signalwire.agents.agent.AgentBase;
import com.signalwire.agents.swaig.FunctionResult;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

public class JokeAgent {

    private static final Gson gson = new Gson();
    private static final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    // ... checkNgrok() same as before ...

    /**
     * Call API Ninjas Dad Jokes endpoint and return the joke text.
     */
    static FunctionResult tellJoke(Map<String, Object> args, Map<String, Object> rawData) {
        var apiKey = System.getenv("API_NINJAS_KEY");
        if (apiKey == null || apiKey.isEmpty()) {
            return new FunctionResult(
                    "Sorry, I can't access my joke book right now. My API key is missing.");
        }

        try {
            var request = HttpRequest.newBuilder()
                    .uri(URI.create("https://api.api-ninjas.com/v1/dadjokes"))
                    .header("X-Api-Key", apiKey)
                    .timeout(Duration.ofSeconds(5))
                    .GET()
                    .build();
            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() != 200) {
                return new FunctionResult(
                        "Sorry, my joke service is taking a nap. Ask me again in a moment!");
            }

            List<Map<String, Object>> jokes = gson.fromJson(response.body(),
                    new TypeToken<List<Map<String, Object>>>() {}.getType());
            if (jokes != null && !jokes.isEmpty()) {
                return new FunctionResult(
                        "Here's a dad joke: " + jokes.getFirst().get("joke"));
            }
            return new FunctionResult(
                    "I tried to find a joke but came up empty. "
                    + "That's... kind of a joke itself?");
        } catch (Exception e) {
            return new FunctionResult(
                    "Sorry, my joke service is taking a nap. Ask me again in a moment!");
        }
    }

    public static void main(String[] args) throws Exception {
        // checkNgrok();

        var agent = AgentBase.builder()
                .name("joke-agent")
                .route("/")
                .port(3000)
                .build();

        agent.addLanguage("English", "en-US", "rime.spore");

        agent.promptAddSection("Role",
                "You are a friendly assistant named Buddy. "
                + "You love telling jokes and making people laugh. "
                + "Keep your responses short since this is a phone call.");

        agent.promptAddSection("Guidelines", "Follow these guidelines:", List.of(
                "When someone asks for a joke, use the tell_joke function",
                "After telling a joke, pause for a reaction before offering another",
                "Be enthusiastic and have fun with it"
        ));

        // Register joke function -- now calls live API via method reference
        agent.defineTool(
                "tell_joke",
                "Tell the caller a funny dad joke. Use this whenever someone asks "
                + "for a joke, humor, or to be entertained.",
                Map.of("type", "object", "properties", Map.of()),
                JokeAgent::tellJoke
        );

        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Note which jokes were told and how the caller reacted.");

        // ... onSummary same as before ...

        System.out.println("Starting joke agent on port 3000...");
        agent.run();
    }
}
```

What changed:

- Removed the `JOKES` list and `ThreadLocalRandom` import
- Added a shared `HttpClient` instance (Java's built-in HTTP client, thread-safe and reusable)
- The `tellJoke` method calls the API Ninjas endpoint using `HttpRequest` and `HttpResponse`
- We read the API key from `System.getenv()` (your `env.sh` file)
- Gson (included as a transitive dependency from `signalwire-agents`) parses the JSON response
- There's error handling -- if the API is down or the key is wrong, the agent says something graceful instead of crashing
- The handler is now a method reference `JokeAgent::tellJoke` instead of an inline lambda

### Step 3: Test and Call

Rebuild and run:

```bash
gradle run -PmainClass=JokeAgent
```

Call your number and ask for jokes. Every joke is now fresh from the internet.

> **Checkpoint:** Every time you ask for a joke, you get a different one. If you're getting errors, make sure `API_NINJAS_KEY` is set in your environment (`source env.sh`).

---

## Section 8: DataMap -- The Serverless Approach (15 min)

For the joke function, you wrote Java code that runs on your server. That works great, but there's another way: **DataMap**.

DataMap lets you declare an API call and SignalWire executes it on their infrastructure -- your server never handles the request. See [the full explanation](../README.md#what-is-datamap) for details.

Think of it this way:

- **defineTool** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### Step 1: Create the Weather + Joke Agent

Let's create a new agent that has both jokes (via your custom function) and weather (via DataMap). Create `src/main/java/WeatherJokeAgent.java`:

`src/main/java/WeatherJokeAgent.java`

```java
import com.signalwire.agents.agent.AgentBase;
import com.signalwire.agents.datamap.DataMap;
import com.signalwire.agents.swaig.FunctionResult;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

public class WeatherJokeAgent {

    private static final Gson gson = new Gson();
    private static final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    // ... checkNgrok() same as before ...

    static FunctionResult tellJoke(Map<String, Object> args, Map<String, Object> rawData) {
        var apiKey = System.getenv("API_NINJAS_KEY");
        if (apiKey == null || apiKey.isEmpty()) {
            return new FunctionResult("Sorry, my joke book is unavailable right now.");
        }

        try {
            var request = HttpRequest.newBuilder()
                    .uri(URI.create("https://api.api-ninjas.com/v1/dadjokes"))
                    .header("X-Api-Key", apiKey)
                    .timeout(Duration.ofSeconds(5))
                    .GET()
                    .build();
            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() != 200) {
                return new FunctionResult(
                        "My joke service is taking a break. Try again in a moment!");
            }

            List<Map<String, Object>> jokes = gson.fromJson(response.body(),
                    new TypeToken<List<Map<String, Object>>>() {}.getType());
            if (jokes != null && !jokes.isEmpty()) {
                return new FunctionResult(
                        "Here's a dad joke: " + jokes.getFirst().get("joke"));
            }
            return new FunctionResult("I couldn't find a joke this time. Try again!");
        } catch (Exception e) {
            return new FunctionResult(
                    "My joke service is taking a break. Try again in a moment!");
        }
    }

    /**
     * Register weather lookup via DataMap (runs on SignalWire's servers).
     */
    static void registerWeatherDataMap(AgentBase agent) {
        var apiKey = System.getenv("WEATHER_API_KEY");
        if (apiKey == null) apiKey = "";

        var weatherDm = new DataMap("get_weather")
                .description(
                        "Get the current weather for a city. "
                        + "Use this when the caller asks about weather, "
                        + "temperature, or conditions.")
                .parameter("city", "string",
                        "The city to get weather for", true)
                .webhook("GET",
                        "https://api.weatherapi.com/v1/current.json?key=" + apiKey
                        + "&q=${enc:args.city}")
                .output(new FunctionResult(
                        "Weather in ${args.city}: "
                        + "${response.current.condition.text}, "
                        + "${response.current.temp_f} degrees Fahrenheit, "
                        + "humidity ${response.current.humidity} percent. "
                        + "Feels like ${response.current.feelslike_f} degrees."))
                .fallbackOutput(new FunctionResult(
                        "Sorry, I couldn't get the weather for ${args.city}. "
                        + "Please check the city name and try again."));

        agent.registerSwaigFunction(weatherDm.toSwaigFunction());
    }

    public static void main(String[] args) throws Exception {
        // checkNgrok();

        var agent = AgentBase.builder()
                .name("weather-joke-agent")
                .route("/")
                .port(3000)
                .build();

        agent.addLanguage("English", "en-US", "rime.spore");

        agent.promptAddSection("Role",
                "You are a friendly assistant named Buddy. "
                + "You help people with weather information and tell great jokes. "
                + "Keep your responses short since this is a phone call.");

        agent.promptAddSection("Guidelines", "Follow these guidelines:", List.of(
                "When someone asks about weather, use the get_weather function",
                "When someone asks for a joke, use the tell_joke function",
                "Be warm, friendly, and conversational"
        ));

        // Custom function: dad jokes (runs on our server)
        agent.defineTool(
                "tell_joke",
                "Tell the caller a funny dad joke. Use this whenever "
                + "someone asks for a joke or humor.",
                Map.of("type", "object", "properties", Map.of()),
                WeatherJokeAgent::tellJoke
        );

        // DataMap: weather (runs on SignalWire's servers)
        registerWeatherDataMap(agent);

        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Note what the caller asked about (weather, jokes, etc.) "
                + "and how the interaction went.");

        // ... onSummary same as before ...

        System.out.println("Starting weather + joke agent on port 3000...");
        agent.run();
    }
}
```

Let's unpack the DataMap piece:

- `new DataMap("get_weather")` -- creates a new DataMap function with that name
- `.description(...)` -- tells the AI when to use it (same as `defineTool`)
- `.parameter("city", "string", ..., true)` -- the AI will extract the city from the caller's request. The `true` marks it as required.
- `.webhook("GET", url)` -- the HTTP request SignalWire will make. Notice `${enc:args.city}` -- that's the city parameter, URL-encoded, inserted right into the URL
- `.output(...)` -- a template for the response. `${response.current.temp_f}` pulls the temperature from the API's JSON response
- `.fallbackOutput(...)` -- what to say if the API call fails

The API key is baked into the URL at startup time (via string concatenation). The city gets substituted at call time (via `${enc:args.city}`).

### Step 2: Test It

```bash
gradle run -PmainClass=WeatherJokeAgent
```

In another terminal, fetch the SWML:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

Find the `get_weather` function in the JSON. Notice it has a `data_map` section instead of a `web_hook_url` -- that tells SignalWire to execute the API call directly.

> **Note:** You can't test DataMap functions locally because they run on SignalWire's infrastructure, not your server. You'll test weather by calling your agent.

### Step 3: Call and Test

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

### Step 1: Upgrade the Prompts

Edit `WeatherJokeAgent.java`. We're keeping the same structure but enhancing the prompt sections and adding AI parameters. Replace the agent setup in `main()`:

```java
        // Voice configuration
        agent.addLanguage("English", "en-US", "rime.spore");

        // AI parameters for better conversation flow
        agent.setParams(Map.of(
                "end_of_speech_timeout", 600,     // Wait 600ms of silence before responding
                "attention_timeout", 15000,       // Prompt after 15s of silence
                "attention_timeout_prompt",
                    "Are you still there? I can help with weather, jokes, or math!"
        ));

        // Speech hints help the recognizer with tricky words
        agent.addHints(List.of("Buddy", "weather", "joke", "temperature", "forecast"));

        // Structured prompt with personality
        agent.promptAddSection("Personality",
                "You are Buddy, a cheerful and witty AI phone assistant. "
                + "You have a warm, upbeat personality and you genuinely enjoy "
                + "helping people. You're a bit of a dad joke enthusiast. "
                + "Think of yourself as that friendly neighbor who always "
                + "has a joke ready and knows what the weather is like.");

        agent.promptAddSection("Voice Style",
                "Since this is a phone conversation, follow these rules:", List.of(
                "Keep responses to 1-2 sentences when possible",
                "Use conversational language, not formal or robotic",
                "React to what the caller says before jumping to information",
                "If they laugh at a joke, acknowledge it warmly",
                "Use natural transitions between topics"
        ));

        agent.promptAddSection("Capabilities",
                "You can help with the following:", List.of(
                "Weather: current conditions for any city worldwide",
                "Jokes: endless supply of dad jokes, always fresh",
                "General chat: friendly conversation on any topic"
        ));
```

See `steps/Step09WeatherJokeAgent.java` for the complete file.

What we improved:

- **`setParams()`** -- `end_of_speech_timeout` of 600ms means the agent waits a natural beat before responding (not jumping in too fast). `attention_timeout` of 15 seconds prompts the caller if they go quiet.
- **`addHints()`** -- helps the speech recognizer with words it might mishear. "Buddy" could sound like "body" without a hint.
- **Richer prompts** -- the "Personality" section gives the AI a character to play. The "Voice Style" section has specific rules for phone conversation. The "Capabilities" section tells the AI what tools it has.

### Step 2: Test and Call

```bash
gradle run -PmainClass=WeatherJokeAgent
```

The difference should be noticeable: the agent sounds more natural, has more personality, and handles pauses in conversation better.

> **Checkpoint:** Same capabilities (weather + jokes) but the conversation feels smoother and more natural. The agent has personality, uses varied filler phrases, and handles silence gracefully. Compare the experience to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

### Step 1: Add DateTime and Math Skills

Edit `WeatherJokeAgent.java`. Add two lines after registering the weather DataMap:

```java
        // Custom function: dad jokes
        agent.defineTool("tell_joke", ...);

        // DataMap: weather
        registerWeatherDataMap(agent);

        // Built-in skills -- one line each, zero configuration
        agent.addSkill("datetime", Map.of("default_timezone", "America/New_York"));
        agent.addSkill("math", Map.of());
```

Also update the "Capabilities" prompt section to mention the new abilities:

```java
        agent.promptAddSection("Capabilities",
                "You can help with the following:", List.of(
                "Weather: current conditions for any city worldwide",
                "Jokes: endless supply of dad jokes, always fresh",
                "Date and time: current time in any timezone",
                "Math: calculations, percentages, conversions",
                "General chat: friendly conversation on any topic"
        ));
```

That's it. Two lines of code just gave your agent the ability to tell time in any timezone and do math.

### Step 2: Compare the Approaches

Let's look at what it took to add each capability:

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

### Step 3: Test the New Skills

Rebuild and run:

```bash
gradle run -PmainClass=WeatherJokeAgent
```

In another terminal, verify the tools appear in the SWML:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

You should see your original two functions plus the skill functions in the SWML output.

### Step 4: Call and Test

Call your number and try asking:
- "What time is it?"
- "What time is it in Tokyo?"
- "What's 15% tip on a $47.50 bill?"
- "What's 144 divided by 12?"
- And of course: weather and jokes still work

> **Checkpoint:** Your agent now handles weather, jokes, time/date, and math. That's four capabilities, and two of them were a single line of code each. Verify all four work by calling and testing each one.

---

## Section 11: The Finished Agent (10 min)

Let's bring everything together into one clean, final version. This is the definitive `CompleteAgent.java` -- combining all four capabilities with polished prompts and tuned parameters.

### The Complete Agent

Create `src/main/java/CompleteAgent.java`:

`src/main/java/CompleteAgent.java`

```java
/**
 * Complete Workshop Agent
 * -----------------------
 * A polished AI phone assistant with four capabilities:
 *   - Dad jokes via API Ninjas (custom defineTool)
 *   - Weather via WeatherAPI (serverless DataMap)
 *   - Date/time via built-in skill
 *   - Math via built-in skill
 *
 * Run:   gradle run -PmainClass=CompleteAgent
 * Test:  curl -s -u workshop:PASS http://localhost:3000/ | python3 -m json.tool
 */

import com.signalwire.agents.agent.AgentBase;
import com.signalwire.agents.datamap.DataMap;
import com.signalwire.agents.swaig.FunctionResult;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

public class CompleteAgent {

    private static final Gson gson = new Gson();
    private static final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    // ------------------------------------------------------------------
    // ngrok auto-detection
    // ------------------------------------------------------------------

    static void checkNgrok() {
        try {
            var request = HttpRequest.newBuilder()
                    .uri(URI.create("http://127.0.0.1:4040/api/tunnels"))
                    .timeout(Duration.ofSeconds(1))
                    .GET()
                    .build();
            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            Map<String, Object> json = gson.fromJson(response.body(),
                    new TypeToken<Map<String, Object>>() {}.getType());
            @SuppressWarnings("unchecked")
            var tunnels = (List<Map<String, Object>>) json.get("tunnels");
            if (tunnels != null) {
                for (var t : tunnels) {
                    if ("https".equals(t.get("proto"))) {
                        var url = (String) t.get("public_url");
                        System.setProperty("SWML_PROXY_URL_BASE", url);
                        System.out.println("ngrok detected: " + url);
                        return;
                    }
                }
            }
        } catch (Exception e) {
            // ngrok not running
        }
        var current = System.getenv("SWML_PROXY_URL_BASE");
        if (current != null && !current.isEmpty()) {
            System.out.println("Using SWML_PROXY_URL_BASE from env: " + current);
        } else {
            System.out.println(
                    "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set");
        }
    }

    // ------------------------------------------------------------------
    // Dad jokes -- custom function calling API Ninjas
    // ------------------------------------------------------------------

    static FunctionResult tellJoke(Map<String, Object> args, Map<String, Object> rawData) {
        var apiKey = System.getenv("API_NINJAS_KEY");
        if (apiKey == null || apiKey.isEmpty()) {
            return new FunctionResult(
                    "Sorry, my joke book is unavailable right now.");
        }

        try {
            var request = HttpRequest.newBuilder()
                    .uri(URI.create("https://api.api-ninjas.com/v1/dadjokes"))
                    .header("X-Api-Key", apiKey)
                    .timeout(Duration.ofSeconds(5))
                    .GET()
                    .build();
            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() != 200) {
                return new FunctionResult(
                        "My joke service is taking a break. Try again in a moment!");
            }

            List<Map<String, Object>> jokes = gson.fromJson(response.body(),
                    new TypeToken<List<Map<String, Object>>>() {}.getType());
            if (jokes != null && !jokes.isEmpty()) {
                return new FunctionResult(
                        "Here's a dad joke: " + jokes.getFirst().get("joke"));
            }
            return new FunctionResult(
                    "I couldn't find a joke this time. Try again!");
        } catch (Exception e) {
            return new FunctionResult(
                    "My joke service is taking a break. Try again in a moment!");
        }
    }

    // ------------------------------------------------------------------
    // Weather -- DataMap (runs on SignalWire, not our server)
    // ------------------------------------------------------------------

    static void registerWeatherDataMap(AgentBase agent) {
        var apiKey = System.getenv("WEATHER_API_KEY");
        if (apiKey == null) apiKey = "";

        var weatherDm = new DataMap("get_weather")
                .description(
                        "Get the current weather for a city. Use this when "
                        + "the caller asks about weather, temperature, or conditions.")
                .parameter("city", "string",
                        "The city to get weather for", true)
                .webhook("GET",
                        "https://api.weatherapi.com/v1/current.json?key=" + apiKey
                        + "&q=${enc:args.city}")
                .output(new FunctionResult(
                        "Weather in ${args.city}: "
                        + "${response.current.condition.text}, "
                        + "${response.current.temp_f} degrees Fahrenheit, "
                        + "humidity ${response.current.humidity} percent. "
                        + "Feels like ${response.current.feelslike_f} degrees."))
                .fallbackOutput(new FunctionResult(
                        "Sorry, I couldn't get the weather for ${args.city}. "
                        + "Please check the city name and try again."));

        agent.registerSwaigFunction(weatherDm.toSwaigFunction());
    }

    // ------------------------------------------------------------------
    // Save call summaries
    // ------------------------------------------------------------------

    static void saveSummary(Map<String, Object> summary, Map<String, Object> rawData) {
        try {
            Files.createDirectories(Path.of("calls"));
            var callId = rawData != null && rawData.containsKey("call_id")
                    ? (String) rawData.get("call_id")
                    : LocalDateTime.now().format(
                            DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
            var filepath = Path.of("calls", callId + ".json");
            Files.writeString(filepath, gson.toJson(rawData));
            System.out.println("Call summary saved: " + filepath);
        } catch (IOException e) {
            System.err.println("Failed to save call summary: " + e.getMessage());
        }
    }

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------

    public static void main(String[] args) throws Exception {
        checkNgrok();

        var agent = AgentBase.builder()
                .name("complete-agent")
                .route("/")
                .port(3000)
                .build();

        // ---- Voice and speech ----

        agent.addLanguage("English", "en-US", "rime.spore");

        agent.addHints(List.of(
                "Buddy", "weather", "joke", "temperature",
                "forecast", "Fahrenheit", "Celsius"
        ));

        // ---- AI parameters ----

        agent.setParams(Map.of(
                "end_of_speech_timeout", 600,
                "attention_timeout", 15000,
                "attention_timeout_prompt",
                    "Are you still there? I can help with weather, "
                    + "jokes, math, or just chat!"
        ));

        // ---- Prompts ----

        agent.promptAddSection("Personality",
                "You are Buddy, a cheerful and witty AI phone assistant. "
                + "You have a warm, upbeat personality and you genuinely enjoy "
                + "helping people. You're a bit of a dad joke enthusiast. "
                + "Think of yourself as that friendly neighbor who always "
                + "has a joke ready and knows what the weather is like.");

        agent.promptAddSection("Voice Style",
                "Since this is a phone conversation:", List.of(
                "Keep responses to 1-2 sentences when possible",
                "Use conversational language, not formal or robotic",
                "React naturally to what the caller says",
                "Use smooth transitions between topics"
        ));

        agent.promptAddSection("Capabilities",
                "You can help with:", List.of(
                "Weather: current conditions for any city worldwide",
                "Jokes: endless supply of fresh dad jokes",
                "Date and time: current time in any timezone",
                "Math: calculations, percentages, unit conversions",
                "General chat: friendly conversation on any topic"
        ));

        agent.promptAddSection("Greeting",
                "When the call starts, introduce yourself as Buddy and "
                + "briefly mention what you can help with. Keep the greeting "
                + "to one or two sentences -- don't list every capability.");

        // ---- Dad jokes: custom function ----

        agent.defineTool(
                "tell_joke",
                "Tell the caller a funny dad joke. Use this whenever "
                + "someone asks for a joke, humor, or to be entertained.",
                Map.of("type", "object", "properties", Map.of()),
                CompleteAgent::tellJoke
        );

        // ---- Weather: DataMap ----

        registerWeatherDataMap(agent);

        // ---- Skills: built-in, zero-code capabilities ----

        agent.addSkill("datetime", Map.of("default_timezone", "America/New_York"));
        agent.addSkill("math", Map.of());

        // ---- Post-prompt ----

        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Note what the caller asked about (weather, jokes, time, "
                + "math, etc.) and how the interaction went.");

        agent.onSummary(CompleteAgent::saveSummary);

        System.out.println("Starting complete agent on port 3000...");
        agent.run();
    }
}
```

### What's Different From the Iterative Version?

Structurally, very little. This is the same agent you've been building, just organized with clean static methods:

- `checkNgrok()` -- ngrok auto-detection
- `tellJoke()` -- custom SWAIG function for dad jokes
- `registerWeatherDataMap()` -- serverless DataMap for weather
- `saveSummary()` -- call summaries saved to `calls/`

The `main()` method wires everything together in a clear, readable sequence: voice, params, prompts, tools, DataMap, skills, post-prompt.

> **Debugging with Post-Prompt Viewer:** After each call, check your `calls/` folder -- you'll find a JSON file for every conversation. Upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize the full conversation flow, see what functions were called, and read the AI-generated summary. It's the fastest way to debug and improve your agent.

### Test Everything

```bash
# Verify it builds
gradle build -PmainClass=CompleteAgent

# Fetch the SWML configuration
gradle run -PmainClass=CompleteAgent
# In another terminal:
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | python3 -m json.tool
```

### Go Live

```bash
gradle run -PmainClass=CompleteAgent
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

Here's what you created today:

```
workshop-agent/
├── env.sh                        # Your API keys and configuration
├── build.gradle                  # Gradle build configuration
├── settings.gradle               # Project name
└── src/
    └── main/
        └── java/
            ├── HelloAgent.java           # Section 4 -- minimal agent
            ├── JokeAgent.java            # Sections 6-7 -- jokes (hardcoded, then API)
            ├── WeatherJokeAgent.java      # Sections 8-10 -- weather + jokes + skills
            ├── CompleteAgent.java         # Section 11 -- the final polished version
            └── calls/                     # Post-prompt data saved after each call
                ├── abc123-def456.json
                └── ...
```

Upload files from `calls/` to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize your conversations.

---

## Quick Reference

### Common Commands

```bash
# Build
gradle build

# Run (default main class)
gradle run

# Run a specific class
gradle run -PmainClass=CompleteAgent

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
| `gradle build` fails | Check `java --version` is 21+, check `build.gradle` syntax |
| Agent won't start | Check env vars are set (`source env.sh`) |
| Can't reach agent from internet | Is ngrok running? Check `http://127.0.0.1:4040` |
| SignalWire can't reach agent | Verify SWML URL has trailing slash, auth matches |
| Weather returns errors | Check `WEATHER_API_KEY` in your environment |
| Jokes return errors | Check `API_NINJAS_KEY` in your environment |
| Agent doesn't call functions | Check function `description` -- AI needs clear guidance |
| Speech recognition is wrong | Add `addHints()` for commonly misheard words |
| Agent responds too fast | Increase `end_of_speech_timeout` in `setParams()` |
| Agent goes silent | Decrease `attention_timeout` in `setParams()` |
