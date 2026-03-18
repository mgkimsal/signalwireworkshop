#!/usr/bin/env perl
#
# Complete Workshop Agent
# -----------------------
# A polished AI phone assistant with four capabilities:
#   - Dad jokes via API Ninjas (custom define_tool)
#   - Weather via WeatherAPI (serverless DataMap)
#   - Date/time via built-in skill
#   - Math via built-in skill
#
# Run:  perl complete_agent.pl
# Test: perl bin/swaig-test complete_agent.pl --dump-swml

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
    package CompleteAgent;
    use Moo;
    extends 'SignalWire::Agents::Agent::AgentBase';

    sub BUILD {
        my ($self) = @_;

        $self->_configure_voice();
        $self->_configure_params();
        $self->_configure_prompts();
        $self->_register_joke_function();
        $self->_register_weather_datamap();
        $self->_register_skills();
        $self->_configure_post_prompt();
    }

    # ------------------------------------------------------------------
    # Voice and speech
    # ------------------------------------------------------------------

    sub _configure_voice {
        my ($self) = @_;

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

        $self->add_hints(
            'Buddy', 'weather', 'joke', 'temperature',
            'forecast', 'Fahrenheit', 'Celsius',
        );
    }

    # ------------------------------------------------------------------
    # AI parameters
    # ------------------------------------------------------------------

    sub _configure_params {
        my ($self) = @_;

        $self->set_params({
            end_of_speech_timeout    => 600,
            attention_timeout        => 15000,
            attention_timeout_prompt =>
                'Are you still there? I can help with weather, '
                . 'jokes, math, or just chat!',
        });
    }

    # ------------------------------------------------------------------
    # Prompts
    # ------------------------------------------------------------------

    sub _configure_prompts {
        my ($self) = @_;

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
            'Since this is a phone conversation:',
            bullets => [
                'Keep responses to 1-2 sentences when possible',
                'Use conversational language, not formal or robotic',
                'React naturally to what the caller says',
                'Use smooth transitions between topics',
            ],
        );

        $self->prompt_add_section(
            'Capabilities',
            'You can help with:',
            bullets => [
                'Weather: current conditions for any city worldwide',
                'Jokes: endless supply of fresh dad jokes',
                'Date and time: current time in any timezone',
                'Math: calculations, percentages, unit conversions',
                'General chat: friendly conversation on any topic',
            ],
        );

        $self->prompt_add_section(
            'Greeting',
            'When the call starts, introduce yourself as Buddy and '
            . 'briefly mention what you can help with. Keep the greeting '
            . 'to one or two sentences -- do not list every capability.',
        );
    }

    # ------------------------------------------------------------------
    # Dad jokes -- custom function calling API Ninjas
    # ------------------------------------------------------------------

    sub _register_joke_function {
        my ($self) = @_;

        $self->define_tool(
            name        => 'tell_joke',
            description =>
                'Tell the caller a funny dad joke. Use this whenever '
                . 'someone asks for a joke, humor, or to be entertained.',
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

    # ------------------------------------------------------------------
    # Weather -- DataMap (runs on SignalWire, not our server)
    # ------------------------------------------------------------------

    sub _register_weather_datamap {
        my ($self) = @_;
        my $api_key = $ENV{WEATHER_API_KEY} // '';

        my $weather_dm = SignalWire::Agents::DataMap->new('get_weather')
            ->description(
                'Get the current weather for a city. Use this when '
                . 'the caller asks about weather, temperature, or conditions.'
            )
            ->parameter(
                'city', 'string',
                'The city to get weather for',
                required => 1,
            )
            ->webhook(
                'GET',
                "https://api.weatherapi.com/v1/current.json"
                . "?key=${api_key}&q=\${enc:args.city}"
            )
            ->output(
                SignalWire::Agents::SWAIG::FunctionResult->new(
                    'Weather in ${args.city}: '
                    . '${response.current.condition.text}, '
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

    # ------------------------------------------------------------------
    # Skills -- built-in, zero-code capabilities
    # ------------------------------------------------------------------

    sub _register_skills {
        my ($self) = @_;
        $self->add_skill('datetime', { default_timezone => 'America/New_York' });
        $self->add_skill('math');
    }

    # ------------------------------------------------------------------
    # Post-prompt -- save call summaries for debugging
    # ------------------------------------------------------------------

    sub _configure_post_prompt {
        my ($self) = @_;

        $self->set_post_prompt(
            'Summarize this conversation in 2-3 sentences. '
            . 'Note what the caller asked about (weather, jokes, time, math, etc.) '
            . 'and how the interaction went.',
        );

        # Save post-prompt data to calls/ folder for debugging.
        # View saved files at: https://postpromptviewer.signalwire.io/
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
}

# --- Start the Agent ---
my $agent = CompleteAgent->new(
    name  => 'complete-agent',
    route => '/',
    host  => '0.0.0.0',
    port  => 3000,
);

print "Starting Complete Agent on http://0.0.0.0:3000/\n";
$agent->run;
