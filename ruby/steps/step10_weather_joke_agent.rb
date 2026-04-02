#!/usr/bin/env ruby
# frozen_string_literal: true

# Polished agent with skills added -- weather, jokes, datetime, and math.

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

agent = SignalWireAgents::AgentBase.new(name: 'weather-joke-agent', route: '/')

# Voice configuration with fillers for natural conversation
agent.add_language(
  'name'  => 'English',
  'code'  => 'en-US',
  'voice' => 'rime.spore',
  'speech_fillers'   => ['Um', 'Well', 'So'],
  'function_fillers' => [
    'Let me check on that for you...',
    'One moment while I look that up...',
    'Hang on just a sec...'
  ]
)

# AI parameters for better conversation flow
agent.set_params(
  'end_of_speech_timeout'    => 600,
  'attention_timeout'        => 15_000,
  'attention_timeout_prompt' => 'Are you still there? I can help with weather, jokes, or math!'
)

# Speech hints help the recognizer with tricky words
agent.add_hints(%w[Buddy weather joke temperature forecast])

# Structured prompt with personality
agent.prompt_add_section(
  'Personality',
  'You are Buddy, a cheerful and witty AI phone assistant. ' \
  'You have a warm, upbeat personality and you genuinely enjoy ' \
  "helping people. You're a bit of a dad joke enthusiast. " \
  'Think of yourself as that friendly neighbor who always ' \
  'has a joke ready and knows what the weather is like.'
)

agent.prompt_add_section(
  'Voice Style',
  'Since this is a phone conversation, follow these rules:',
  bullets: [
    'Keep responses to 1-2 sentences when possible',
    'Use conversational language, not formal or robotic',
    'React to what the caller says before jumping to information',
    'If they laugh at a joke, acknowledge it warmly',
    'Use natural transitions between topics'
  ]
)

agent.prompt_add_section(
  'Capabilities',
  'You can help with the following:',
  bullets: [
    'Weather: current conditions for any city worldwide',
    'Jokes: endless supply of dad jokes, always fresh',
    'Date and time: current time in any timezone',
    'Math: calculations, percentages, conversions',
    'General chat: friendly conversation on any topic'
  ]
)

# ------------------------------------------------------------------
# Dad jokes -- custom function (runs on our server)
# ------------------------------------------------------------------

agent.define_tool(
  name:        'tell_joke',
  description: 'Tell the caller a funny dad joke. Use this whenever someone asks for a joke or humor.',
  parameters:  {},
  fillers:     {
    'en-US' => [
      'Let me think of a good one...',
      "Oh, I've got one for you...",
      'Here comes a good one...'
    ]
  }
) do |_args, _raw_data|
  api_key = ENV.fetch('API_NINJAS_KEY', '')
  if api_key.empty?
    next SignalWireAgents::Swaig::FunctionResult.new('Sorry, my joke book is unavailable right now.')
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
      SignalWireAgents::Swaig::FunctionResult.new("I couldn't find a joke this time. Try again!")
    end
  rescue StandardError
    SignalWireAgents::Swaig::FunctionResult.new('My joke service is taking a break. Try again in a moment!')
  end
end

# ------------------------------------------------------------------
# Weather -- DataMap (runs on SignalWire, not our server)
# ------------------------------------------------------------------

weather_api_key = ENV.fetch('WEATHER_API_KEY', '')

weather_dm = SignalWireAgents::DataMap.new('get_weather')
  .description(
    'Get the current weather for a city. ' \
    'Use this when the caller asks about weather, temperature, or conditions.'
  )
  .parameter('city', 'string', 'The city to get weather for', required: true)
  .webhook(
    'GET',
    "https://api.weatherapi.com/v1/current.json?key=#{weather_api_key}&q=${enc:args.city}"
  )
  .output(SignalWireAgents::Swaig::FunctionResult.new(
    'Weather in ${args.city}: ${response.current.condition.text}, ' \
    '${response.current.temp_f} degrees Fahrenheit, ' \
    'humidity ${response.current.humidity} percent. ' \
    'Feels like ${response.current.feelslike_f} degrees.'
  ))
  .fallback_output(SignalWireAgents::Swaig::FunctionResult.new(
    "Sorry, I couldn't get the weather for ${args.city}. " \
    'Please check the city name and try again.'
  ))

agent.register_swaig_function(weather_dm.to_swaig_function)

# ------------------------------------------------------------------
# Built-in skills -- one line each, zero configuration
# ------------------------------------------------------------------

agent.add_skill('datetime', 'default_timezone' => 'America/New_York')
agent.add_skill('math')

# ------------------------------------------------------------------
# Post-prompt
# ------------------------------------------------------------------

agent.set_post_prompt(
  'Summarize this conversation in 2-3 sentences. ' \
  'Note what the caller asked about (weather, jokes, time, math, etc.) ' \
  'and how the interaction went.'
)

agent.on_summary do |summary, raw_data|
  FileUtils.mkdir_p('calls')
  call_id = (raw_data || {}).fetch('call_id', Time.now.strftime('%Y%m%d_%H%M%S'))
  filepath = File.join('calls', "#{call_id}.json")
  File.write(filepath, JSON.pretty_generate(raw_data))
  puts "Call summary saved: #{filepath}"
end

agent.run
