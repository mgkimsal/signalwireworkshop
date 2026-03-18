#!/usr/bin/env ruby
# frozen_string_literal: true

# Agent with a hardcoded joke function.

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

require 'signalwire_agents'

JOKES = [
  'Why do programmers prefer dark mode? Because light attracts bugs.',
  'I told my wife she was drawing her eyebrows too high. She looked surprised.',
  'What do you call a fake noodle? An impasta.',
  "Why don't scientists trust atoms? Because they make up everything.",
  "I'm reading a book about anti-gravity. It's impossible to put down.",
  'What did the ocean say to the beach? Nothing, it just waved.',
  'Why did the scarecrow win an award? He was outstanding in his field.',
  'I used to hate facial hair, but then it grew on me.'
].freeze

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

# Register the joke function
agent.define_tool(
  name:        'tell_joke',
  description: 'Tell the caller a funny joke. Use this whenever someone asks for a joke or humor.',
  parameters:  {}
) do |_args, _raw_data|
  joke = JOKES.sample
  SignalWireAgents::Swaig::FunctionResult.new("Here's a joke: #{joke}")
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
