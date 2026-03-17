// Agent that tells fresh dad jokes from API Ninjas.

#include <signalwire/agent/agent_base.hpp>
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

    agent::AgentBase agent("joke-agent");

    agent.add_language({"English", "en-US", "rime.spore"});

    agent.prompt_add_section(
        "Role",
        "You are a friendly assistant named Buddy. "
        "You love telling jokes and making people laugh. "
        "Keep your responses short since this is a phone call."
    );

    agent.prompt_add_section("Guidelines",
        "Follow these guidelines:", {
            "When someone asks for a joke, use the tell_joke function",
            "After telling a joke, pause for a reaction before offering another",
            "Be enthusiastic and have fun with it",
        }
    );

    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny dad joke. Use this whenever someone "
        "asks for a joke, humor, or to be entertained.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;

            auto* api_key = std::getenv("API_NINJAS_KEY");
            if (!api_key || !api_key[0]) {
                return swaig::FunctionResult(
                    "Sorry, I can't access my joke book right now. "
                    "My API key is missing.");
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
                        "I tried to find a joke but came up empty. "
                        "That's... kind of a joke itself?");
                }
            } catch (...) {}

            return swaig::FunctionResult(
                "Sorry, my joke service is taking a nap. "
                "Ask me again in a moment!");
        }
    );

    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Note which jokes were told and how the caller reacted."
    );

    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        std::ofstream("calls/" + call_id + ".json") << raw_data.dump(2);
        std::cout << "Call summary saved: calls/" << call_id << ".json\n";
    });

    std::cout << "Starting joke-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
