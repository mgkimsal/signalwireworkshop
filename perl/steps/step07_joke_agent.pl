#!/usr/bin/env perl
# Agent that tells fresh dad jokes from API Ninjas.

use strict;
use warnings;
use lib 'lib';
use JSON;
use File::Path qw(make_path);
use POSIX qw(strftime);
use HTTP::Tiny;
use SignalWire;
use SignalWire::Agent::AgentBase;
use SignalWire::SWAIG::FunctionResult;

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
    package JokeAgent;
    use Moo;
    extends 'SignalWire::Agent::AgentBase';

    sub BUILD {
        my ($self) = @_;

        $self->add_language(
            name             => 'English',
            code             => 'en-US',
            voice            => 'rime.spore',
            speech_fillers   => ['Um', 'Well'],
            function_fillers => ['Let me think of a good one...'],
        );

        $self->prompt_add_section(
            'Role',
            'You are a friendly assistant named Buddy. '
            . 'You love telling jokes and making people laugh. '
            . 'Keep your responses short since this is a phone call.',
        );

        $self->prompt_add_section(
            'Guidelines',
            'Follow these guidelines:',
            bullets => [
                'When someone asks for a joke, use the tell_joke function',
                'After telling a joke, pause for a reaction before offering another',
                'Be enthusiastic and have fun with it',
            ],
        );

        $self->define_tool(
            name        => 'tell_joke',
            description => 'Tell the caller a funny dad joke. Use this whenever someone asks for a joke, humor, or to be entertained.',
            parameters  => { type => 'object', properties => {} },
            handler     => sub {
                my ($args, $raw_data) = @_;
                my $api_key = $ENV{API_NINJAS_KEY} // '';
                if (!$api_key) {
                    return SignalWire::SWAIG::FunctionResult->new(
                        "Sorry, I can't access my joke book right now. My API key is missing."
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
                        return SignalWire::SWAIG::FunctionResult->new(
                            "Here's a dad joke: $jokes->[0]{joke}"
                        );
                    }
                    return SignalWire::SWAIG::FunctionResult->new(
                        "I tried to find a joke but came up empty. That's... kind of a joke itself?"
                    );
                }

                return SignalWire::SWAIG::FunctionResult->new(
                    "Sorry, my joke service is taking a nap. Ask me again in a moment!"
                );
            },
        );

        # Post-prompt: summarize every call and save to calls/ folder
        $self->set_post_prompt(
            'Summarize this conversation in 2-3 sentences. '
            . 'Note which jokes were told and how the caller reacted.',
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
}

# --- Start the Agent ---
my $agent = JokeAgent->new(
    name  => 'joke-agent',
    route => '/',
    host  => '0.0.0.0',
    port  => 3000,
);

print "Starting Joke Agent on http://0.0.0.0:3000/\n";
$agent->run;
