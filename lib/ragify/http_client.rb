# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ragify
  # Minimal HTTP client with retry/backoff. No external dependencies.
  class HttpClient
    class ApiError < Error; end
    class RateLimitError < ApiError; end
    class AuthenticationError < ApiError; end
    class TimeoutError < ApiError; end

    MAX_RETRIES = 3
    BASE_BACKOFF = 1 # seconds

    def post_json(url, body:, timeout: 30)
      retries = 0

      begin
        raw_request(url, body: body, timeout: timeout)
      rescue RateLimitError, TimeoutError, Net::OpenTimeout, Net::ReadTimeout => e
        retries += 1
        if retries <= MAX_RETRIES
          sleep(BASE_BACKOFF * (2**(retries - 1))) # exponential: 1s, 2s, 4s
          retry
        end
        raise ApiError, "#{e.message} (after #{MAX_RETRIES} retries)"
      end
    end

    private

    def raw_request(url, body:, timeout:)
      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{Ragify.configuration.openai_api_key!}"
      request.body = JSON.generate(body)

      response = http.request(request)

      case response
      when Net::HTTPSuccess
        JSON.parse(response.body)
      when Net::HTTPTooManyRequests
        raise RateLimitError, "Rate limited (429)"
      when Net::HTTPUnauthorized
        raise AuthenticationError, "Invalid API key (401)"
      else
        raise ApiError, "OpenAI API error #{response.code}: #{response.body.to_s[0, 200]}"
      end
    end
  end
end
