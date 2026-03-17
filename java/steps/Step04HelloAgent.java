/**
 * My first AI phone agent -- Hello World edition.
 *
 * Run:
 *   gradle run -PmainClass=HelloAgent
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
                        : LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
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
