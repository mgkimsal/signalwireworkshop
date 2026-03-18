/**
 * Agent that tells fresh dad jokes from API Ninjas.
 * Run: npx tsx steps/step07_joke_agent.ts
 * Test: npx swaig-test steps/step07_joke_agent.ts --exec tell_joke
 */

import 'dotenv/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AgentBase, SwaigFunctionResult } from 'signalwire-agents';

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

export const agent = new AgentBase({ name: 'joke-agent' });

agent.addLanguage({
  name: 'English',
  code: 'en-US',
  voice: 'rime.spore',
  fillers: ['Um', 'Well'],
  functionFillers: ['Let me think of a good one...'],
});

agent.promptAddSection('Role', {
  body:
    'You are a friendly assistant named Buddy. ' +
    'You love telling jokes and making people laugh. ' +
    'Keep your responses short since this is a phone call.',
});

agent.promptAddSection('Guidelines', {
  body: 'Follow these guidelines:',
  bullets: [
    'When someone asks for a joke, use the tell_joke function',
    'After telling a joke, pause for a reaction before offering another',
    'Be enthusiastic and have fun with it',
  ],
});

agent.defineTool({
  name: 'tell_joke',
  description:
    'Tell the caller a funny dad joke. Use this whenever someone asks for a joke, humor, or to be entertained.',
  parameters: {},
  handler: async () => {
    const apiKey = process.env['API_NINJAS_KEY'] ?? '';
    if (!apiKey) {
      return new SwaigFunctionResult(
        "Sorry, I can't access my joke book right now. My API key is missing.",
      );
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
      return new SwaigFunctionResult(
        "I tried to find a joke but came up empty. That's... kind of a joke itself?",
      );
    } catch {
      return new SwaigFunctionResult(
        'Sorry, my joke service is taking a nap. Ask me again in a moment!',
      );
    }
  },
});

// Post-prompt: summarize every call and save to calls/ folder
agent.setPostPrompt(
  'Summarize this conversation in 2-3 sentences. ' +
    'Note which jokes were told and how the caller reacted.',
);

agent.onSummary = (_summary, rawData) => {
  fs.mkdirSync('calls', { recursive: true });
  const callId = rawData?.['call_id'] ?? new Date().toISOString().replace(/[:.]/g, '-');
  const filepath = path.join('calls', `${callId}.json`);
  fs.writeFileSync(filepath, JSON.stringify(rawData, null, 2));
  console.log(`Call summary saved: ${filepath}`);
};

agent.run();
