# frozen_string_literal: true

require "logger"
require "digest"

module Ragify
  class Configuration
    attr_accessor :openai_api_key,
                  :embedding_model,
                  :embedding_dimensions,
                  :chat_model,
                  :max_tokens,
                  :temperature,
                  :similarity_threshold,
                  :search_limit,
                  :ivfflat_probes,
                  :logger,
                  :async

    def initialize
      @openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
      @embedding_model = "text-embedding-3-small"
      @embedding_dimensions = 1536
      @chat_model = "gpt-4o-mini"
      @max_tokens = 1000
      @temperature = 0.3
      @similarity_threshold = 0.2
      @search_limit = 5
      @ivfflat_probes = 10
      @async = false
      @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
    end

    def openai_api_key!
      openai_api_key || raise(
        Error,
        "Ragify: openai_api_key is not configured. " \
        "Set via Ragify.configure { |c| c.openai_api_key = '...' } or ENV['OPENAI_API_KEY']"
      )
    end

    def validate!
      unless embedding_dimensions.is_a?(Integer) && embedding_dimensions.positive?
        raise Error,
              "embedding_dimensions must be a positive integer"
      end
      raise Error, "similarity_threshold must be between 0 and 1" unless (0..1).cover?(similarity_threshold.to_f)
      raise Error, "search_limit must be positive" unless search_limit.to_i.positive?
      raise Error, "ivfflat_probes must be positive" unless ivfflat_probes.to_i.positive?
      raise Error, "max_tokens must be positive" unless max_tokens.to_i.positive?
      raise Error, "temperature must be between 0 and 2" unless (0..2).cover?(temperature.to_f)

      true
    end
  end
end
