/**
 * Agent with dad jokes (custom function) and weather (DataMap).
 *
 * Run:
 *   gradle run -PmainClass=WeatherJokeAgent
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

public class WeatherJokeAgent {

    private static final Gson gson = new Gson();
    private static final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

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

    /**
     * Call API Ninjas Dad Jokes endpoint.
     */
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

    /**
     * Register weather lookup via DataMap (runs on SignalWire's servers).
     */
    static void registerWeatherDataMap(AgentBase agent) {
        var apiKey = System.getenv("WEATHER_API_KEY");
        if (apiKey == null) apiKey = "";

        var weatherDm = new DataMap("get_weather")
                .description(
                        "Get the current weather for a city. "
                        + "Use this when the caller asks about weather, temperature, or conditions.")
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

    public static void main(String[] args) throws Exception {
        checkNgrok();

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
                "Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.",
                Map.of("type", "object", "properties", Map.of()),
                WeatherJokeAgent::tellJoke
        );

        // DataMap: weather (runs on SignalWire's servers)
        registerWeatherDataMap(agent);

        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Note what the caller asked about (weather, jokes, etc.) "
                + "and how the interaction went.");

        agent.onSummary((summary, rawData) -> {
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
        });

        System.out.println("Starting weather + joke agent on port 3000...");
        agent.run();
    }
}
