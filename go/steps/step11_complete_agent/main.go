// Complete Workshop Agent
//
// A polished AI phone assistant with four capabilities:
//   - Dad jokes via API Ninjas (custom DefineTool)
//   - Weather via WeatherAPI (serverless DataMap)
//   - Date/time via built-in skill
//   - Math via built-in skill
//
// Run: go run main.go
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"github.com/signalwire/signalwire-agents-go/pkg/agent"
	"github.com/signalwire/signalwire-agents-go/pkg/datamap"
	"github.com/signalwire/signalwire-agents-go/pkg/swaig"
	_ "github.com/signalwire/signalwire-agents-go/pkg/skills/builtin"
)

// ---------------------------------------------------------------------------
// ngrok auto-detection
// ---------------------------------------------------------------------------

// checkNgrok auto-detects an ngrok tunnel and sets SWML_PROXY_URL_BASE.
func checkNgrok() string {
	type tunnel struct {
		Proto     string `json:"proto"`
		PublicURL string `json:"public_url"`
	}
	type apiResp struct {
		Tunnels []tunnel `json:"tunnels"`
	}

	client := &http.Client{Timeout: time.Second}
	resp, err := client.Get("http://127.0.0.1:4040/api/tunnels")
	if err == nil {
		defer resp.Body.Close()
		var data apiResp
		if json.NewDecoder(resp.Body).Decode(&data) == nil {
			for _, t := range data.Tunnels {
				if t.Proto == "https" {
					os.Setenv("SWML_PROXY_URL_BASE", t.PublicURL)
					fmt.Println("ngrok detected:", t.PublicURL)
					user := os.Getenv("SWML_BASIC_AUTH_USER")
					pw := os.Getenv("SWML_BASIC_AUTH_PASSWORD")
					if user != "" && pw != "" {
						if parsed, err := url.Parse(t.PublicURL); err == nil {
							fmt.Printf("\n  SignalWire SWML URL (paste into dashboard):\n  %s://%s:%s@%s/\n\n", parsed.Scheme, user, pw, parsed.Host)
							fmt.Println("  ⚠ Dev only — do not log credentials in production")
						}
					}
					return t.PublicURL
				}
			}
		}
	}

	current := os.Getenv("SWML_PROXY_URL_BASE")
	if current != "" {
		fmt.Println("Using SWML_PROXY_URL_BASE from .env:", current)
	} else {
		fmt.Println("No ngrok tunnel detected and SWML_PROXY_URL_BASE not set")
	}
	return current
}

// ---------------------------------------------------------------------------
// Dad jokes -- custom function calling API Ninjas
// ---------------------------------------------------------------------------

// fetchDadJoke calls the API Ninjas dad jokes endpoint.
func fetchDadJoke() *swaig.FunctionResult {
	apiKey := os.Getenv("API_NINJAS_KEY")
	if apiKey == "" {
		return swaig.NewFunctionResult("Sorry, my joke book is unavailable right now.")
	}

	req, err := http.NewRequest("GET", "https://api.api-ninjas.com/v1/dadjokes", nil)
	if err != nil {
		return swaig.NewFunctionResult("My joke service is taking a break. Try again in a moment!")
	}
	req.Header.Set("X-Api-Key", apiKey)

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return swaig.NewFunctionResult("My joke service is taking a break. Try again in a moment!")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil || resp.StatusCode != http.StatusOK {
		return swaig.NewFunctionResult("My joke service is taking a break. Try again in a moment!")
	}

	var jokes []struct {
		Joke string `json:"joke"`
	}
	if err := json.Unmarshal(body, &jokes); err != nil || len(jokes) == 0 {
		return swaig.NewFunctionResult("I couldn't find a joke this time. Try again!")
	}

	return swaig.NewFunctionResult("Here's a dad joke: " + jokes[0].Joke)
}

// ---------------------------------------------------------------------------
// Weather -- DataMap (runs on SignalWire, not our server)
// ---------------------------------------------------------------------------

// registerWeatherDataMap creates a DataMap for weather lookup.
func registerWeatherDataMap(a *agent.AgentBase) {
	apiKey := os.Getenv("WEATHER_API_KEY")

	weatherDM := datamap.New("get_weather").
		Description(
			"Get the current weather for a city. "+
				"Use this when the caller asks about weather, temperature, or conditions.",
		).
		Parameter("city", "string", "The city to get weather for", true, nil).
		Webhook(
			"GET",
			fmt.Sprintf("https://api.weatherapi.com/v1/current.json?key=%s&q=${enc:args.city}", apiKey),
			nil, "", false, nil,
		).
		Output(swaig.NewFunctionResult(
			"Weather in ${args.city}: ${response.current.condition.text}, "+
				"${response.current.temp_f} degrees Fahrenheit, "+
				"humidity ${response.current.humidity} percent. "+
				"Feels like ${response.current.feelslike_f} degrees.",
		)).
		FallbackOutput(swaig.NewFunctionResult(
			"Sorry, I couldn't get the weather for ${args.city}. "+
				"Please check the city name and try again.",
		))

	a.RegisterSwaigFunction(weatherDM.ToSwaigFunction())
}

// ---------------------------------------------------------------------------
// Voice and speech configuration
// ---------------------------------------------------------------------------

func configureVoice(a *agent.AgentBase) {
	a.AddLanguage(map[string]any{
		"name":  "English",
		"code":  "en-US",
		"voice": "rime.spore",
		"speech_fillers": []string{"Um", "Well", "So"},
		"function_fillers": []string{
			"Let me check on that for you...",
			"One moment while I look that up...",
			"Hang on just a sec...",
		},
	})

	a.AddHints([]string{
		"Buddy", "weather", "joke", "temperature",
		"forecast", "Fahrenheit", "Celsius",
	})
}

// ---------------------------------------------------------------------------
// AI parameters
// ---------------------------------------------------------------------------

func configureParams(a *agent.AgentBase) {
	a.SetParam("end_of_speech_timeout", 600)
	a.SetParam("attention_timeout", 15000)
	a.SetParam("attention_timeout_prompt",
		"Are you still there? I can help with weather, jokes, math, or just chat!")
}

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

func configurePrompts(a *agent.AgentBase) {
	a.PromptAddSection("Personality",
		"You are Buddy, a cheerful and witty AI phone assistant. "+
			"You have a warm, upbeat personality and you genuinely enjoy "+
			"helping people. You're a bit of a dad joke enthusiast. "+
			"Think of yourself as that friendly neighbor who always "+
			"has a joke ready and knows what the weather is like.",
		nil,
	)

	a.PromptAddSection("Voice Style",
		"Since this is a phone conversation:",
		[]string{
			"Keep responses to 1-2 sentences when possible",
			"Use conversational language, not formal or robotic",
			"React naturally to what the caller says",
			"Use smooth transitions between topics",
		},
	)

	a.PromptAddSection("Capabilities",
		"You can help with:",
		[]string{
			"Weather: current conditions for any city worldwide",
			"Jokes: endless supply of fresh dad jokes",
			"Date and time: current time in any timezone",
			"Math: calculations, percentages, unit conversions",
			"General chat: friendly conversation on any topic",
		},
	)

	a.PromptAddSection("Greeting",
		"When the call starts, introduce yourself as Buddy and "+
			"briefly mention what you can help with. Keep the greeting "+
			"to one or two sentences -- don't list every capability.",
		nil,
	)
}

// ---------------------------------------------------------------------------
// Dad joke tool registration
// ---------------------------------------------------------------------------

func registerJokeTool(a *agent.AgentBase) {
	a.DefineTool(agent.ToolDefinition{
		Name: "tell_joke",
		Description: "Tell the caller a funny dad joke. Use this whenever " +
			"someone asks for a joke, humor, or to be entertained.",
		Fillers: map[string][]string{
			"en-US": {
				"Let me think of a good one...",
				"Oh, I've got one for you...",
				"Here comes a good one...",
			},
		},
		Handler: func(args map[string]any, rawData map[string]any) *swaig.FunctionResult {
			return fetchDadJoke()
		},
	})
}

// ---------------------------------------------------------------------------
// Skills -- built-in, zero-code capabilities
// ---------------------------------------------------------------------------

func registerSkills(a *agent.AgentBase) {
	a.AddSkill("datetime", map[string]any{"default_timezone": "America/New_York"})
	a.AddSkill("math", nil)
}

// ---------------------------------------------------------------------------
// Post-prompt -- save call summaries for debugging
// ---------------------------------------------------------------------------

func configurePostPrompt(a *agent.AgentBase) {
	a.SetPostPrompt(
		"Summarize this conversation in 2-3 sentences. " +
			"Note what the caller asked about (weather, jokes, time, math, etc.) " +
			"and how the interaction went.",
	)

	// Save post-prompt data to calls/ folder for debugging.
	// View saved files at: https://postpromptviewer.signalwire.io/
	a.OnSummary(func(summary map[string]any, rawData map[string]any) {
		_ = os.MkdirAll("calls", 0o755)
		callID, _ := rawData["call_id"].(string)
		if callID == "" {
			callID = time.Now().Format("20060102_150405")
		}
		fp := filepath.Join("calls", callID+".json")
		data, _ := json.MarshalIndent(rawData, "", "  ")
		_ = os.WriteFile(fp, data, 0o644)
		fmt.Println("Call summary saved:", fp)
	})
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

func main() {
	loadEnv()
	checkNgrok()

	a := agent.NewAgentBase(
		agent.WithName("complete-agent"),
		agent.WithRoute("/"),
	)

	configureVoice(a)
	configureParams(a)
	configurePrompts(a)
	registerJokeTool(a)
	registerWeatherDataMap(a)
	registerSkills(a)
	configurePostPrompt(a)

	fmt.Println("Starting complete-agent on :3000/ ...")
	if err := a.Run(); err != nil {
		fmt.Printf("Agent error: %v\n", err)
		os.Exit(1)
	}
}

// ---------------------------------------------------------------------------
// Minimal .env loader
// ---------------------------------------------------------------------------

// loadEnv reads a .env file if present and sets environment variables.
// For production use consider github.com/joho/godotenv.
func loadEnv() {
	data, err := os.ReadFile(".env")
	if err != nil {
		return
	}
	for _, line := range splitLines(string(data)) {
		line = trimSpace(line)
		if line == "" || line[0] == '#' {
			continue
		}
		if k, v, ok := cutString(line, "="); ok {
			os.Setenv(trimSpace(k), trimSpace(v))
		}
	}
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

func trimSpace(s string) string {
	i, j := 0, len(s)
	for i < j && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r') {
		i++
	}
	for j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\r') {
		j--
	}
	return s[i:j]
}

func cutString(s, sep string) (string, string, bool) {
	for i := 0; i <= len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			return s[:i], s[i+len(sep):], true
		}
	}
	return s, "", false
}
