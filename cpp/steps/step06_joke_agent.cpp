// Agent with a hardcoded joke function.

#include <signalwire/agent/agent_base.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <random>
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
                    auto* auth_user = std::getenv("SWML_BASIC_AUTH_USER");
                    auto* auth_pass = std::getenv("SWML_BASIC_AUTH_PASSWORD");
                    if (auth_user && auth_user[0] && auth_pass && auth_pass[0]) {
                        auto scheme_end = url.find("://");
                        auto host_start = scheme_end + 3;
                        auto host_end = url.find('/', host_start);
                        auto scheme = url.substr(0, scheme_end);
                        auto host = url.substr(host_start, host_end == std::string::npos ? std::string::npos : host_end - host_start);
                        std::cout << "\n  SignalWire SWML URL (paste into dashboard):\n  "
                                  << scheme << "://" << auth_user << ":" << auth_pass << "@" << host << "/\n\n";
                        std::cout << "  ⚠ Dev only — do not log credentials in production\n\n";
                    }
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

// Hardcoded jokes for our first function
static const std::vector<std::string> JOKES = {
    "Why do programmers prefer dark mode? Because light attracts bugs.",
    "I told my wife she was drawing her eyebrows too high. She looked surprised.",
    "What do you call a fake noodle? An impasta.",
    "Why don't scientists trust atoms? Because they make up everything.",
    "I'm reading a book about anti-gravity. It's impossible to put down.",
    "What did the ocean say to the beach? Nothing, it just waved.",
    "Why did the scarecrow win an award? He was outstanding in his field.",
    "I used to hate facial hair, but then it grew on me.",
};

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

    // Register the joke function
    agent.define_tool(
        "tell_joke",
        "Tell the caller a funny joke. Use this whenever someone asks "
        "for a joke or humor.",
        {{"type", "object"}, {"properties", json::object()}},
        [](const json& args, const json& raw) -> swaig::FunctionResult {
            (void)args; (void)raw;
            static std::mt19937 rng{std::random_device{}()};
            std::uniform_int_distribution<size_t> dist(0, JOKES.size() - 1);
            return swaig::FunctionResult("Here's a joke: " + JOKES[dist(rng)]);
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
