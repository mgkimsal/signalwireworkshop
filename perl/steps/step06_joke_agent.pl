#!/usr/bin/env perl
# Agent with a hardcoded joke function.

use strict;
use warnings;
use lib 'lib';
use JSON;
use File::Path qw(make_path);
use POSIX qw(strftime);
use HTTP::Tiny;
use SignalWire::Agents;
use SignalWire::Agents::Agent::AgentBase;
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

# --- Hardcoded joke list ---
my @JOKES = (
    'Why do programmers prefer dark mode? Because light attracts bugs.',
    'I told my wife she was drawing her eyebrows too high. She looked surprised.',
    'What do you call a fake noodle? An impasta.',
    "Why don't scientists trust atoms? Because they make up everything.",
    "I'm reading a book about anti-gravity. It's impossible to put down.",
    'What did the ocean say to the beach? Nothing, it just waved.',
    'Why did the scarecrow win an award? He was outstanding in his field.',
    'I used to hate facial hair, but then it grew on me.',
);

# --- Define the Agent ---
{
    package JokeAgent;
    use Moo;
    extends 'SignalWire::Agents::Agent::AgentBase';

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

        # Register the joke function
        $self->define_tool(
            name        => 'tell_joke',
            description => 'Tell the caller a funny joke. Use this whenever someone asks for a joke or humor.',
            parameters  => { type => 'object', properties => {} },
            handler     => sub {
                my ($args, $raw_data) = @_;
                my $joke = $JOKES[int(rand(scalar @JOKES))];
                return SignalWire::Agents::SWAIG::FunctionResult->new("Here's a joke: $joke");
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
