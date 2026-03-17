// Agent with a hardcoded joke function.
package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/signalwire/signalwire-agents-go/pkg/agent"
	"github.com/signalwire/signalwire-agents-go/pkg/swaig"
)

var jokes = []string{
	"Why do programmers prefer dark mode? Because light attracts bugs.",
	"I told my wife she was drawing her eyebrows too high. She looked surprised.",
	"What do you call a fake noodle? An impasta.",
	"Why don't scientists trust atoms? Because they make up everything.",
	"I'm reading a book about anti-gravity. It's impossible to put down.",
	"What did the ocean say to the beach? Nothing, it just waved.",
	"Why did the scarecrow win an award? He was outstanding in his field.",
	"I used to hate facial hair, but then it grew on me.",
}

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

func main() {
	loadEnv()
	checkNgrok()

	a := agent.NewAgentBase(
		agent.WithName("joke-agent"),
		agent.WithRoute("/"),
	)

	// Voice configuration with fillers
	a.AddLanguage(map[string]any{
		"name":             "English",
		"code":             "en-US",
		"voice":            "rime.spore",
		"speech_fillers":   []string{"Um", "Well"},
		"function_fillers": []string{"Let me think of a good one..."},
	})

	// Prompt sections
	a.PromptAddSection("Role",
		"You are a friendly assistant named Buddy. "+
			"You love telling jokes and making people laugh. "+
			"Keep your responses short since this is a phone call.",
		nil,
	)

	a.PromptAddSection("Guidelines",
		"Follow these guidelines:",
		[]string{
			"When someone asks for a joke, use the tell_joke function",
			"After telling a joke, pause for a reaction before offering another",
			"Be enthusiastic and have fun with it",
		},
	)

	// Register the joke function
	a.DefineTool(agent.ToolDefinition{
		Name:        "tell_joke",
		Description: "Tell the caller a funny joke. Use this whenever someone asks for a joke or humor.",
		Handler: func(args map[string]any, rawData map[string]any) *swaig.FunctionResult {
			joke := jokes[rand.Intn(len(jokes))]
			return swaig.NewFunctionResult("Here's a joke: " + joke)
		},
	})

	// Post-prompt: summarize every call
	a.SetPostPrompt(
		"Summarize this conversation in 2-3 sentences. " +
			"Note which jokes were told and how the caller reacted.",
	)

	// Save call summaries
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

	fmt.Println("Starting joke-agent on :3000/ ...")
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
