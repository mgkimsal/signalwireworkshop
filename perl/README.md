# Build Your First AI Phone Agent -- Perl Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

## Prerequisites

- Perl 5.26+ (`perl -v`)
- cpanm (`cpanm --version` -- install via `curl -L https://cpanmin.us | perl - --sudo App::cpanminus` if needed)
- Completed [SignalWire Account Setup](../README.md#section-2-signalwire-account-setup)
- Completed [API Keys and ngrok Setup](../README.md#section-3-api-keys-and-ngrok-setup)

## Step Files

Each section has a corresponding step file in `steps/` with the complete working code for that checkpoint. If you get stuck, compare your code with the step file.

| Section | Step File |
|---------|-----------|
| Section 4: Hello World | `steps/step04_hello_agent.pl` |
| Section 6: Hardcoded Jokes | `steps/step06_joke_agent.pl` |
| Section 7: Live API Jokes | `steps/step07_joke_agent.pl` |
| Section 8: Weather DataMap | `steps/step08_weather_joke_agent.pl` |
| Section 9: Polish | `steps/step09_weather_joke_agent.pl` |
| Section 10: Skills | `steps/step10_weather_joke_agent.pl` |
| Section 11: Complete Agent | `steps/step11_complete_agent.pl` |

---

## Section 3: Project Setup (5 min)

Your SignalWire account and external API keys should already be set up from the [shared setup](../README.md). Now let's create the project.

### Step 1: Create Your Project Directory

Open a terminal and set up your project:

```bash
mkdir workshop-agent
cd workshop-agent
```

### Step 2: Create Your Environment File

Create a file called `.env` in your project directory with all your keys:

```
# SignalWire Credentials
SIGNALWIRE_PROJECT_ID=your-project-id-here
SIGNALWIRE_API_TOKEN=your-api-token-here
SIGNALWIRE_SPACE=your-space.signalwire.com

# Agent Authentication
SWML_BASIC_AUTH_USER=workshop
SWML_BASIC_AUTH_PASSWORD=pickASecurePassword123

# Weather API
WEATHER_API_KEY=your-weatherapi-key-here

# API Ninjas
API_NINJAS_KEY=your-api-ninjas-key-here
```

Replace every placeholder with your actual values.

> **Note:** You might notice there's no `SWML_PROXY_URL_BASE` here. Our agent code will auto-detect your ngrok tunnel at startup -- no need to configure it manually. If you're not using ngrok (e.g., deploying to a cloud server), you can add `SWML_PROXY_URL_BASE=https://your-server.example.com` to this file as a fallback.

> **Important:** The `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` are credentials that SignalWire will use to authenticate with your agent. Choose whatever you want, but remember them -- you'll enter them into the SignalWire dashboard later.

### Step 3: Create cpanfile

Create a `cpanfile` in your project directory:

```perl
requires 'Moo';
requires 'JSON';
requires 'Plack';
requires 'Plack::Request';
requires 'HTTP::Tiny';
requires 'Digest::SHA';
requires 'MIME::Base64';
requires 'IO::Socket::SSL';
requires 'POSIX';
```

Your project directory should now look like this:

```
workshop-agent/
├── .env
└── cpanfile
```

---

## Section 4: Install and Hello World (10 min)

Time to write some code. We'll start with the simplest possible agent -- just enough to prove everything is wired up correctly.

### Step 1: Install Dependencies

```bash
cpanm --installdeps .
```

If you prefer installing into a local directory (no root required):

```bash
cpanm -l local --installdeps .
```

If you install locally, you'll need to set `PERL5LIB` when running your agent:

```bash
export PERL5LIB=local/lib/perl5:lib
```

You also need the SignalWire Agents SDK itself. If you have it in a local directory, make sure `lib/` is in your `PERL5LIB` or use `use lib 'lib'` in your scripts (which all our examples do).

### Step 2: Write Your First Agent

Create a file called `hello_agent.pl`:

`hello_agent.pl`

```perl
#!/usr/bin/env perl
# My first AI phone agent -- Hello World edition.

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
```

Let's break down what's happening:

- The `.env` loader reads your environment file by parsing each `KEY=VALUE` line into `%ENV`. Perl doesn't have a built-in `dotenv`, so we read the file manually -- it's just a few lines.
- `check_ngrok()` queries ngrok's local API at `http://127.0.0.1:4040` using `HTTP::Tiny` to discover the tunnel URL. If ngrok is running, it automatically sets `SWML_PROXY_URL_BASE` -- the environment variable the SDK uses to generate correct webhook URLs. If ngrok isn't running yet (it isn't -- we'll set it up in Section 5), it prints a helpful message and moves on.
- The `HelloAgent` package uses `Moo` and `extends 'SignalWire::Agents::Agent::AgentBase'` -- the foundation class for every agent.
- Configuration happens in `BUILD`, which Moo calls after construction.
- `add_language()` takes named parameters: `name`, `code`, `voice`, and `speech_fillers`.
- `prompt_add_section()` gives the AI its instructions.
- `set_post_prompt()` tells the AI to generate a summary after every call. When the call ends, SignalWire sends the summary data to your agent's `/post_prompt` endpoint.
- `on_summary()` receives a callback that saves the full JSON payload to a `calls/` folder. Each file is named by call ID. You can upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize and debug your agent's conversations.
- `$agent->run` starts a Plack HTTP server on port 3000.

### Step 3: Test with swaig-test

Before we run the server, let's verify the agent's configuration is valid:

```bash
perl bin/swaig-test hello_agent.pl --dump-swml
```

You should see a JSON document -- this is the SWML (SignalWire Markup Language) that tells the SignalWire platform how to run your agent. Look for your prompt text in the output.

You can also test with curl. First, run the agent:

```bash
perl hello_agent.pl
```

You'll see output like:

```
No ngrok tunnel detected and SWML_PROXY_URL_BASE not set
Starting Hello Agent on http://0.0.0.0:3000/
```

The "No ngrok tunnel detected" message is expected -- we haven't set up ngrok yet. That's coming in Section 5.

In a **separate terminal** (keep the agent running), test with curl:

```bash
curl -s -u workshop:pickASecurePassword123 http://localhost:3000/ | perl -MJSON -e 'print JSON->new->pretty->encode(decode_json(join "", <>))'
```

Use whatever values you set for `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD` in your `.env` file.

You should see the same SWML JSON. Your agent is serving its configuration correctly.

> **Checkpoint:** You see SWML JSON output from both `swaig-test` and curl. The JSON contains your prompt text and voice settings. If not, double-check that your `.env` file exists and is in the right directory, and that your `PERL5LIB` includes the SDK's `lib` directory.

---

## Section 5: ngrok and Going Live (10 min)

Your agent is running locally, but SignalWire's cloud can't reach `localhost:3000`. We need ngrok to create a public tunnel. See the [shared setup](../README.md#step-3-ngrok-account-and-static-domain) if you haven't installed ngrok yet.

### Step 1: Restart Your Agent

Now that ngrok is running, restart your agent (Ctrl+C the old one, then run it again):

```bash
perl hello_agent.pl
```

This time you should see:

```
ngrok detected: https://your-domain.ngrok-free.app
Starting Hello Agent on http://0.0.0.0:3000/
```

The `check_ngrok()` function we wrote earlier just found your tunnel automatically. No need to manually configure `SWML_PROXY_URL_BASE` -- the agent discovers it on every startup.

### Step 2: Test Through the Tunnel

From another terminal:

```bash
curl -s -u workshop:pickASecurePassword123 https://your-domain.ngrok-free.app/ | perl -MJSON -e 'print JSON->new->pretty->encode(decode_json(join "", <>))'
```

You should get the same SWML JSON, but now it's coming through the public internet. Look at the `web_hook_url` values in the JSON -- they should reference your ngrok domain, confirming the auto-detection worked.

### Step 3: Connect Your Phone Number

Now the exciting part. Go back to the SignalWire Dashboard:

1. Go to **Phone Numbers**
2. Click on the number you purchased
3. Select **Edit Settings**
4. Click **Select Resource**, then  **+ add**
5. Create a new **Script**, we will be using a **SWML Script**
6. Under **Handle Calls Using**, select **External URL**
7. Enter your ngrok URL: `https://workshop:password123@your-domain.ngrok-free.app/`
8. Click **Save**

> **Don't forget the trailing slash** on the URL. Your agent is serving on `/`.

### Step 4: Call Your Agent

Pick up your phone and call the number you purchased. You should hear the agent greet you!

It can't do much yet -- just have a friendly chat -- but you're talking to an AI agent running on your laptop. That's pretty great for 45 minutes of work.

> **Checkpoint:** You can call your phone number and have a conversation with your agent. It greets you warmly and chats. If the call fails, check: Is ngrok running? Is your agent running? Is the URL in SignalWire correct (with trailing slash)? Check the ngrok web interface at `http://127.0.0.1:4040` to see if requests are reaching your agent.

---

## Section 6: Your First SWAIG Function (15 min)

Your agent can talk, but it can't *do* anything. Let's fix that by teaching it to tell jokes.

SWAIG (SignalWire AI Gateway) functions are tools that the AI can decide to call during a conversation. See [the full explanation](../README.md#what-are-swaig-functions) for details.

### Step 1: Create the Joke Agent

Create a new file called `joke_agent.pl`:

`joke_agent.pl`

```perl
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
```

Let's look at the new pieces:

- `SignalWire::Agents::SWAIG::FunctionResult->new("text")` is how you return data from a SWAIG function. The AI takes this text and weaves it into its response.
- `define_tool()` registers the function. The `description` is critical -- it tells the AI *when* to call this function.
- `parameters` defines what the AI should extract from the conversation. Our joke function doesn't need any input, so it's an empty object.
- `function_fillers` are phrases the agent says while your function executes, so there's no awkward silence.
- The handler is an anonymous `sub` that receives `($args, $raw_data)` and returns a `FunctionResult`.

### Step 2: Test the Function

Stop your previous agent (Ctrl+C) and test the new one:

```bash
perl bin/swaig-test joke_agent.pl --list-tools
```

You should see `tell_joke` listed. Now test executing it:

```bash
perl bin/swaig-test joke_agent.pl --exec tell_joke
```

You should see a joke from the list. Run it a few times -- you'll get different jokes.

### Step 3: Run and Call

```bash
perl joke_agent.pl
```

With ngrok still running, call your number and ask for a joke. Try phrases like:
- "Tell me a joke"
- "Make me laugh"
- "Got any jokes?"

The AI should recognize these as requests for humor and call your function.

> **Checkpoint:** When you call and ask for a joke, the agent tells you one from the hardcoded list. You can see function calls in your agent's terminal output. If the agent talks about jokes but doesn't actually tell one from the list, check that your `define_tool` description clearly instructs the AI to use the function.

---

## Section 7: Calling a Live API (15 min)

Hardcoded jokes get old fast. Let's replace them with fresh dad jokes from the API Ninjas Dad Jokes API. Every call will be a different joke.

### Step 1: Understanding the API

The API Ninjas Dad Jokes endpoint is simple:

- **URL:** `https://api.api-ninjas.com/v1/dadjokes`
- **Method:** GET
- **Auth:** `X-Api-Key` header with your API key
- **Response:** A JSON array with a `joke` field: `[{"joke": "..."}]`

You can test it right now in your terminal:

```bash
curl -s -H "X-Api-Key: YOUR_API_NINJAS_KEY" https://api.api-ninjas.com/v1/dadjokes
```

### Step 2: Update the Joke Agent

Edit `joke_agent.pl` -- we'll replace the hardcoded jokes with a live API call. Replace the entire file:

`joke_agent.pl`

```perl
#!/usr/bin/env perl
# Agent that tells fresh dad jokes from API Ninjas.

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

        $self->define_tool(
            name        => 'tell_joke',
            description => 'Tell the caller a funny dad joke. Use this whenever someone asks for a joke, humor, or to be entertained.',
            parameters  => { type => 'object', properties => {} },
            handler     => sub {
                my ($args, $raw_data) = @_;
                my $api_key = $ENV{API_NINJAS_KEY} // '';
                if (!$api_key) {
                    return SignalWire::Agents::SWAIG::FunctionResult->new(
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
                        return SignalWire::Agents::SWAIG::FunctionResult->new(
                            "Here's a dad joke: $jokes->[0]{joke}"
                        );
                    }
                    return SignalWire::Agents::SWAIG::FunctionResult->new(
                        "I tried to find a joke but came up empty. That's... kind of a joke itself?"
                    );
                }

                return SignalWire::Agents::SWAIG::FunctionResult->new(
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
```

What changed:

- Removed the `@JOKES` array
- The handler now calls the API Ninjas endpoint using `HTTP::Tiny`
- We read the API key from `$ENV{API_NINJAS_KEY}` (loaded from your `.env` file)
- There's error handling -- if the API is down or the key is wrong, the agent says something graceful instead of crashing
- JSON response parsing uses `eval { decode_json(...) }` for safe decoding

### Step 3: Test It

```bash
perl bin/swaig-test joke_agent.pl --exec tell_joke
```

Run it several times. Every joke should be different. If you see an error about the API key, make sure `API_NINJAS_KEY` is set in your `.env` file.

### Step 4: Call and Test

Restart your agent:

```bash
perl joke_agent.pl
```

Call your number and ask for jokes. Every joke is now fresh from the internet.

> **Checkpoint:** Every time you ask for a joke, you get a different one. Running `perl bin/swaig-test --exec tell_joke` multiple times confirms this. If you're getting the same joke every time, the API might be caching -- wait a moment and try again.

---

## Section 8: DataMap -- The Serverless Approach (15 min)

For the joke function, you wrote Perl code that runs on your server. That works great, but there's another way: **DataMap**.

DataMap lets you declare an API call and SignalWire executes it on their infrastructure -- your server never handles the request. See [the full explanation](../README.md#what-is-datamap) for details.

Think of it this way:

- **define_tool** = "When the AI needs weather, send a request to my server, I'll call the weather API and return the result"
- **DataMap** = "When the AI needs weather, here's the weather API URL and how to format the response -- you do it, SignalWire"

### Step 1: Create the Weather + Joke Agent

Let's create a new agent that has both jokes (via your custom function) and weather (via DataMap). Create `weather_joke_agent.pl`:

`weather_joke_agent.pl`

```perl
#!/usr/bin/env perl
# Agent with dad jokes (custom function) and weather (DataMap).

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

        $self->add_language(
            name             => 'English',
            code             => 'en-US',
            voice            => 'rime.spore',
            speech_fillers   => ['Um', 'Well'],
            function_fillers => [
                'Let me check on that...',
                'One moment...',
            ],
        );

        $self->prompt_add_section(
            'Role',
            'You are a friendly assistant named Buddy. '
            . 'You help people with weather information and tell great jokes. '
            . 'Keep your responses short since this is a phone call.',
        );

        $self->prompt_add_section(
            'Guidelines',
            'Follow these guidelines:',
            bullets => [
                'When someone asks about weather, use the get_weather function',
                'When someone asks for a joke, use the tell_joke function',
                'Be warm, friendly, and conversational',
            ],
        );

        $self->_register_joke_function();
        $self->_register_weather_datamap();

        # Post-prompt: summarize every call and save to calls/ folder
        $self->set_post_prompt(
            'Summarize this conversation in 2-3 sentences. '
            . 'Note what the caller asked about (weather, jokes, etc.) '
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
            fillers     => { 'en-US' => ['Let me think of a good one...'] },
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
```

Let's unpack the DataMap piece:

- `SignalWire::Agents::DataMap->new('get_weather')` -- creates a new DataMap function with that name
- `->description(...)` -- tells the AI when to use it (same as `define_tool`)
- `->parameter('city', 'string', ...)` -- the AI will extract the city from the caller's request
- `->webhook('GET', $url)` -- the HTTP request SignalWire will make. Notice `${enc:args.city}` -- that's the city parameter, URL-encoded, inserted right into the URL
- `->output(...)` -- a template for the response. `${response.current.temp_f}` pulls the temperature from the API's JSON response
- `->fallback_output(...)` -- what to say if the API call fails

The API key is baked into the URL at startup time (via Perl string interpolation). The city gets substituted at call time (via `${enc:args.city}`).

> **Perl tip:** In the webhook URL string, we use `\${enc:args.city}` -- the backslash prevents Perl from interpreting `${enc:args.city}` as a Perl variable. The same applies to `${args.city}` and `${response.*}` in the output templates -- use single-quoted strings to avoid interpolation issues.

### Step 2: Test It

```bash
perl bin/swaig-test weather_joke_agent.pl --list-tools
```

You should see both `tell_joke` and `get_weather`. Now look at how the DataMap appears in the SWML:

```bash
perl bin/swaig-test weather_joke_agent.pl --dump-swml
```

Find the `get_weather` function in the JSON. Notice it has a `data_map` section instead of a `web_hook_url` -- that tells SignalWire to execute the API call directly.

Test the joke function still works:

```bash
perl bin/swaig-test weather_joke_agent.pl --exec tell_joke
```

> **Note:** You can't test DataMap functions locally with `--exec` because they run on SignalWire's infrastructure, not your server. You'll test weather by calling your agent.

### Step 3: Call and Test

Stop any running agent and start the new one:

```bash
perl weather_joke_agent.pl
```

Call your number and try:
- "What's the weather in New York?"
- "How's the weather in London?"
- "Tell me a joke"
- "What's the temperature in Tokyo?"

You now have an agent with two capabilities, built two different ways.

> **Checkpoint:** Your agent answers weather questions with live data AND tells fresh dad jokes. The weather responses include temperature, conditions, and humidity. If weather isn't working, double-check your `WEATHER_API_KEY` in `.env` -- DataMap sends the key directly to WeatherAPI, so it must be correct.

---

## Section 9: Polish and Personality (10 min)

Your agent works, but it sounds a bit robotic. Let's give it a personality and tune the conversation flow. Same file, better experience.

### Step 1: Upgrade the Prompts

Edit `weather_joke_agent.pl`. Replace the entire file with this improved version -- we're keeping the same structure but enhancing the prompt sections and adding AI parameters:

`weather_joke_agent.pl`

```perl
#!/usr/bin/env perl
# Polished agent with personality, hints, and tuned parameters.

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
                'General chat: friendly conversation on any topic',
            ],
        );

        $self->_register_joke_function();
        $self->_register_weather_datamap();

        # Post-prompt
        $self->set_post_prompt(
            'Summarize this conversation in 2-3 sentences. '
            . 'Note what the caller asked about (weather, jokes, etc.) '
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
```

What we improved:

- **`set_params()`** -- `end_of_speech_timeout` of 600ms means the agent waits a natural beat before responding (not jumping in too fast). `attention_timeout` of 15 seconds prompts the caller if they go quiet.
- **`add_hints()`** -- helps the speech recognizer with words it might mishear. "Buddy" could sound like "body" without a hint.
- **Richer prompts** -- the "Personality" section gives the AI a character to play. The "Voice Style" section has specific rules for phone conversation. The "Capabilities" section tells the AI what tools it has.
- **More fillers** -- multiple options per function so the agent doesn't say the same thing every time.

### Step 2: Test and Call

```bash
perl bin/swaig-test weather_joke_agent.pl --dump-swml
```

Look at the SWML -- you'll see the `hints` array, the `params` section with your timeouts, and the richer prompt. Restart and call:

```bash
perl weather_joke_agent.pl
```

The difference should be noticeable: the agent sounds more natural, has more personality, and handles pauses in conversation better.

> **Checkpoint:** Same capabilities (weather + jokes) but the conversation feels smoother and more natural. The agent has personality, uses varied filler phrases, and handles silence gracefully. Compare the experience to Section 8 -- it should be noticeably better.

---

## Section 10: Skills -- The Easy Way (10 min)

You've now built a custom function (jokes) and a DataMap function (weather). There's a third way to add capabilities: **skills**.

Skills are pre-built capabilities that ship with the SDK. Adding one is a single line of code. See [the full explanation](../README.md#what-are-skills) for details.

### Step 1: Add DateTime and Math Skills

Edit `weather_joke_agent.pl`. Add two lines inside `BUILD`, after the `_register_weather_datamap()` call:

```perl
        $self->_register_joke_function();
        $self->_register_weather_datamap();

        # Built-in skills -- one line each, zero configuration
        $self->add_skill('datetime', { default_timezone => 'America/New_York' });
        $self->add_skill('math');
```

Also update the "Capabilities" prompt section to mention the new abilities:

```perl
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
```

That's it. Two lines of code just gave your agent the ability to tell time in any timezone and do math.

### Step 2: Compare the Approaches

Let's look at what it took to add each capability:

| Capability | Approach | Lines of Code | Your Server Handles It? |
|-----------|----------|---------------|------------------------|
| Dad Jokes | `define_tool` | ~30 lines | Yes |
| Weather | DataMap | ~15 lines | No (SignalWire) |
| DateTime | Skill | 1 line | No (built-in) |
| Math | Skill | 1 line | No (built-in) |

**When to use which:**

- **Skills** -- when one exists for what you need. Fastest path, zero maintenance
- **DataMap** -- when you need to call a REST API. No server code, SignalWire handles it
- **define_tool** -- when you need custom logic, database access, or complex processing

### Step 3: Test the New Skills

```bash
perl bin/swaig-test weather_joke_agent.pl --list-tools
```

You should see your original two functions plus the skill functions: `get_current_time`, `get_current_date`, and `calculate`.

```bash
perl bin/swaig-test weather_joke_agent.pl --exec get_current_time
perl bin/swaig-test weather_joke_agent.pl --exec calculate --expression "15/100 * 47.50"
```

### Step 4: Call and Test

Restart the agent and call:

```bash
perl weather_joke_agent.pl
```

Try asking:
- "What time is it?"
- "What time is it in Tokyo?"
- "What's 15% tip on a $47.50 bill?"
- "What's 144 divided by 12?"
- And of course: weather and jokes still work

> **Checkpoint:** Your agent now handles weather, jokes, time/date, and math. That's four capabilities, and two of them were a single line of code each. Verify all four work by calling and testing each one.

---

## Section 11: The Finished Agent (10 min)

Let's bring everything together into one clean, final version. This is the definitive `complete_agent.pl` -- combining all four capabilities with polished prompts and tuned parameters.

### The Complete Agent

Create `complete_agent.pl`:

`complete_agent.pl`

```perl
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
```

### What's Different From the Iterative Version?

Structurally, very little. This is the same agent you've been building, just organized into clean private methods:

- `_configure_voice()` -- voice, fillers, hints
- `_configure_params()` -- AI behavior tuning
- `_configure_prompts()` -- personality and instructions
- `_register_joke_function()` -- custom SWAIG function
- `_register_weather_datamap()` -- serverless DataMap
- `_register_skills()` -- built-in skills
- `_configure_post_prompt()` -- call summaries saved to `calls/`

This pattern (`_configure_*` and `_register_*` methods) is the standard way to organize larger agents in the SDK.

> **Debugging with Post-Prompt Viewer:** After each call, check your `calls/` folder -- you'll find a JSON file for every conversation. Upload these files to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize the full conversation flow, see what functions were called, and read the AI-generated summary. It's the fastest way to debug and improve your agent.

### Test Everything

```bash
# Verify configuration
perl bin/swaig-test complete_agent.pl --dump-swml

# List all tools
perl bin/swaig-test complete_agent.pl --list-tools

# Test individual functions
perl bin/swaig-test complete_agent.pl --exec tell_joke
perl bin/swaig-test complete_agent.pl --exec get_current_time
perl bin/swaig-test complete_agent.pl --exec calculate --expression "20 * 1.15"
```

### Go Live

```bash
perl complete_agent.pl
```

Call your number and run through all the capabilities:

1. "Hey, what time is it?" -- datetime skill
2. "What's the weather in Paris?" -- DataMap weather
3. "Tell me a joke!" -- API Ninjas dad jokes
4. "What's 18% tip on $86?" -- math skill
5. "Thanks Buddy, you're great!" -- personality shines

> **Checkpoint:** All four capabilities work end-to-end through a phone call. Your agent has personality, handles pauses naturally, and uses filler phrases while thinking. This is your complete, polished AI phone assistant. Congratulations -- you built this!

---

## Your Files

Here's what you created today:

```
workshop-agent/
├── .env                      # Your API keys and configuration
├── cpanfile                  # Perl dependencies
├── hello_agent.pl            # Section 4 -- minimal agent
├── joke_agent.pl             # Sections 6-7 -- jokes (hardcoded, then API)
├── weather_joke_agent.pl     # Sections 8-10 -- weather + jokes + skills
├── complete_agent.pl         # Section 11 -- the final polished version
└── calls/                    # Post-prompt data saved after each call
    ├── abc123-def456.json    # One JSON file per call
    └── ...
```

Upload files from `calls/` to [postpromptviewer.signalwire.io](https://postpromptviewer.signalwire.io/) to visualize your conversations.

---

## Quick Reference

### Common swaig-test Commands

```bash
perl bin/swaig-test your_agent.pl --dump-swml          # View full SWML configuration
perl bin/swaig-test your_agent.pl --list-tools         # List registered functions
perl bin/swaig-test your_agent.pl --exec func_name     # Execute a function
perl bin/swaig-test your_agent.pl --exec calc --expression "2+2"  # With arguments
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `SWML_BASIC_AUTH_USER` | Username for agent authentication |
| `SWML_BASIC_AUTH_PASSWORD` | Password for agent authentication |
| `SWML_PROXY_URL_BASE` | Auto-detected from ngrok; set manually only if not using ngrok |
| `WEATHER_API_KEY` | WeatherAPI.com API key |
| `API_NINJAS_KEY` | API Ninjas API key |

### Three Ways to Add Capabilities

```perl
# 1. Custom function (full control, runs on your server)
$self->define_tool(name => '...', description => '...', parameters => {...}, handler => sub { ... });

# 2. DataMap (serverless, runs on SignalWire)
my $dm = SignalWire::Agents::DataMap->new('name')->description('...')->parameter(...)->webhook(...)->output(...);
$self->register_swaig_function($dm->to_swaig_function);

# 3. Skill (pre-built, one line)
$self->add_skill('skill_name', { config => 'value' });
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| Agent won't start | Check `PERL5LIB` includes `lib` and dependencies are installed |
| Module not found | Run `cpanm --installdeps .` and check `use lib 'lib'` is in your script |
| Can't reach agent from internet | Is ngrok running? Check `http://127.0.0.1:4040` |
| SignalWire can't reach agent | Verify SWML URL has trailing slash, auth matches |
| Weather returns errors | Check `WEATHER_API_KEY` in `.env` |
| Jokes return errors | Check `API_NINJAS_KEY` in `.env` |
| Agent doesn't call functions | Check function `description` -- AI needs clear guidance |
| Speech recognition is wrong | Add `add_hints()` for commonly misheard words |
| Agent responds too fast | Increase `end_of_speech_timeout` in `set_params()` |
| Agent goes silent | Decrease `attention_timeout` in `set_params()` |
| String interpolation issues | Use `\$` or single quotes to prevent Perl from expanding `${args.*}` templates |
