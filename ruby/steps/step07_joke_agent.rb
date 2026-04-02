#!/usr/bin/env ruby
# frozen_string_literal: true

# Agent that tells fresh dad jokes from API Ninjas.

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'time'
require 'dotenv/load'

# Auto-detect ngrok tunnel and set SWML_PROXY_URL_BASE.
def check_ngrok
  uri = URI('http://127.0.0.1:4040/api/tunnels')
  resp = Net::HTTP.get_response(uri)
  tunnels = JSON.parse(resp.body).fetch('tunnels', [])
  tunnels.each do |t|
    next unless t['proto'] == 'https'

    url = t['public_url']
    ENV['SWML_PROXY_URL_BASE'] = url
    puts "ngrok detected: #{url}"
    user = ENV['SWML_BASIC_AUTH_USER'].to_s
    pw = ENV['SWML_BASIC_AUTH_PASSWORD'].to_s
    unless user.empty? || pw.empty?
      ngrok_uri = URI.parse(url)
      puts "\n  SignalWire SWML URL (paste into dashboard):\n  #{ngrok_uri.scheme}://#{user}:#{pw}@#{ngrok_uri.host}/\n"
      puts "  ⚠ Dev only — do not log credentials in production\n"
    end
    return url
  end
rescue StandardError
  nil
ensure
  current = ENV['SWML_PROXY_URL_BASE'].to_s
  if current.empty?
    puts 'No ngrok tunnel detected and SWML_PROXY_URL_BASE not set'
  elsif ENV['SWML_PROXY_URL_BASE'] != current
    puts "Using SWML_PROXY_URL_BASE from .env: #{current}"
  end
end

check_ngrok

require 'signalwire'

agent = SignalWireAgents::AgentBase.new(name: 'joke-agent', route: '/')

agent.add_language(
  'name'  => 'English',
  'code'  => 'en-US',
  'voice' => 'rime.spore',
  'speech_fillers'   => ['Um', 'Well'],
  'function_fillers' => ['Let me think of a good one...']
)

agent.prompt_add_section(
  'Role',
  'You are a friendly assistant named Buddy. ' \
  'You love telling jokes and making people laugh. ' \
  'Keep your responses short since this is a phone call.'
)

agent.prompt_add_section(
  'Guidelines',
  'Follow these guidelines:',
  bullets: [
    'When someone asks for a joke, use the tell_joke function',
    'After telling a joke, pause for a reaction before offering another',
    'Be enthusiastic and have fun with it'
  ]
)

agent.define_tool(
  name:        'tell_joke',
  description: 'Tell the caller a funny dad joke. Use this whenever someone asks for a joke, humor, or to be entertained.',
  parameters:  {}
) do |_args, _raw_data|
  api_key = ENV.fetch('API_NINJAS_KEY', '')
  if api_key.empty?
    next SignalWireAgents::Swaig::FunctionResult.new(
      "Sorry, I can't access my joke book right now. My API key is missing."
    )
  end

  begin
    uri = URI('https://api.api-ninjas.com/v1/dadjokes')
    req = Net::HTTP::Get.new(uri)
    req['X-Api-Key'] = api_key

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    resp = http.request(req)
    jokes = JSON.parse(resp.body)

    if jokes.is_a?(Array) && !jokes.empty?
      SignalWireAgents::Swaig::FunctionResult.new("Here's a dad joke: #{jokes[0]['joke']}")
    else
      SignalWireAgents::Swaig::FunctionResult.new(
        "I tried to find a joke but came up empty. That's... kind of a joke itself?"
      )
    end
  rescue StandardError
    SignalWireAgents::Swaig::FunctionResult.new(
      'Sorry, my joke service is taking a nap. Ask me again in a moment!'
    )
  end
end

# Post-prompt: summarize every call and save to calls/ folder
agent.set_post_prompt(
  'Summarize this conversation in 2-3 sentences. ' \
  'Note which jokes were told and how the caller reacted.'
)

agent.on_summary do |summary, raw_data|
  FileUtils.mkdir_p('calls')
  call_id = (raw_data || {}).fetch('call_id', Time.now.strftime('%Y%m%d_%H%M%S'))
  filepath = File.join('calls', "#{call_id}.json")
  File.write(filepath, JSON.pretty_generate(raw_data))
  puts "Call summary saved: #{filepath}"
end

agent.run
