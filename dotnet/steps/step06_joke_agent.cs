// Agent with a hardcoded joke function.

using SignalWire.Agent;
using SignalWire.SWAIG;
using System.Text.Json;

var envFile = Path.Combine(Directory.GetCurrentDirectory(), ".env");
if (File.Exists(envFile))
    foreach (var line in File.ReadAllLines(envFile))
    {
        var t = line.Trim();
        if (string.IsNullOrEmpty(t) || t.StartsWith('#')) continue;
        var i = t.IndexOf('=');
        if (i > 0) Environment.SetEnvironmentVariable(t[..i].Trim(), t[(i + 1)..].Trim());
    }

try
{
    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(1) };
    var json = await http.GetStringAsync("http://127.0.0.1:4040/api/tunnels");
    var doc = JsonDocument.Parse(json);
    foreach (var tunnel in doc.RootElement.GetProperty("tunnels").EnumerateArray())
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
catch
{
    var c = Environment.GetEnvironmentVariable("SWML_PROXY_URL_BASE") ?? "";
    Console.WriteLine(c != "" ? $"Using SWML_PROXY_URL_BASE from .env: {c}" : "No ngrok tunnel detected");
}

var agent = new AgentBase(new AgentOptions { Name = "joke-agent" });

agent.AddLanguage("English", "en-US", "rime.spore");

agent.PromptAddSection(
    "Role",
    "You are a friendly assistant named Buddy who loves telling dad jokes. "
    + "Keep your responses short since this is a phone call."
);

var jokes = new[]
{
    "Why don't scientists trust atoms? Because they make up everything!",
    "What do you call a fake noodle? An impasta!",
    "Why did the scarecrow win an award? He was outstanding in his field!",
};

agent.DefineTool(
    name: "tell_joke",
    description: "Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.",
    parameters: new Dictionary<string, object>(),
    handler: (args, rawData) =>
    {
        var joke = jokes[Random.Shared.Next(jokes.Length)];
        return new FunctionResult($"Here's a dad joke: {joke}");
    }
);

agent.SetPostPrompt("Summarize this conversation in 2-3 sentences.");

agent.OnSummary((summary, rawData, headers) =>
{
    Directory.CreateDirectory("calls");
    var callId = rawData?.GetValueOrDefault("call_id")?.ToString() ?? DateTime.Now.ToString("yyyyMMdd_HHmmss");
    File.WriteAllText($"calls/{callId}.json", JsonSerializer.Serialize(rawData, new JsonSerializerOptions { WriteIndented = true }));
    Console.WriteLine($"Call summary saved: calls/{callId}.json");
});

agent.Run();
