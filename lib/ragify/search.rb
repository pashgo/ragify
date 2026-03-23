# frozen_string_literal: true

module Ragify
  # Semantic vector search against an Embeddable model.
  #
  #   Search.new(FaqEntry).call("how does cashback work?")
  #   # => [{ record: #<FaqEntry>, content: "...", similarity: 0.87 }, ...]
  #
  class Search
    def initialize(model)
      @model = model
    end

    def call(query, limit: nil, threshold: nil)
      limit ||= config.search_limit
      threshold ||= config.similarity_threshold

      embedding = EmbeddingClient.new.generate(query)
      return [] if embedding.nil?

      set_ivfflat_probes

      results = @model
                .with_embedding
                .nearest_neighbors(:embedding, embedding, distance: "cosine")
                .limit(limit * 2)
                .to_a

      results
        .select { |record| (1 - record.neighbor_distance) >= threshold }
        .first(limit)
        .map { |record| format_result(record) }
    end

    private

    def set_ivfflat_probes
      @model.connection.execute("SET ivfflat.probes = #{config.ivfflat_probes}")
    end

    def format_result(record)
      similarity = (1 - record.neighbor_distance).round(4)
      content = record.ragify_text

      { record: record, content: content, similarity: similarity }
    end

    def config
      Ragify.configuration
    end
  end
end
