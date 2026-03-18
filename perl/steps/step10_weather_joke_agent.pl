#!/usr/bin/env perl
# Polished agent with skills added -- weather, jokes, datetime, and math.

use strict;
use warnings;
use lib 'lib';
use JSON;
use File::Path qw(make_path);
use POSIX qw(strftime);
use HTTP::Tiny;
use SignalWire::Agents;
use SignalWire::Agents::Agent::AgentBase;
use SignalWire::Agents::DataMap;
use SignalWire::Agents::SWAIG::FunctionResult;

# --- Load .env file ---
if (-f '.env') {
    open my $fh, '<', '.env' or warn "Cannot open .env: $!";
    if ($fh) {
        while (my $line = <$fh>) {
            chomp $line;
            next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
            if ($line =~ /^\s*([^=]+?)\s*=\s*(.*?)\s*$/) {
                $ENV{$1} = $2;
            }
        }
        close $fh;
    }
}

# --- Auto-detect ngrok tunnel ---
sub check_ngrok {
    my $http = HTTP::Tiny->new(timeout => 1);
    eval {
        my $resp = $http->get('http://127.0.0.1:4040/api/tunnels');
        if ($resp->{success}) {
            my $data = decode_json($resp->{content});
            for my $t (@{ $data->{tunnels} || [] }) {
                if (($t->{proto} // '') eq 'https') {
                    my $url = $t->{public_url};
                    $ENV{SWML_PROXY_URL_BASE} = $url;
                    print "ngrok detected: $url\n";
                    my $user = $ENV{SWML_BASIC_AUTH_USER} // '';
                    my $pw   = $ENV{SWML_BASIC_AUTH_PASSWORD} // '';
                    if ($user && $pw) {
                        my ($scheme, $host) = $url =~ m{^(https?)://([^/]+)};
                        print "\n  SignalWire SWML URL (paste into dashboard):\n  $scheme://$user:$pw\@$host/\n\n";
                        print "  \x{26a0} Dev only \x{2014} do not log credentials in production\n\n";
                    }
                    return $url;
                }
            }
        }
    };
    my $current = $ENV{SWML_PROXY_URL_BASE} // '';
    if ($current) {
        print "Using SWML_PROXY_URL_BASE from .env: $current\n";
    } else {
        print "No ngrok tunnel detected and SWML_PROXY_URL_BASE not set\n";
    }
    return $current;
}

check_ngrok();

# --- Define the Agent ---
{
    package WeatherJokeAgent;
    use Moo;
    extends 'SignalWire::Agents::Agent::AgentBase';

    sub BUILD {
        my ($self) = @_;

        # Voice configuration with fillers for natural conversation
        $self->add_language(
            name             => 'English',
            code             => 'en-US',
            voice            => 'rime.spore',
            speech_fillers   => ['Um', 'Well', 'So'],
            function_fillers => [
                'Let me check on that for you...',
                'One moment while I look that up...',
                'Hang on just a sec...',
            ],
        );

        # AI parameters for better conversation flow
        $self->set_params({
            end_of_speech_timeout    => 600,      # Wait 600ms of silence before responding
            attention_timeout        => 15000,     # Prompt after 15s of silence
            attention_timeout_prompt => 'Are you still there? I can help with weather, jokes, or math!',
        });

        # Speech hints help the recognizer with tricky words
        $self->add_hints('Buddy', 'weather', 'joke', 'temperature', 'forecast');

        # Structured prompt with personality
        $self->prompt_add_section(
            'Personality',
            'You are Buddy, a cheerful and witty AI phone assistant. '
            . 'You have a warm, upbeat personality and you genuinely enjoy '
            . 'helping people. You are a bit of a dad joke enthusiast. '
            . 'Think of yourself as that friendly neighbor who always '
            . 'has a joke ready and knows what the weather is like.',
        );

        $self->prompt_add_section(
            'Voice Style',
            'Since this is a phone conversation, follow these rules:',
            bullets => [
                'Keep responses to 1-2 sentences when possible',
                'Use conversational language, not formal or robotic',
                'React to what the caller says before jumping to information',
                'If they laugh at a joke, acknowledge it warmly',
                'Use natural transitions between topics',
            ],
        );

        $self->prompt_add_section(
            'Capabilities',
            'You can help with the following:',
            bullets => [
                'Weather: current conditions for any city worldwide',
                'Jokes: endless supply of dad jokes, always fresh',
                'Date and time: current time in any timezone',
                'Math: calculations, percentages, conversions',
                'General chat: friendly conversation on any topic',
            ],
        );

        $self->_register_joke_function();
        $self->_register_weather_datamap();

        # Built-in skills -- one line each, zero configuration
        $self->add_skill('datetime', { default_timezone => 'America/New_York' });
        $self->add_skill('math');

        # Post-prompt: summarize every call and save to calls/ folder
        $self->set_post_prompt(
            'Summarize this conversation in 2-3 sentences. '
            . 'Note what the caller asked about (weather, jokes, time, math, etc.) '
            . 'and how the interaction went.',
        );

        $self->on_summary(sub {
            my ($summary, $raw_data) = @_;
            make_path('calls');
            my $call_id = ($raw_data && ref $raw_data eq 'HASH')
                ? ($raw_data->{call_id} // strftime('%Y%m%d_%H%M%S', localtime))
                : strftime('%Y%m%d_%H%M%S', localtime);
            my $filepath = "calls/$call_id.json";
            if (open my $fh, '>', $filepath) {
                print $fh JSON::encode_json($raw_data // {});
                close $fh;
                print "Call summary saved: $filepath\n";
            }
        });
    }

    sub _register_joke_function {
        my ($self) = @_;
        $self->define_tool(
            name        => 'tell_joke',
            description => 'Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.',
            parameters  => { type => 'object', properties => {} },
            fillers     => {
                'en-US' => [
                    'Let me think of a good one...',
                    'Oh, I have got one for you...',
                    'Here comes a good one...',
                ],
            },
            handler     => sub {
                my ($args, $raw_data) = @_;
                my $api_key = $ENV{API_NINJAS_KEY} // '';
                if (!$api_key) {
                    return SignalWire::Agents::SWAIG::FunctionResult->new(
                        'Sorry, my joke book is unavailable right now.'
                    );
                }

                my $http = HTTP::Tiny->new(timeout => 5);
                my $resp = $http->get(
                    'https://api.api-ninjas.com/v1/dadjokes',
                    { headers => { 'X-Api-Key' => $api_key } },
                );

                if ($resp->{success}) {
                    my $jokes = eval { decode_json($resp->{content}) };
                    if ($jokes && ref $jokes eq 'ARRAY' && @$jokes) {
                        return SignalWire::Agents::SWAIG::FunctionResult->new(
                            "Here's a dad joke: $jokes->[0]{joke}"
                        );
                    }
                    return SignalWire::Agents::SWAIG::FunctionResult->new(
                        "I couldn't find a joke this time. Try again!"
                    );
                }

                return SignalWire::Agents::SWAIG::FunctionResult->new(
                    'My joke service is taking a break. Try again in a moment!'
                );
            },
        );
    }

    sub _register_weather_datamap {
        my ($self) = @_;
        my $api_key = $ENV{WEATHER_API_KEY} // '';

        my $weather_dm = SignalWire::Agents::DataMap->new('get_weather')
            ->description(
                'Get the current weather for a city. '
                . 'Use this when the caller asks about weather, temperature, or conditions.'
            )
            ->parameter('city', 'string', 'The city to get weather for', required => 1)
            ->webhook(
                'GET',
                "https://api.weatherapi.com/v1/current.json?key=${api_key}&q=\${enc:args.city}"
            )
            ->output(
                SignalWire::Agents::SWAIG::FunctionResult->new(
                    'Weather in ${args.city}: ${response.current.condition.text}, '
                    . '${response.current.temp_f} degrees Fahrenheit, '
                    . 'humidity ${response.current.humidity} percent. '
                    . 'Feels like ${response.current.feelslike_f} degrees.'
                )
            )
            ->fallback_output(
                SignalWire::Agents::SWAIG::FunctionResult->new(
                    "Sorry, I couldn't get the weather for \${args.city}. "
                    . 'Please check the city name and try again.'
                )
            );

        $self->register_swaig_function($weather_dm->to_swaig_function);
    }
}

# --- Start the Agent ---
my $agent = WeatherJokeAgent->new(
    name  => 'weather-joke-agent',
    route => '/',
    host  => '0.0.0.0',
    port  => 3000,
);

print "Starting Weather Joke Agent on http://0.0.0.0:3000/\n";
$agent->run;
