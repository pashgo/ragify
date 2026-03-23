# frozen_string_literal: true

module Ragify
  # RAG chat: find relevant context via semantic search, then ask an LLM.
  #
  #   Ragify.chat("how does cashback work?",
  #     context_model: FaqEntry,
  #     system_prompt: "You are a helpful assistant."
  #   )
  #   # => { answer: "Cashback is...", context: [...], tokens: 342 }
  #
  class Chat
    OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"

    DEFAULT_SYSTEM_PROMPT = "You are a helpful assistant. Answer questions based on the provided context. " \
                            "If the context doesn't contain relevant information, say you don't know."

    def initialize(context_model:, system_prompt: nil, search_limit: nil, history: nil)
      @context_model = context_model
      @system_prompt = system_prompt || DEFAULT_SYSTEM_PROMPT
      @search_limit = search_limit
      @history = history || []
    end

    def call(query)
      search_results = Search.new(@context_model).call(query, limit: @search_limit)
      context = build_context(search_results)
      messages = build_messages(query, context)

      response = chat_completion(messages)
      answer = response.dig("choices", 0, "message", "content")&.strip
      tokens = response.dig("usage", "total_tokens") || 0

      {
        answer: answer,
        context: search_results,
        tokens: tokens,
        had_context: search_results.any?
      }
    rescue HttpClient::ApiError, Net::OpenTimeout, Net::ReadTimeout => e
      config.logger.error("[Ragify::Chat] API error: #{e.message}")
      { answer: nil, context: [], tokens: 0, had_context: false, error: e.message }
    end

    private

    def build_context(results)
      return "" if results.empty?

      results.map do |result|
        "[Relevance: #{(result[:similarity] * 100).round}%]\n#{result[:content]}"
      end.join("\n\n---\n\n")
    end

    def build_messages(query, context)
      messages = [{ role: "system", content: @system_prompt }]

      @history.each do |msg|
        messages << { role: msg[:role].to_s, content: msg[:content].to_s }
      end

      user_content = if context.present?
                       "Context:\n#{context}\n\n---\n\nQuestion: #{query}"
                     else
                       query
                     end

      messages << { role: "user", content: user_content }
      messages
    end

    def chat_completion(messages)
      HttpClient.new.post_json(OPENAI_CHAT_URL, body: {
                                 model: config.chat_model,
                                 messages: messages,
                                 max_tokens: config.max_tokens,
                                 temperature: config.temperature
                               }, timeout: 60)
    end

    def config
      Ragify.configuration
    end
  end
end
