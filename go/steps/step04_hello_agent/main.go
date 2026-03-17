// My first AI phone agent -- Hello World edition.
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/signalwire/signalwire-agents-go/pkg/agent"
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

	// Create the agent with functional options
	a := agent.NewAgentBase(
		agent.WithName("hello-agent"),
		agent.WithRoute("/"),
	)

	// Set up the voice
	a.AddLanguage(map[string]any{
		"name":  "English",
		"code":  "en-US",
		"voice": "rime.spore",
		"speech_fillers": []string{"Um", "Well"},
	})

	// Tell the AI who it is
	a.PromptAddSection("Role",
		"You are a friendly assistant named Buddy. "+
			"You greet callers warmly, ask how their day is going, "+
			"and have a brief pleasant conversation. "+
			"Keep your responses short since this is a phone call.",
		nil,
	)

	// Post-prompt: summarize every call
	a.SetPostPrompt(
		"Summarize this conversation in 2-3 sentences. " +
			"Include what the caller wanted and how the conversation went.",
	)

	// Save post-prompt data to calls/ folder for debugging
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

	// Run the agent (blocking)
	fmt.Println("Starting hello-agent on :3000/ ...")
	if err := a.Run(); err != nil {
		fmt.Printf("Agent error: %v\n", err)
		os.Exit(1)
	}
}

// loadEnv reads a .env file if present and sets environment variables.
// This is a minimal implementation -- for production use consider godotenv.
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
