/**
 * Agent with a hardcoded joke function.
 * Run: npx tsx steps/step06_joke_agent.ts
 * Test: npx swaig-test steps/step06_joke_agent.ts --list-tools
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

const JOKES = [
  'Why do programmers prefer dark mode? Because light attracts bugs.',
  'I told my wife she was drawing her eyebrows too high. She looked surprised.',
  'What do you call a fake noodle? An impasta.',
  "Why don't scientists trust atoms? Because they make up everything.",
  "I'm reading a book about anti-gravity. It's impossible to put down.",
  'What did the ocean say to the beach? Nothing, it just waved.',
  'Why did the scarecrow win an award? He was outstanding in his field.',
  'I used to hate facial hair, but then it grew on me.',
];

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

// Register the joke function
agent.defineTool({
  name: 'tell_joke',
  description: 'Tell the caller a funny joke. Use this whenever someone asks for a joke or humor.',
  parameters: {},
  handler: () => {
    const joke = JOKES[Math.floor(Math.random() * JOKES.length)];
    return new SwaigFunctionResult(`Here's a joke: ${joke}`);
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
