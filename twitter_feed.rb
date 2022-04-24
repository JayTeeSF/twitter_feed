#!/usr/bin/env ruby

require 'json'
require 'typhoeus'

class TwitterFeed
  STOP_FILE = './stop'
  CONFIG_FILE = './config.json'
  RULES_FILE = './rules.json'

  def self.run(do_delete=false)
    new.run(do_delete)
  end

  def self.help(name)
    return %Q|Stream tweets matching pre-configured rules:\n\tgrab an hour's worth: #{name} > tweets.json & sleep 3600 && kill -9 %1 && echo "" >> tweets.json && echo "]" >> tweets.json\n\tclear existing rules before resubmitting pre-configured rules: #{name} --delete\n\tto get this message: #{name} --help|
  end


  # Get request to rules endpoint. Returns list of of active rules from your stream 
  def get_all_rules
    options = {
      headers: {
        "User-Agent": "v2FilteredStreamRuby",
        "Authorization": "Bearer #{@bearer_token}"
      }
    }

    @response = Typhoeus.get(@rules_url, options)

    raise "An error occurred while retrieving active rules from your stream: #{@response.body}" unless @response.success?

    @body = JSON.parse(@response.body)
  end

  # Post request to add rules to your stream
  def set_rules(rules)
    return if rules.nil?

    @payload = {
      add: rules
    }

    options = {
      headers: {
        "User-Agent": "v2FilteredStreamRuby",
        "Authorization": "Bearer #{@bearer_token}",
        "Content-type": "application/json"
      },
      body: JSON.dump(@payload)
    }

    @response = Typhoeus.post(@rules_url, options)
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

    options = {
      headers: {
        "User-Agent": "v2FilteredStreamRuby",
        "Authorization": "Bearer #{@bearer_token}",
        "Content-type": "application/json"
      },
      body: JSON.dump(@payload)
    }

    @response = Typhoeus.post(@rules_url, options)

    raise "An error occurred while deleting your rules: #{@response.status_message}" unless @response.success?
  end

  # Helper method that gets active rules and prompts to delete (y/n), then adds new rules set in line 17 (@sample_rules)
  def setup_rules(do_delete=false)
    # Gets the complete list of rules currently applied to the stream
    @rules = get_all_rules
    warn "Found existing rules on the stream:\n #{@rules}\n"

    if do_delete
      delete_all_rules(@rules)
      warn("Deleted all rules")
    else
      warn "Rerun this program with the '--delete' parameter, to delete existing rules"
      warn "Keeping existing rules and adding new ones."
    end

    # Add rules to the stream
    set_rules(@sample_rules)
  end

  # Connects to the stream and returns data (Tweet payloads) in chunks
  def stream_connect
    last_chunk = nil

    @request = Typhoeus::Request.new(@stream_url, @options)
    @request.on_body do |chunk|
      parsed_chunk = JSON.parse(chunk)
      data = parsed_chunk&.dig("data")
      if output = data&.slice("id", "text")&.to_json
        puts ",\n" unless last_chunk.nil?
        last_chunk = "not nil"
        print output
      end
      fail("done") if File.exists?(STOP_FILE)
    rescue Exception => e
      warn(%Q|unable to parse chunk: #{chunk.inspect}; e: #{e.message}, bkt: #{e.backtrace.join("\n\t")}|)
      if File.exists?(STOP_FILE)
        raise("done") 
      end
    end
    @request.run
  ensure
    puts "" unless last_chunk.nil? # ensure there's a blank after the last tweet
  end

  def initialize
    # This script contains methods to add, remove, and retrieve rules from your stream.
    # It will also connect to the stream endpoint and begin outputting data.
    # Run as-is, the script gives you the option to replace existing rules with new ones and begin streaming data

    @bearer_token = JSON.parse(File.read(CONFIG_FILE))["BearerToken"]

    @stream_url = "https://api.twitter.com/2/tweets/search/stream"
    @rules_url = "https://api.twitter.com/2/tweets/search/stream/rules"

    @sample_rules = JSON.parse(File.read(RULES_FILE))

    # Add or remove values from the optional parameters below. Full list of parameters can be found in the docs:
    # https://developer.twitter.com/en/docs/twitter-api/tweets/filtered-stream/api-reference/get-tweets-search-stream
    @params = {
      #"expansions": "attachments.poll_ids,attachments.media_keys,author_id,entities.mentions.username,geo.place_id,in_reply_to_user_id,referenced_tweets.id,referenced_tweets.id.author_id",
      #"tweet.fields": "attachments,author_id,conversation_id,created_at,entities,geo,id,in_reply_to_user_id,lang",
      ## "user.fields": "description",
      ## "media.fields": "url", 
      ## "place.fields": "country_code",
      ## "poll.fields": "options"
      "tweet.fields": "author_id,conversation_id,created_at,entities,geo,id,in_reply_to_user_id,lang,text",
    }

    @options = {
      timeout: 20,
      method: 'get',
      headers: {
        "User-Agent": "v2FilteredStreamRuby",
        "Authorization": "Bearer #{@bearer_token}"
      },
      params: @params
    }
  end

  def run(do_delete=false)
    old_sync = $stdout.sync
    $stdout.sync = true
    # Comment this line if you already setup rules and want to keep them
    setup_rules(do_delete)
    return if do_delete || File.exists?(STOP_FILE)

    # Listen to the stream.
    # This reconnection logic will attempt to reconnect when a disconnection is detected.
    # To avoid rate limits, this logic implements exponential backoff, so the wait time
    # will increase if the client cannot reconnect to the stream.
    timeout = 0
    puts "["
    while true
      begin
        stream_connect
      rescue Exception => e
        if File.exists?(STOP_FILE)
          break
          raise("done")
        end
      end
      warn "sleeping for timeout: #{timeout.inspect}..."
      sleep 2 ** timeout
      timeout += 1
    end
  ensure
    puts "]"
    # reenable the default behavior
    $stdout.sync = old_sync
  end
end

if __FILE__ == $PROGRAM_NAME
  if File.exists?(TwitterFeed::STOP_FILE)
    fail "Remove the stop file to continue: rm #{TwitterFeed::STOP_FILE}"
  end
  if ARGV.size >= 1
    if ARGV[0] == '--delete'
      TwitterFeed.run(true)
    else
      warn TwitterFeed.help($PROGRAM_NAME)
    end
  else
    TwitterFeed.run(false)
  end
end
