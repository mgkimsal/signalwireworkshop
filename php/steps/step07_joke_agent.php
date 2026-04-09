#!/usr/bin/env php
<?php
/**Agent that tells fresh dad jokes from API Ninjas.*/

require __DIR__ . '/../../sdks/signalwire-php/vendor/autoload.php';

use SignalWire\Agent\AgentBase;
use SignalWire\SWAIG\FunctionResult;

$envFile = __DIR__ . '/../.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#')) continue;
        putenv(trim($line));
        [$key, $val] = explode('=', $line, 2);
        $_ENV[trim($key)] = trim($val);
    }
}

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
                        echo "\n  SignalWire SWML URL:\n  {$parsed['scheme']}://$user:$pw@{$parsed['host']}/\n\n";
                    }
                    return $url;
                }
            }
        }
    } catch (\Exception $e) {}
    $current = getenv('SWML_PROXY_URL_BASE') ?: '';
    if ($current) echo "Using SWML_PROXY_URL_BASE from .env: $current\n";
    else echo "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    return $current;
}

checkNgrok();

$agent = new AgentBase(['name' => 'joke-agent', 'route' => '/']);

$agent->addLanguage(name: 'English', code: 'en-US', voice: 'rime.spore');

$agent->promptAddSection(
    'Role',
    'You are a friendly assistant named Buddy who loves telling dad jokes. '
    . 'Keep your responses short since this is a phone call.'
);

$agent->defineTool(
    name:        'tell_joke',
    description: 'Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.',
    parameters:  ['type' => 'object', 'properties' => []],
    handler: function (array $args, array $rawData): FunctionResult {
        $apiKey = getenv('API_NINJAS_KEY') ?: '';
        if (!$apiKey) {
            return new FunctionResult('Sorry, my joke book is unavailable right now.');
        }
        $ctx = stream_context_create(['http' => [
            'timeout' => 5,
            'header'  => "X-Api-Key: $apiKey\r\n",
        ]]);
        $json = @file_get_contents('https://api.api-ninjas.com/v1/dadjokes', false, $ctx);
        if ($json) {
            $jokes = json_decode($json, true);
            if (!empty($jokes)) {
                return new FunctionResult("Here's a dad joke: " . $jokes[0]['joke']);
            }
        }
        return new FunctionResult("My joke service is taking a break. Try again in a moment!");
    },
);

$agent->setPostPrompt('Summarize this conversation in 2-3 sentences.');

$agent->onSummary(function ($summary, $rawData) {
    @mkdir('calls', 0755, true);
    $callId = $rawData['call_id'] ?? date('Ymd_His');
    file_put_contents("calls/$callId.json", json_encode($rawData, JSON_PRETTY_PRINT));
    echo "Call summary saved: calls/$callId.json\n";
});

$agent->run();
