// My first AI phone agent -- Hello World edition.

#include <signalwire/agent/agent_base.hpp>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <filesystem>

// cpp-httplib is vendored in the SDK
#include <httplib.h>
#include <nlohmann/json.hpp>

using namespace signalwire;
using json = nlohmann::json;

// Auto-detect ngrok tunnel and set SWML_PROXY_URL_BASE
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

    agent::AgentBase agent("hello-agent");

    // Set up the voice
    agent.add_language({"English", "en-US", "rime.spore"});

    // Tell the AI who it is
    agent.prompt_add_section(
        "Role",
        "You are a friendly assistant named Buddy. "
        "You greet callers warmly, ask how their day is going, "
        "and have a brief pleasant conversation. "
        "Keep your responses short since this is a phone call."
    );

    // Post-prompt: summarize every call
    agent.set_post_prompt(
        "Summarize this conversation in 2-3 sentences. "
        "Include what the caller wanted and how the conversation went."
    );

    // Save call summaries for debugging
    agent.on_summary([](const json& summary, const json& raw_data) {
        std::filesystem::create_directories("calls");
        auto call_id = raw_data.value("call_id",
            std::to_string(std::time(nullptr)));
        auto filepath = "calls/" + call_id + ".json";
        std::ofstream(filepath) << raw_data.dump(2);
        std::cout << "Call summary saved: " << filepath << "\n";
    });

    std::cout << "Starting hello-agent at http://0.0.0.0:3000/\n";
    agent.run();
}
