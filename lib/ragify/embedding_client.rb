# frozen_string_literal: true

module Ragify
  class EmbeddingClient
    OPENAI_URL = "https://api.openai.com/v1/embeddings"
    MAX_TEXT_LENGTH = 30_000

    def generate(text)
      return nil if text.nil? || text.to_s.strip.empty?

      response = request(truncate(text))
      response.dig("data", 0, "embedding")
    rescue HttpClient::ApiError, Net::OpenTimeout, Net::ReadTimeout => e
      config.logger.error("[Ragify] Embedding failed: #{e.message}")
      nil
    end

    def generate_batch(texts)
      return [] if texts.nil? || texts.empty?

      truncated = texts.map { |t| truncate(t) }
      response = request(truncated)

      data = response["data"] || []
      embeddings = Array.new(texts.size)

      data.each do |item|
        index = item["index"]
        embeddings[index] = item["embedding"] if index && index < texts.size
      end

      embeddings
    rescue HttpClient::ApiError, Net::OpenTimeout, Net::ReadTimeout => e
      config.logger.error("[Ragify] Batch embedding failed: #{e.message}")
      Array.new(texts.size)
    end

    private

    def request(input)
      body = { model: config.embedding_model, input: input }
      body[:dimensions] = config.embedding_dimensions if config.embedding_dimensions
      HttpClient.new.post_json(OPENAI_URL, body: body)
    end

    def truncate(text)
      text.to_s[0, MAX_TEXT_LENGTH]
    end

    def config
      Ragify.configuration
    end
  end
end
