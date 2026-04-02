/**
 * Agent with dad jokes (custom function) and weather (DataMap).
 * Run: npx tsx steps/step08_weather_joke_agent.ts
 * Test: npx swaig-test steps/step08_weather_joke_agent.ts --list-tools
 */

import 'dotenv/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AgentBase, FunctionResult, DataMap } from '@signalwire/sdk';

// Auto-detect ngrok tunnel and set SWML_PROXY_URL_BASE
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

export const agent = new AgentBase({ name: 'weather-joke-agent' });

agent.addLanguage({
  name: 'English',
  code: 'en-US',
  voice: 'rime.spore',
  fillers: ['Um', 'Well'],
  functionFillers: ['Let me check on that...', 'One moment...'],
});

agent.promptAddSection('Role', {
  body:
    'You are a friendly assistant named Buddy. ' +
    'You help people with weather information and tell great jokes. ' +
    'Keep your responses short since this is a phone call.',
});

agent.promptAddSection('Guidelines', {
  body: 'Follow these guidelines:',
  bullets: [
    'When someone asks about weather, use the get_weather function',
    'When someone asks for a joke, use the tell_joke function',
    'Be warm, friendly, and conversational',
  ],
});

// Register the dad joke function (runs on our server)
agent.defineTool({
  name: 'tell_joke',
  description:
    'Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.',
  parameters: {},
  handler: async () => {
    const apiKey = process.env['API_NINJAS_KEY'] ?? '';
    if (!apiKey) {
      return new FunctionResult('Sorry, my joke book is unavailable right now.');
    }

    try {
      const resp = await fetch('https://api.api-ninjas.com/v1/dadjokes', {
        headers: { 'X-Api-Key': apiKey },
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const jokes = (await resp.json()) as { joke: string }[];
      if (jokes.length) {
        return new FunctionResult(`Here's a dad joke: ${jokes[0].joke}`);
      }
      return new FunctionResult("I couldn't find a joke this time. Try again!");
    } catch {
      return new FunctionResult(
        'My joke service is taking a break. Try again in a moment!',
      );
    }
  },
  fillers: {
    'en-US': ['Let me think of a good one...'],
  },
});

// Register weather lookup via DataMap (runs on SignalWire's servers)
const weatherApiKey = process.env['WEATHER_API_KEY'] ?? '';

const weatherDm = new DataMap('get_weather')
  .description(
    'Get the current weather for a city. ' +
      'Use this when the caller asks about weather, temperature, or conditions.',
  )
  .parameter('city', 'string', 'The city to get weather for', { required: true })
  .webhook(
    'GET',
    `https://api.weatherapi.com/v1/current.json?key=${weatherApiKey}&q=\${enc:args.city}`,
  )
  .output(
    new FunctionResult(
      'Weather in ${args.city}: ${response.current.condition.text}, ' +
        '${response.current.temp_f} degrees Fahrenheit, ' +
        'humidity ${response.current.humidity} percent. ' +
        'Feels like ${response.current.feelslike_f} degrees.',
    ),
  )
  .fallbackOutput(
    new FunctionResult(
      "Sorry, I couldn't get the weather for ${args.city}. " +
        'Please check the city name and try again.',
    ),
  );

agent.registerSwaigFunction(weatherDm.toSwaigFunction());

// Post-prompt: summarize every call and save to calls/ folder
agent.setPostPrompt(
  'Summarize this conversation in 2-3 sentences. ' +
    'Note what the caller asked about (weather, jokes, etc.) ' +
    'and how the interaction went.',
);

agent.onSummary = (_summary, rawData) => {
  fs.mkdirSync('calls', { recursive: true });
  const callId = rawData?.['call_id'] ?? new Date().toISOString().replace(/[:.]/g, '-');
  const filepath = path.join('calls', `${callId}.json`);
  fs.writeFileSync(filepath, JSON.stringify(rawData, null, 2));
  console.log(`Call summary saved: ${filepath}`);
};

agent.run();
