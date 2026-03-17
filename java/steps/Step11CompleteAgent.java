/**
 * Complete Workshop Agent
 * -----------------------
 * A polished AI phone assistant with four capabilities:
 *   - Dad jokes via API Ninjas (custom defineTool)
 *   - Weather via WeatherAPI (serverless DataMap)
 *   - Date/time via built-in skill
 *   - Math via built-in skill
 *
 * Run:
 *   gradle run -PmainClass=Step11CompleteAgent
 *
 * Test:
 *   curl -s -u workshop:PASS http://localhost:3000/ | python3 -m json.tool
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

public class Step11CompleteAgent {

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
            System.out.println("No ngrok tunnel detected and SWML_PROXY_URL_BASE not set");
        }
    }

    // ------------------------------------------------------------------
    // Dad jokes -- custom function calling API Ninjas
    // ------------------------------------------------------------------

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
                return new FunctionResult("Here's a dad joke: " + jokes.getFirst().get("joke"));
            }
            return new FunctionResult("I couldn't find a joke this time. Try again!");
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
                .parameter("city", "string", "The city to get weather for", true)
                .webhook("GET",
                        "https://api.weatherapi.com/v1/current.json?key=" + apiKey
                        + "&q=${enc:args.city}")
                .output(new FunctionResult(
                        "Weather in ${args.city}: ${response.current.condition.text}, "
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
                    : LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
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
                    "Are you still there? I can help with weather, jokes, math, or just chat!"
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
                Step11CompleteAgent::tellJoke
        );

        // ---- Weather: DataMap ----

        registerWeatherDataMap(agent);

        // ---- Skills: built-in, zero-code capabilities ----

        agent.addSkill("datetime", Map.of("default_timezone", "America/New_York"));
        agent.addSkill("math", Map.of());

        // ---- Post-prompt ----

        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Note what the caller asked about (weather, jokes, time, math, etc.) "
                + "and how the interaction went.");

        agent.onSummary(Step11CompleteAgent::saveSummary);

        System.out.println("Starting complete agent on port 3000...");
        agent.run();
    }
}
