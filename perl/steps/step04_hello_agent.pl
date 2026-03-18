#!/usr/bin/env perl
# My first AI phone agent -- Hello World edition.

use strict;
use warnings;
use lib "$ENV{HOME}/perl5/lib/perl5", 'lib';
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
    package HelloAgent;
    use Moo;
    extends 'SignalWire::Agents::Agent::AgentBase';

    sub BUILD {
        my ($self) = @_;

        # Set up the voice
        $self->add_language(
            name            => 'English',
            code            => 'en-US',
            voice           => 'rime.spore',
            speech_fillers  => ['Um', 'Well'],
        );

        # Tell the AI who it is
        $self->prompt_add_section(
            'Role',
            'You are a friendly assistant named Buddy. '
            . 'You greet callers warmly, ask how their day is going, '
            . 'and have a brief pleasant conversation. '
            . 'Keep your responses short since this is a phone call.',
        );

        # Post-prompt: summarize every call and save to calls/ folder
        $self->set_post_prompt(
            'Summarize this conversation in 2-3 sentences. '
            . 'Include what the caller wanted and how the conversation went.',
        );

        # Save post-prompt data to calls/ folder for debugging
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
my $agent = HelloAgent->new(
    name  => 'hello-agent',
    route => '/',
    host  => '0.0.0.0',
    port  => 3000,
);

print "Starting Hello Agent on http://0.0.0.0:3000/\n";
$agent->run;
