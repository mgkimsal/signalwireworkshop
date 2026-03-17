// Polished agent with skills added -- weather, jokes, datetime, and math.

#include <signalwire/agent/agent_base.hpp>
#include <signalwire/datamap/datamap.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <filesystem>

#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

std::string check_ngrok() {
    try {
        httplib::Client cli("127.0.0.1", 4040);
        cli.set_connection_timeout(1);
        if (auto res = cli.Get("/api/tunnels")) {
            auto tunnels = json::parse(res->body);
            for (auto& t : tunnels.value("tunnels", json::array())) {
                if (t.value("proto", "") == "https") {
                    auto url = t.value("public_url", "");
                    setenv("SWML_PROXY_URL_BASE", url.c_str(), 1);
                    std::cout << "ngrok detected: " << url << "\n";
                    return url;
                }
            }
        }
    } catch (...) {}

    if (auto* env = std::getenv("SWML_PROXY_URL_BASE"); env && env[0]) {
        std::cout << "Using SWML_PROXY_URL_BASE from env: " << env << "\n";
        return env;
    }
    std::cout << "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return "";
}

int main() {
    check_ngrok();

    agent::AgentBase agent("weather-joke-agent");

    // Voice configuration
    agent.add_language({"English", "en-US", "rime.spore"});

    // AI parameters for better conversation flow
    agent.set_params({
        {"end_of_speech_timeout", 600},    // Wait 600ms of silence before responding
        {"attention_timeout", 15000},      // Prompt after 15s of silence
        {"attention_timeout_prompt",
            "Are you still there? I can help with weather, jokes, or math!"},
    });

    // Speech hints help the recognizer with tricky words
    agent.add_hints({"Buddy", "weather", "joke", "temperature", "forecast"});

    // Structured prompt with personality
    agent.prompt_add_section(
        "Personality",
        "You are Buddy, a cheerful and witty AI phone assistant. "
        "You have a warm, upbeat personality and you genuinely enjoy "
        "helping people. You're a bit of a dad joke enthusiast. "
        "Think of yourself as that friendly neighbor who always "
        "has a joke ready and knows what the weather is like."
    );

    agent.prompt_add_section("Voice Style",
        "Since this is a phone conversation, follow these rules:", {
            "Keep responses to 1-2 sentences when possible",
            "Use conversational language, not formal or robotic",
            "React to what the caller says before jumping to information",
            "If they laugh at a joke, acknowledge it warmly",
            "Use natural transitions between topics",
        }
    );

    agent.prompt_add_section("Capabilities",
        "You can help with the following:", {
            "Weather: current conditions for any city worldwide",
            "Jokes: endless supply of dad jokes, always fresh",
            "Date and time: current time in any timezone",
            "Math: calculations, percentages, conversions",
            "General chat: friendly conversation on any topic",
        }
    );

    // ---- Dad jokes: custom function ----

    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny dad joke. Use this whenever someone "
        "asks for a joke or humor.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;

            auto* api_key = std::getenv("API_NINJAS_KEY");
            if (!api_key || !api_key[0]) {
                return swaig::FunctionResult(
                    "Sorry, my joke book is unavailable right now.");
            }

            try {
                httplib::Client cli("https://api.api-ninjas.com");
                cli.set_connection_timeout(5);
                httplib::Headers headers = {{"X-Api-Key", api_key}};

                if (auto res = cli.Get("/v1/dadjokes", headers)) {
                    auto jokes = json::parse(res->body);
                    if (jokes.is_array() && !jokes.empty()) {
                        return swaig::FunctionResult(
                            "Here's a dad joke: " +
                            jokes[0].value("joke", ""));
                    }
                    return swaig::FunctionResult(
                        "I couldn't find a joke this time. Try again!");
                }
            } catch (...) {}

            return swaig::FunctionResult(
                "My joke service is taking a break. "
                "Try again in a moment!");
        }
    );

    // ---- Weather: DataMap ----

    std::string weather_key;
    if (auto* env = std::getenv("WEATHER_API_KEY")) weather_key = env;

    auto weather_dm = datamap::DataMap("get_weather")
        .description(
            "Get the current weather for a city. "
            "Use this when the caller asks about weather, "
            "temperature, or conditions.")
        .parameter("city", "string",
            "The city to get weather for", true)
        .webhook("GET",
            "https://api.weatherapi.com/v1/current.json"
            "?key=" + weather_key + "&q=${enc:args.city}")
        .output(swaig::FunctionResult(
            "Weather in ${args.city}: "
            "${response.current.condition.text}, "
            "${response.current.temp_f} degrees Fahrenheit, "
            "humidity ${response.current.humidity} percent. "
            "Feels like ${response.current.feelslike_f} degrees."))
        .fallback_output(swaig::FunctionResult(
            "Sorry, I couldn't get the weather for ${args.city}. "
            "Please check the city name and try again."));

    agent.register_swaig_function(weather_dm.to_swaig_function());

    // Built-in skills -- one line each, zero configuration
    agent.add_skill("datetime", {{"default_timezone", "America/New_York"}});
    agent.add_skill("math");

    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Note what the caller asked about (weather, jokes, time, math, etc.) "
        "and how the interaction went."
    );

    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        std::ofstream("calls/" + call_id + ".json") << raw_data.dump(2);
        std::cout << "Call summary saved: calls/" << call_id << ".json\n";
    });

    std::cout << "Starting weather-joke-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
