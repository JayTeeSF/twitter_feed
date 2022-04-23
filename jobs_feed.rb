#!/usr/bin/env ruby

# run it for an hour: ./jobs_feed.rb > job_feed.json & sleep 3600 && kill -9 %1

# This script contains methods to add, remove, and retrieve rules from your stream.
# It will also connect to the stream endpoint and begin outputting data.
# Run as-is, the script gives you the option to replace existing rules with new ones and begin streaming data

require 'json'
require 'typhoeus'

# The code below sets the bearer token from your environment variables
# To set environment variables on Mac OS X, run the export command below from the terminal:
# export BEARER_TOKEN='YOUR-TOKEN'
#@bearer_token = ENV["BEARER_TOKEN"]
# config = JSON.parse("./config.json")
config = JSON.parse(File.read("./config.json"))

@bearer_token = config["BearerToken"]

@stream_url = "https://api.twitter.com/2/tweets/search/stream"
@rules_url = "https://api.twitter.com/2/tweets/search/stream/rules"

@sample_rules = [
  { 'value': '(ruby OR python) (developer OR engineer) remote (context:66.961961812492148736 OR context:66.850073441055133696)', 'tag': 'remote s/w jobs' },
  { 'value': 'personal finance savings (context:66.847888632711061504 has:links -is:retweet savings)', 'tag': 'savings tips' },
]
  # { "value": "context:123.1220701888179359745 lang:en -is:retweet", "tag": "covid" },
  #{ 'value': 'dog has:images', 'tag': 'dog pictures' },
  #{ 'value': 'cat has:images -grumpy', 'tag': 'cat pictures' },

# Add or remove values from the optional parameters below. Full list of parameters can be found in the docs:
# https://developer.twitter.com/en/docs/twitter-api/tweets/filtered-stream/api-reference/get-tweets-search-stream
params = {
  #"expansions": "attachments.poll_ids,attachments.media_keys,author_id,entities.mentions.username,geo.place_id,in_reply_to_user_id,referenced_tweets.id,referenced_tweets.id.author_id",
  #"tweet.fields": "attachments,author_id,conversation_id,created_at,entities,geo,id,in_reply_to_user_id,lang",
  ## "user.fields": "description",
  ## "media.fields": "url", 
  ## "place.fields": "country_code",
  ## "poll.fields": "options"
  "tweet.fields": "author_id,conversation_id,created_at,entities,geo,id,in_reply_to_user_id,lang,text",
}

# Get request to rules endpoint. Returns list of of active rules from your stream 
def get_all_rules
  @options = {
    headers: {
      "User-Agent": "v2FilteredStreamRuby",
      "Authorization": "Bearer #{@bearer_token}"
    }
  }

  @response = Typhoeus.get(@rules_url, @options)

  raise "An error occurred while retrieving active rules from your stream: #{@response.body}" unless @response.success?

  @body = JSON.parse(@response.body)
end

# Post request to add rules to your stream
def set_rules(rules)
  return if rules.nil?

  @payload = {
    add: rules
  }

  @options = {
    headers: {
      "User-Agent": "v2FilteredStreamRuby",
      "Authorization": "Bearer #{@bearer_token}",
      "Content-type": "application/json"
    },
    body: JSON.dump(@payload)
  }

  @response = Typhoeus.post(@rules_url, @options)
  raise "An error occurred while adding rules: #{@response.status_message}" unless @response.success?
end

# Post request with a delete body to remove rules from your stream
def delete_all_rules(rules)
  return if rules.nil?

  @ids = rules['data'].map { |rule| rule["id"] }
  @payload = {
    delete: {
      ids: @ids
    }
  }

  @options = {
    headers: {
      "User-Agent": "v2FilteredStreamRuby",
      "Authorization": "Bearer #{@bearer_token}",
      "Content-type": "application/json"
    },
    body: JSON.dump(@payload)
  }

  @response = Typhoeus.post(@rules_url, @options)

  raise "An error occurred while deleting your rules: #{@response.status_message}" unless @response.success?
end

# Helper method that gets active rules and prompts to delete (y/n), then adds new rules set in line 17 (@sample_rules)
def setup_rules
  # Gets the complete list of rules currently applied to the stream
  @rules = get_all_rules
  warn "Found existing rules on the stream:\n #{@rules}\n"

  #warn "Do you want to delete existing rules and replace with new rules? [y/n]"
  #answer = gets.chomp
  #if answer == "y"
  #  # Delete all rules
  delete_all_rules(@rules)
  #else
  #warn "Keeping existing rules and adding new ones."
  #end
  
  # Add rules to the stream
  set_rules(@sample_rules)
end

# Connects to the stream and returns data (Tweet payloads) in chunks
def stream_connect(params)
  @options = {
    timeout: 20,
    method: 'get',
    headers: {
      "User-Agent": "v2FilteredStreamRuby",
      "Authorization": "Bearer #{@bearer_token}"
    },
    params: params
  }

  @request = Typhoeus::Request.new(@stream_url, @options)
  @request.on_body do |chunk|
    # warn("raw chunk: #{chunk.inspect}")
    parsed_chunk = JSON.parse(chunk) rescue chunk
    # warn("parsed chunk == chunk: #{(parsed_chunk == chunk).inspect}")
    data = parsed_chunk["data"]
    puts data&.slice("id", "text").to_json
    #puts parsed_chunk["data"].slice("id", "text").inspect
  end
  @request.run
end

# Comment this line if you already setup rules and want to keep them
setup_rules

# Listen to the stream.
# This reconnection logic will attempt to reconnect when a disconnection is detected.
# To avoid rate limites, this logic implements exponential backoff, so the wait time
# will increase if the client cannot reconnect to the stream.
timeout = 0
while true
  stream_connect(params)
  warn "sleeping for timeout: #{timeout.inspect}..."
  sleep 2 ** timeout
  timeout += 1
end
