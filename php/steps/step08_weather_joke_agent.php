#!/usr/bin/env php
<?php
/**Agent with dad jokes (custom function) and weather (DataMap).*/

require __DIR__ . '/../../sdks/signalwire-php/vendor/autoload.php';

use SignalWire\Agent\AgentBase;
use SignalWire\DataMap\DataMap;
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

$agent = new AgentBase(name: 'weather-joke-agent', route: '/');

$agent->addLanguage(name: 'English', code: 'en-US', voice: 'rime.spore');

$agent->promptAddSection(
    'Role',
    'You are a friendly assistant named Buddy who can tell jokes and report the weather. '
    . 'Keep your responses short since this is a phone call.'
);

// Dad jokes via custom function
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

// Weather via DataMap (runs on SignalWire, not our server)
$weatherKey = getenv('WEATHER_API_KEY') ?: '';

$weather = (new DataMap('get_weather'))
    ->description('Get the current weather for a city. Use this when the caller asks about weather, temperature, or conditions.')
    ->parameter('city', 'string', 'The city to get weather for', required: true)
    ->webhook('GET', "https://api.weatherapi.com/v1/current.json?key={$weatherKey}&q=\${enc:args.city}")
    ->output(new FunctionResult(
        'Weather in ${args.city}: ${response.current.condition.text}, '
        . '${response.current.temp_f} degrees Fahrenheit, '
        . 'humidity ${response.current.humidity} percent. '
        . 'Feels like ${response.current.feelslike_f} degrees.'
    ))
    ->fallbackOutput(new FunctionResult(
        "Sorry, I couldn't get the weather for \${args.city}. Please check the city name and try again."
    ));

$agent->registerSwaigFunction($weather->toSwaigFunction());

$agent->setPostPrompt('Summarize this conversation in 2-3 sentences.');

$agent->onSummary(function ($summary, $rawData) {
    @mkdir('calls', 0755, true);
    $callId = $rawData['call_id'] ?? date('Ymd_His');
    file_put_contents("calls/$callId.json", json_encode($rawData, JSON_PRETTY_PRINT));
    echo "Call summary saved: calls/$callId.json\n";
});

$agent->run();
