/**
 * Complete Workshop Agent
 *
 * A polished AI phone assistant with four capabilities:
 *   - Dad jokes via API Ninjas (custom defineTool)
 *   - Weather via WeatherAPI (serverless DataMap)
 *   - Date/time via built-in skill
 *   - Math via built-in skill
 *
 * Run: npx tsx steps/step11_complete_agent.ts
 * Test: npx swaig-test steps/step11_complete_agent.ts --dump-swml
 */

import 'dotenv/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AgentBase, SwaigFunctionResult, DataMap, DateTimeSkill, MathSkill } from 'signalwire-agents';

// ── ngrok auto-detection ────────────────────────────────────────────────

async function checkNgrok(): Promise<string> {
  try {
    const resp = await fetch('http://127.0.0.1:4040/api/tunnels', { signal: AbortSignal.timeout(1000) });
    const data = (await resp.json()) as { tunnels: { proto: string; public_url: string }[] };
    for (const t of data.tunnels ?? []) {
      if (t.proto === 'https') {
        process.env['SWML_PROXY_URL_BASE'] = t.public_url;
        console.log(`ngrok detected: ${t.public_url}`);
        const user = process.env['SWML_BASIC_AUTH_USER'] ?? '';
        const pw = process.env['SWML_BASIC_AUTH_PASSWORD'] ?? '';
        if (user && pw) {
          const u = new URL(t.public_url);
          console.log(`\n  SignalWire SWML URL (paste into dashboard):\n  ${u.protocol}//${user}:${pw}@${u.host}/\n`);
          console.log('  ⚠ Dev only — do not log credentials in production\n');
        }
        return t.public_url;
      }
    }
  } catch {
    // ngrok not running
  }
  const current = process.env['SWML_PROXY_URL_BASE'] ?? '';
  if (current) {
    console.log(`Using SWML_PROXY_URL_BASE from .env: ${current}`);
  } else {
    console.log('No ngrok tunnel detected and SWML_PROXY_URL_BASE not set');
  }
  return current;
}

await checkNgrok();

// ── Agent setup ─────────────────────────────────────────────────────────

export const agent = new AgentBase({ name: 'complete-agent' });

// ── Voice and speech ────────────────────────────────────────────────────

agent.addLanguage({
  name: 'English',
  code: 'en-US',
  voice: 'rime.spore',
  fillers: ['Um', 'Well', 'So'],
  functionFillers: [
    'Let me check on that for you...',
    'One moment while I look that up...',
    'Hang on just a sec...',
  ],
});

agent.addHints([
  'Buddy', 'weather', 'joke', 'temperature',
  'forecast', 'Fahrenheit', 'Celsius',
]);

// ── AI parameters ───────────────────────────────────────────────────────

agent.setParams({
  end_of_speech_timeout: 600,
  attention_timeout: 15000,
  attention_timeout_prompt:
    'Are you still there? I can help with weather, jokes, math, or just chat!',
});

// ── Prompts ─────────────────────────────────────────────────────────────

agent.promptAddSection('Personality', {
  body:
    'You are Buddy, a cheerful and witty AI phone assistant. ' +
    'You have a warm, upbeat personality and you genuinely enjoy ' +
    "helping people. You're a bit of a dad joke enthusiast. " +
    'Think of yourself as that friendly neighbor who always ' +
    'has a joke ready and knows what the weather is like.',
});

agent.promptAddSection('Voice Style', {
  body: 'Since this is a phone conversation:',
  bullets: [
    'Keep responses to 1-2 sentences when possible',
    'Use conversational language, not formal or robotic',
    'React naturally to what the caller says',
    'Use smooth transitions between topics',
  ],
});

agent.promptAddSection('Capabilities', {
  body: 'You can help with:',
  bullets: [
    'Weather: current conditions for any city worldwide',
    'Jokes: endless supply of fresh dad jokes',
    'Date and time: current time in any timezone',
    'Math: calculations, percentages, unit conversions',
    'General chat: friendly conversation on any topic',
  ],
});

agent.promptAddSection('Greeting', {
  body:
    'When the call starts, introduce yourself as Buddy and ' +
    'briefly mention what you can help with. Keep the greeting ' +
    "to one or two sentences -- don't list every capability.",
});

// ── Dad jokes -- custom function calling API Ninjas ─────────────────────

agent.defineTool({
  name: 'tell_joke',
  description:
    'Tell the caller a funny dad joke. Use this whenever ' +
    'someone asks for a joke, humor, or to be entertained.',
  parameters: {},
  handler: async () => {
    const apiKey = process.env['API_NINJAS_KEY'] ?? '';
    if (!apiKey) {
      return new SwaigFunctionResult('Sorry, my joke book is unavailable right now.');
    }

    try {
      const resp = await fetch('https://api.api-ninjas.com/v1/dadjokes', {
        headers: { 'X-Api-Key': apiKey },
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const jokes = (await resp.json()) as { joke: string }[];
      if (jokes.length) {
        return new SwaigFunctionResult(`Here's a dad joke: ${jokes[0].joke}`);
      }
      return new SwaigFunctionResult("I couldn't find a joke this time. Try again!");
    } catch {
      return new SwaigFunctionResult(
        'My joke service is taking a break. Try again in a moment!',
      );
    }
  },
  fillers: {
    'en-US': [
      'Let me think of a good one...',
      "Oh, I've got one for you...",
      'Here comes a good one...',
    ],
  },
});

// ── Weather -- DataMap (runs on SignalWire, not our server) ─────────────

const weatherApiKey = process.env['WEATHER_API_KEY'] ?? '';

const weatherDm = new DataMap('get_weather')
  .description(
    'Get the current weather for a city. Use this when ' +
      'the caller asks about weather, temperature, or conditions.',
  )
  .parameter('city', 'string', 'The city to get weather for', { required: true })
  .webhook(
    'GET',
    `https://api.weatherapi.com/v1/current.json?key=${weatherApiKey}&q=\${enc:args.city}`,
  )
  .output(
    new SwaigFunctionResult(
      'Weather in ${args.city}: ${response.current.condition.text}, ' +
        '${response.current.temp_f} degrees Fahrenheit, ' +
        'humidity ${response.current.humidity} percent. ' +
        'Feels like ${response.current.feelslike_f} degrees.',
    ),
  )
  .fallbackOutput(
    new SwaigFunctionResult(
      "Sorry, I couldn't get the weather for ${args.city}. " +
        'Please check the city name and try again.',
    ),
  );

agent.registerSwaigFunction(weatherDm.toSwaigFunction());

// ── Skills -- built-in, zero-code capabilities ──────────────────────────

await agent.addSkill(new DateTimeSkill());
await agent.addSkill(new MathSkill());

// ── Post-prompt -- save call summaries for debugging ────────────────────

agent.setPostPrompt(
  'Summarize this conversation in 2-3 sentences. ' +
    'Note what the caller asked about (weather, jokes, time, math, etc.) ' +
    'and how the interaction went.',
);

/**
 * Save post-prompt data to calls/ folder for debugging.
 * View saved files at: https://postpromptviewer.signalwire.io/
 */
agent.onSummary = (_summary, rawData) => {
  fs.mkdirSync('calls', { recursive: true });
  const callId = rawData?.['call_id'] ?? new Date().toISOString().replace(/[:.]/g, '-');
  const filepath = path.join('calls', `${callId}.json`);
  fs.writeFileSync(filepath, JSON.stringify(rawData, null, 2));
  console.log(`Call summary saved: ${filepath}`);
};

agent.run();
