// Polished agent with personality, hints, and tuned parameters.
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
)

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

func main() {
	loadEnv()
	checkNgrok()

	a := agent.NewAgentBase(
		agent.WithName("weather-joke-agent"),
		agent.WithRoute("/"),
	)

	// Voice configuration with fillers for natural conversation
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

	// AI parameters for better conversation flow
	a.SetParam("end_of_speech_timeout", 600)   // Wait 600ms of silence before responding
	a.SetParam("attention_timeout", 15000)      // Prompt after 15s of silence
	a.SetParam("attention_timeout_prompt",
		"Are you still there? I can help with weather, jokes, or math!")

	// Speech hints help the recognizer with tricky words
	a.AddHints([]string{"Buddy", "weather", "joke", "temperature", "forecast"})

	// Structured prompt with personality
	a.PromptAddSection("Personality",
		"You are Buddy, a cheerful and witty AI phone assistant. "+
			"You have a warm, upbeat personality and you genuinely enjoy "+
			"helping people. You're a bit of a dad joke enthusiast. "+
			"Think of yourself as that friendly neighbor who always "+
			"has a joke ready and knows what the weather is like.",
		nil,
	)

	a.PromptAddSection("Voice Style",
		"Since this is a phone conversation, follow these rules:",
		[]string{
			"Keep responses to 1-2 sentences when possible",
			"Use conversational language, not formal or robotic",
			"React to what the caller says before jumping to information",
			"If they laugh at a joke, acknowledge it warmly",
			"Use natural transitions between topics",
		},
	)

	a.PromptAddSection("Capabilities",
		"You can help with the following:",
		[]string{
			"Weather: current conditions for any city worldwide",
			"Jokes: endless supply of dad jokes, always fresh",
			"General chat: friendly conversation on any topic",
		},
	)

	// Dad joke function with per-function fillers
	a.DefineTool(agent.ToolDefinition{
		Name:        "tell_joke",
		Description: "Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.",
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

	// Weather lookup via DataMap
	registerWeatherDataMap(a)

	a.SetPostPrompt(
		"Summarize this conversation in 2-3 sentences. " +
			"Note what the caller asked about (weather, jokes, etc.) " +
			"and how the interaction went.",
	)

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

	fmt.Println("Starting weather-joke-agent on :3000/ ...")
	if err := a.Run(); err != nil {
		fmt.Printf("Agent error: %v\n", err)
		os.Exit(1)
	}
}

// loadEnv reads a .env file if present and sets environment variables.
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
