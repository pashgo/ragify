# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ragify
  # Minimal HTTP client using Net::HTTP. No external dependencies.
  class HttpClient
    class ApiError < Error; end

    def post_json(url, body:, timeout: 30)
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

      raise ApiError, "OpenAI API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
