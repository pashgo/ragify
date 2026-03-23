# frozen_string_literal: true

require "active_support/concern"
require "neighbor"
require "digest"

module Ragify
  # Include in ActiveRecord models to add vector embeddings and semantic search.
  #
  #   class FaqEntry < ApplicationRecord
  #     include Ragify::Embeddable
  #     ragify_content { |record| "#{record.question} #{record.answer}" }
  #   end
  #
  #   FaqEntry.semantic_search("how does cashback work?")
  #   FaqEntry.embed_all!
  #
  module Embeddable
    extend ActiveSupport::Concern

    included do
      has_neighbors :embedding

      scope :with_embedding, -> { where.not(embedding: nil) }

      after_commit :ragify_generate_embedding, on: %i[create update], if: :ragify_content_changed?
    end

    class_methods do
      # Define how to build the text content for embedding.
      #
      #   ragify_content { |record| "#{record.title} #{record.body}" }
      #   ragify_content :embedding_text  # calls record.embedding_text
      #
      def ragify_content(method_name = nil, &block)
        if block
          @ragify_content_proc = block
        elsif method_name
          @ragify_content_proc = ->(record) { record.public_send(method_name) }
        else
          raise ArgumentError, "ragify_content requires a method name or block"
        end
      end

      def ragify_content_proc
        @ragify_content_proc || raise(Error, "#{name}: call `ragify_content` to define what text to embed")
      end

      # Search for records semantically similar to the query string.
      #
      #   FaqEntry.semantic_search("refund policy", limit: 5, threshold: 0.3)
      #
      def semantic_search(query, limit: nil, threshold: nil)
        Search.new(self).call(query, limit: limit, threshold: threshold)
      end

      # Generate embeddings for all records using batch API.
      #
      #   FaqEntry.embed_all!
      #   FaqEntry.where(embedding: nil).embed_all!
      #
      def embed_all!(batch_size: 50)
        client = EmbeddingClient.new
        find_each(batch_size: batch_size).each_slice(batch_size) do |batch|
          texts = batch.map { |record| ragify_content_proc.call(record) }
          embeddings = client.generate_batch(texts)

          batch.each_with_index do |record, i|
            next unless embeddings[i]

            record.update_columns(embedding: embeddings[i], embedding_digest: Digest::SHA256.hexdigest(texts[i].to_s))
          end
        end
      end
    end

    # Returns the text that will be embedded for this record.
    def ragify_text
      self.class.ragify_content_proc.call(self)
    end

    private

    def ragify_generate_embedding
      text = ragify_text
      return if text.blank?

      if Ragify.configuration.async
        ragify_async_embed
      else
        ragify_sync_embed(text)
      end
    end

    def ragify_sync_embed(text)
      embedding = Ragify.embed(text)
      return unless embedding

      update_columns(embedding: embedding, embedding_digest: Digest::SHA256.hexdigest(text.to_s))
    end

    # Override this method to use your own async job.
    #
    #   def ragify_async_embed
    #     MyEmbeddingJob.perform_later(id)
    #   end
    #
    def ragify_async_embed
      Ragify.configuration.logger.warn(
        "[Ragify] async=true but ragify_async_embed not overridden in #{self.class.name}. " \
        "Override it to enqueue a background job."
      )
    end

    def ragify_content_changed?
      text = ragify_text
      return false if text.blank?

      current_digest = Digest::SHA256.hexdigest(text.to_s)

      if respond_to?(:embedding_digest) && embedding_digest.present?
        current_digest != embedding_digest
      else
        true
      end
    end
  end
end
