#!/usr/bin/env ruby
# frozen_string_literal: true

# My first AI phone agent -- Hello World edition.

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

agent = SignalWireAgents::AgentBase.new(name: 'hello-agent', route: '/')

# Set up the voice
agent.add_language(
  'name'  => 'English',
  'code'  => 'en-US',
  'voice' => 'rime.spore',
  'speech_fillers' => ['Um', 'Well']
)

# Tell the AI who it is
agent.prompt_add_section(
  'Role',
  'You are a friendly assistant named Buddy. ' \
  'You greet callers warmly, ask how their day is going, ' \
  'and have a brief pleasant conversation. ' \
  'Keep your responses short since this is a phone call.'
)

# Post-prompt: summarize every call and save to calls/ folder
agent.set_post_prompt(
  'Summarize this conversation in 2-3 sentences. ' \
  'Include what the caller wanted and how the conversation went.'
)

# Save post-prompt data to calls/ folder for debugging.
agent.on_summary do |summary, raw_data|
  FileUtils.mkdir_p('calls')
  call_id = (raw_data || {}).fetch('call_id', Time.now.strftime('%Y%m%d_%H%M%S'))
  filepath = File.join('calls', "#{call_id}.json")
  File.write(filepath, JSON.pretty_generate(raw_data))
  puts "Call summary saved: #{filepath}"
end

agent.run
