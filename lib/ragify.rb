# frozen_string_literal: true

require_relative "ragify/version"

module Ragify
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def chat(query, context_model:, system_prompt: nil, **)
      Chat.new(context_model: context_model, system_prompt: system_prompt, **).call(query)
    end

    def embed(text)
      EmbeddingClient.new.generate(text)
    end

    def embed_batch(texts)
      EmbeddingClient.new.generate_batch(texts)
    end
  end
end

require_relative "ragify/configuration"
require_relative "ragify/http_client"
require_relative "ragify/embedding_client"
require_relative "ragify/embeddable"
require_relative "ragify/search"
require_relative "ragify/chat"
