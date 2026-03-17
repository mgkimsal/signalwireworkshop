/**
 * Agent with a hardcoded joke function.
 *
 * Run:
 *   gradle run -PmainClass=Step06JokeAgent
 *
 * Test:
 *   curl -s -u workshop:PASS http://localhost:3000/ | python3 -m json.tool
 */

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

public class Step06JokeAgent {

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
            // ngrok not running
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
                .name("joke-agent")
                .route("/")
                .port(3000)
                .build();

        // Set up the voice
        agent.addLanguage("English", "en-US", "rime.spore");

        // Tell the AI who it is
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

        // Post-prompt: summarize every call
        agent.setPostPrompt(
                "Summarize this conversation in 2-3 sentences. "
                + "Note which jokes were told and how the caller reacted.");

        // Save call summaries
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

        System.out.println("Starting joke agent on port 3000...");
        agent.run();
    }
}
