/**
 * My first AI phone agent -- Hello World edition.
 * Run: npx tsx steps/step04_hello_agent.ts
 * Test: npx swaig-test steps/step04_hello_agent.ts --dump-swml
 */

import 'dotenv/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AgentBase } from '@signalwire/sdk';

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

export const agent = new AgentBase({ name: 'hello-agent' });

// Set up the voice
agent.addLanguage({
  name: 'English',
  code: 'en-US',
  voice: 'rime.spore',
  fillers: ['Um', 'Well'],
});

// Tell the AI who it is
agent.promptAddSection('Role', {
  body:
    'You are a friendly assistant named Buddy. ' +
    'You greet callers warmly, ask how their day is going, ' +
    'and have a brief pleasant conversation. ' +
    'Keep your responses short since this is a phone call.',
});

// Post-prompt: summarize every call and save to calls/ folder
agent.setPostPrompt(
  'Summarize this conversation in 2-3 sentences. ' +
    'Include what the caller wanted and how the conversation went.',
);

// Save post-prompt data to calls/ folder for debugging
agent.onSummary = (_summary, rawData) => {
  fs.mkdirSync('calls', { recursive: true });
  const callId = rawData?.['call_id'] ?? new Date().toISOString().replace(/[:.]/g, '-');
  const filepath = path.join('calls', `${callId}.json`);
  fs.writeFileSync(filepath, JSON.stringify(rawData, null, 2));
  console.log(`Call summary saved: ${filepath}`);
};

agent.run();
