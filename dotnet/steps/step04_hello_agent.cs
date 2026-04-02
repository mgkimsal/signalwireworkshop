// My first AI phone agent -- Hello World edition.

using SignalWire.Agent;
using SignalWire.SWAIG;
using System.Text.Json;

// --- Load .env file ---
var envFile = Path.Combine(AppContext.BaseDirectory, "../../../.env");
if (!File.Exists(envFile)) envFile = Path.Combine(Directory.GetCurrentDirectory(), ".env");
if (File.Exists(envFile))
{
    foreach (var line in File.ReadAllLines(envFile))
    {
        var trimmed = line.Trim();
        if (string.IsNullOrEmpty(trimmed) || trimmed.StartsWith('#')) continue;
        var idx = trimmed.IndexOf('=');
        if (idx > 0)
            Environment.SetEnvironmentVariable(trimmed[..idx].Trim(), trimmed[(idx + 1)..].Trim());
    }
}

// --- Auto-detect ngrok tunnel ---
try
{
    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(1) };
    var json = await http.GetStringAsync("http://127.0.0.1:4040/api/tunnels");
    var doc = JsonDocument.Parse(json);
    foreach (var tunnel in doc.RootElement.GetProperty("tunnels").EnumerateArray())
    {
        if (tunnel.GetProperty("proto").GetString() == "https")
        {
            var url = tunnel.GetProperty("public_url").GetString()!;
            Environment.SetEnvironmentVariable("SWML_PROXY_URL_BASE", url);
            Console.WriteLine($"ngrok detected: {url}");
            var user = Environment.GetEnvironmentVariable("SWML_BASIC_AUTH_USER") ?? "";
            var pw = Environment.GetEnvironmentVariable("SWML_BASIC_AUTH_PASSWORD") ?? "";
            if (user != "" && pw != "")
            {
                var uri = new Uri(url);
                Console.WriteLine($"\n  SignalWire SWML URL:\n  {uri.Scheme}://{user}:{pw}@{uri.Host}/\n");
            }
            break;
        }
    }
}
catch
{
    var current = Environment.GetEnvironmentVariable("SWML_PROXY_URL_BASE") ?? "";
    if (current != "")
        Console.WriteLine($"Using SWML_PROXY_URL_BASE from .env: {current}");
    else
        Console.WriteLine("No ngrok tunnel detected and SWML_PROXY_URL_BASE not set");
}

// --- Agent ---

var agent = new AgentBase(new AgentOptions { Name = "hello-agent" });

agent.AddLanguage("English", "en-US", "rime.spore");

agent.PromptAddSection(
    "Role",
    "You are a friendly assistant named Buddy. "
    + "You greet callers warmly, ask how their day is going, "
    + "and have a brief pleasant conversation. "
    + "Keep your responses short since this is a phone call."
);

agent.SetPostPrompt(
    "Summarize this conversation in 2-3 sentences. "
    + "Include what the caller wanted and how the conversation went."
);

agent.OnSummary((summary, rawData, headers) =>
{
    Directory.CreateDirectory("calls");
    var callId = rawData?.GetValueOrDefault("call_id")?.ToString()
                 ?? DateTime.Now.ToString("yyyyMMdd_HHmmss");
    var path = $"calls/{callId}.json";
    File.WriteAllText(path, JsonSerializer.Serialize(rawData, new JsonSerializerOptions { WriteIndented = true }));
    Console.WriteLine($"Call summary saved: {path}");
});

agent.Run();
