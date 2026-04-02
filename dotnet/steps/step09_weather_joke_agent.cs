// Polished agent with personality, hints, and tuned parameters.

using SignalWire.Agent;
using SignalWire.DataMap;
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

var agent = new AgentBase(new AgentOptions { Name = "weather-joke-agent" });

agent.AddLanguage("English", "en-US", "rime.spore");

// AI parameters
agent.SetParams(new Dictionary<string, object>
{
    ["end_of_speech_timeout"] = 600,
    ["attention_timeout"] = 15000,
    ["attention_timeout_prompt"] = "Are you still there? I can help with weather, jokes, or math!",
});

agent.AddHints(new List<string> { "Buddy", "weather", "joke", "temperature", "forecast" });

// Personality
agent.PromptAddSection(
    "Personality",
    "You are Buddy, a cheerful and witty AI phone assistant. "
    + "You have a warm, upbeat personality and you genuinely enjoy "
    + "helping people. You're a bit of a dad joke enthusiast. "
    + "Think of yourself as that friendly neighbor who always "
    + "has a joke ready and knows what the weather is like."
);

agent.PromptAddSection("Voice Style", "Since this is a phone conversation, follow these rules:", new List<string>
{
    "Keep responses to 1-2 sentences when possible",
    "Use conversational language, not formal or robotic",
    "React to what the caller says before jumping to information",
    "If they laugh at a joke, acknowledge it warmly",
    "Use natural transitions between topics",
});

agent.PromptAddSection("Capabilities", "You can help with the following:", new List<string>
{
    "Weather: current conditions for any city worldwide",
    "Jokes: endless supply of dad jokes, always fresh",
    "General chat: friendly conversation on any topic",
});

// Dad jokes
var jokeClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };

agent.DefineTool(
    name: "tell_joke",
    description: "Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.",
    parameters: new Dictionary<string, object>(),
    handler: (args, rawData) =>
    {
        var apiKey = Environment.GetEnvironmentVariable("API_NINJAS_KEY") ?? "";
        if (apiKey == "") return new FunctionResult("Sorry, my joke book is unavailable right now.");
        try
        {
            var req = new HttpRequestMessage(HttpMethod.Get, "https://api.api-ninjas.com/v1/dadjokes");
            req.Headers.Add("X-Api-Key", apiKey);
            var resp = jokeClient.Send(req);
            var body = new StreamReader(resp.Content.ReadAsStream()).ReadToEnd();
            var jokes = JsonSerializer.Deserialize<JsonElement>(body);
            if (jokes.GetArrayLength() > 0)
                return new FunctionResult($"Here's a dad joke: {jokes[0].GetProperty("joke").GetString()}");
        }
        catch { }
        return new FunctionResult("My joke service is taking a break. Try again in a moment!");
    }
);

// Weather via DataMap
var weatherKey = Environment.GetEnvironmentVariable("WEATHER_API_KEY") ?? "";

var weather = new DataMap("get_weather")
    .Description("Get the current weather for a city. Use this when the caller asks about weather, temperature, or conditions.")
    .Parameter("city", "string", "The city to get weather for", required: true)
    .Webhook("GET", $"https://api.weatherapi.com/v1/current.json?key={weatherKey}&q=${{enc:args.city}}")
    .Output(new FunctionResult(
        "Weather in ${args.city}: ${response.current.condition.text}, "
        + "${response.current.temp_f} degrees Fahrenheit, "
        + "humidity ${response.current.humidity} percent. "
        + "Feels like ${response.current.feelslike_f} degrees."
    ))
    .FallbackOutput(new FunctionResult(
        "Sorry, I couldn't get the weather for ${args.city}. Please check the city name and try again."
    ));

agent.RegisterSwaigFunction(weather.ToSwaigFunction());

agent.SetPostPrompt(
    "Summarize this conversation in 2-3 sentences. "
    + "Note what the caller asked about (weather, jokes, etc.) "
    + "and how the interaction went."
);

agent.OnSummary((summary, rawData, headers) =>
{
    Directory.CreateDirectory("calls");
    var callId = rawData?.GetValueOrDefault("call_id")?.ToString() ?? DateTime.Now.ToString("yyyyMMdd_HHmmss");
    File.WriteAllText($"calls/{callId}.json", JsonSerializer.Serialize(rawData, new JsonSerializerOptions { WriteIndented = true }));
    Console.WriteLine($"Call summary saved: calls/{callId}.json");
});

agent.Run();
