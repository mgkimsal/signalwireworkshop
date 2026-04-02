#!/usr/bin/env php
<?php
/**My first AI phone agent -- Hello World edition.*/

require __DIR__ . '/../../sdks/signalwire-php/vendor/autoload.php';

use SignalWire\Agent\AgentBase;
use SignalWire\SWAIG\FunctionResult;

// --- Load .env file ---
$envFile = __DIR__ . '/../.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#')) continue;
        putenv(trim($line));
        [$key, $val] = explode('=', $line, 2);
        $_ENV[trim($key)] = trim($val);
    }
}

// --- Auto-detect ngrok tunnel ---
function checkNgrok(): string {
    try {
        $ctx = stream_context_create(['http' => ['timeout' => 1]]);
        $json = @file_get_contents('http://127.0.0.1:4040/api/tunnels', false, $ctx);
        if ($json) {
            $data = json_decode($json, true);
            foreach (($data['tunnels'] ?? []) as $t) {
                if (($t['proto'] ?? '') === 'https') {
                    $url = $t['public_url'];
                    putenv("SWML_PROXY_URL_BASE=$url");
                    $_ENV['SWML_PROXY_URL_BASE'] = $url;
                    echo "ngrok detected: $url\n";
                    $user = getenv('SWML_BASIC_AUTH_USER') ?: '';
                    $pw   = getenv('SWML_BASIC_AUTH_PASSWORD') ?: '';
                    if ($user && $pw) {
                        $parsed = parse_url($url);
                        $full = "{$parsed['scheme']}://$user:$pw@{$parsed['host']}/";
                        echo "\n  SignalWire SWML URL (paste into dashboard):\n  $full\n\n";
                    }
                    return $url;
                }
            }
        }
    } catch (\Exception $e) {}
    $current = getenv('SWML_PROXY_URL_BASE') ?: '';
    if ($current) {
        echo "Using SWML_PROXY_URL_BASE from .env: $current\n";
    } else {
        echo "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    }
    return $current;
}

checkNgrok();

// --- Agent ---

$agent = new AgentBase(name: 'hello-agent', route: '/');

$agent->addLanguage(name: 'English', code: 'en-US', voice: 'rime.spore');

$agent->promptAddSection(
    'Role',
    'You are a friendly assistant named Buddy. '
    . 'You greet callers warmly, ask how their day is going, '
    . 'and have a brief pleasant conversation. '
    . 'Keep your responses short since this is a phone call.'
);

$agent->setPostPrompt(
    'Summarize this conversation in 2-3 sentences. '
    . 'Include what the caller wanted and how the conversation went.'
);

$agent->onSummary(function ($summary, $rawData) {
    @mkdir('calls', 0755, true);
    $callId = $rawData['call_id'] ?? date('Ymd_His');
    $path = "calls/$callId.json";
    file_put_contents($path, json_encode($rawData, JSON_PRETTY_PRINT));
    echo "Call summary saved: $path\n";
});

$agent->run();
