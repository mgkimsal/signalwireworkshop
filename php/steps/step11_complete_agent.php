#!/usr/bin/env php
<?php
/**
 * Complete Workshop Agent
 * -----------------------
 * A polished AI phone assistant with four capabilities:
 *   - Dad jokes via API Ninjas (custom defineTool)
 *   - Weather via WeatherAPI (serverless DataMap)
 *   - Date/time via built-in skill
 *   - Math via built-in skill
 *
 * Run: php complete_agent.php
 */

require __DIR__ . '/../../sdks/signalwire-php/vendor/autoload.php';

use SignalWire\Agent\AgentBase;
use SignalWire\DataMap\DataMap;
use SignalWire\SWAIG\FunctionResult;

// --- Load .env ---
$envFile = __DIR__ . '/../.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#')) continue;
        putenv(trim($line));
        [$key, $val] = explode('=', $line, 2);
        $_ENV[trim($key)] = trim($val);
    }
}

// --- Auto-detect ngrok ---
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

// --- Agent ---

$agent = new AgentBase(['name' => 'complete-agent', 'route' => '/']);

// Voice and speech
$agent->addLanguage(name: 'English', code: 'en-US', voice: 'rime.spore');
$agent->addHints('Buddy', 'weather', 'joke', 'temperature', 'forecast', 'Fahrenheit', 'Celsius');

// AI parameters
$agent->setParams([
    'end_of_speech_timeout'    => 600,
    'attention_timeout'        => 15000,
    'attention_timeout_prompt' => 'Are you still there? I can help with weather, jokes, math, or just chat!',
]);

// Prompts
$agent->promptAddSection(
    'Personality',
    'You are Buddy, a cheerful and witty AI phone assistant. '
    . 'You have a warm, upbeat personality and you genuinely enjoy '
    . 'helping people. You\'re a bit of a dad joke enthusiast. '
    . 'Think of yourself as that friendly neighbor who always '
    . 'has a joke ready and knows what the weather is like.'
);

$agent->promptAddSection('Voice Style', 'Since this is a phone conversation:', bullets: [
    'Keep responses to 1-2 sentences when possible',
    'Use conversational language, not formal or robotic',
    'React naturally to what the caller says',
    'Use smooth transitions between topics',
]);

$agent->promptAddSection('Capabilities', 'You can help with:', bullets: [
    'Weather: current conditions for any city worldwide',
    'Jokes: endless supply of fresh dad jokes',
    'Date and time: current time in any timezone',
    'Math: calculations, percentages, unit conversions',
    'General chat: friendly conversation on any topic',
]);

$agent->promptAddSection(
    'Greeting',
    'When the call starts, introduce yourself as Buddy and '
    . 'briefly mention what you can help with. Keep the greeting '
    . 'to one or two sentences -- don\'t list every capability.'
);

// Dad jokes -- custom function calling API Ninjas
$agent->defineTool(
    name:        'tell_joke',
    description: 'Tell the caller a funny dad joke. Use this whenever someone asks for a joke, humor, or to be entertained.',
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

// Weather -- DataMap (runs on SignalWire, not our server)
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

// Skills -- built-in, zero-code capabilities
$agent->addSkill('datetime', ['default_timezone' => 'America/New_York']);
$agent->addSkill('math');

// Post-prompt -- save call summaries for debugging
$agent->setPostPrompt(
    'Summarize this conversation in 2-3 sentences. '
    . 'Note what the caller asked about (weather, jokes, time, math, etc.) '
    . 'and how the interaction went.'
);

$agent->onSummary(function ($summary, $rawData) {
    @mkdir('calls', 0755, true);
    $callId = $rawData['call_id'] ?? date('Ymd_His');
    $path = "calls/$callId.json";
    file_put_contents($path, json_encode($rawData, JSON_PRETTY_PRINT));
    echo "Call summary saved: $path\n";
});

$agent->run();
