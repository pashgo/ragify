# Ragify

RAG (Retrieval-Augmented Generation) for Rails. Add semantic search and AI chat to any ActiveRecord model using pgvector and OpenAI.

No external vector databases. No complex infrastructure. Just your PostgreSQL and a few lines of code.

## Requirements

- Ruby >= 3.2
- Rails >= 7.0
- PostgreSQL with [pgvector](https://github.com/pgvector/pgvector) extension
- OpenAI API key

## Installation

Add to your Gemfile:

```ruby
gem "ragify"
```

Then run:

```bash
bundle install
```

## Quick Start

### 1. Configure

```ruby
# config/initializers/ragify.rb
Ragify.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.embedding_model = "text-embedding-3-small"  # default
  config.chat_model = "gpt-4o-mini"                  # default
  config.similarity_threshold = 0.2                   # default
end
```

### 2. Add embedding column

```bash
rails generate ragify:install FaqEntry
rails db:migrate
```

This creates a migration that adds a `vector` column with an IVFFlat index.

### 3. Include in your model

```ruby
class FaqEntry < ApplicationRecord
  include Ragify::Embeddable

  ragify_content { |record| "#{record.question} #{record.answer}" }
end
```

### 4. Use it

```ruby
# Semantic search
results = FaqEntry.semantic_search("how does cashback work?")
# => [{ record: #<FaqEntry>, content: "...", similarity: 0.87 }, ...]

# RAG chat (search + LLM)
response = Ragify.chat("how does cashback work?",
  context_model: FaqEntry,
  system_prompt: "You are a helpful assistant for a loyalty program."
)
# => { answer: "Cashback is automatically...", context: [...], tokens: 342 }

# Generate embeddings for existing records
FaqEntry.embed_all!
```

## Features

### Embeddable

Include `Ragify::Embeddable` in any ActiveRecord model. Embeddings are automatically generated on create/update.

```ruby
class Article < ApplicationRecord
  include Ragify::Embeddable

  # Block form - full control over content
  ragify_content { |r| "#{r.title}\n#{r.body}" }

  # Or method form
  ragify_content :embedding_text
end
```

### Semantic Search

Find records by meaning, not keywords.

```ruby
Article.semantic_search("climate change effects",
  limit: 10,           # max results (default: 5)
  threshold: 0.3       # min similarity 0-1 (default: 0.2)
)
```

Returns an array of hashes with `:record`, `:content`, and `:similarity`.

### RAG Chat

Combine semantic search with an LLM for context-aware answers.

```ruby
Ragify.chat("what's your refund policy?",
  context_model: FaqEntry,
  system_prompt: "You are a customer support agent.",
  search_limit: 5,
  history: [
    { role: "user", content: "hi" },
    { role: "assistant", content: "Hello! How can I help?" }
  ]
)
```

Returns a hash:

```ruby
{
  answer: "Our refund policy allows...",
  context: [{ record: ..., content: "...", similarity: 0.91 }],
  tokens: 487,
  had_context: true
}
```

### Batch Embedding

Generate embeddings for all records (useful for initial setup):

```ruby
FaqEntry.embed_all!

# Or embed specific records
Ragify.embed("some text")
Ragify.embed_batch(["text 1", "text 2", "text 3"])
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `openai_api_key` | `ENV["OPENAI_API_KEY"]` | OpenAI API key |
| `embedding_model` | `text-embedding-3-small` | Embedding model |
| `embedding_dimensions` | `1536` | Vector dimensions |
| `chat_model` | `gpt-4o-mini` | Chat completion model |
| `max_tokens` | `1000` | Max response tokens |
| `temperature` | `0.3` | LLM temperature |
| `similarity_threshold` | `0.2` | Min cosine similarity |
| `search_limit` | `5` | Default search results |
| `ivfflat_probes` | `10` | IVFFlat index probes |
| `logger` | `Rails.logger` | Logger instance |

## How It Works

1. **Embedding**: When a record is saved, `ragify_content` extracts text and sends it to OpenAI's embedding API. The resulting vector is stored in a pgvector column.

2. **Search**: Queries are embedded the same way, then pgvector finds the nearest neighbors using cosine similarity with an IVFFlat index.

3. **Chat**: The search results are injected as context into an LLM prompt, which generates a grounded answer.

## Contributing

Bug reports and pull requests are welcome at https://github.com/pashgo/ragify.

## License

MIT License. See [LICENSE](LICENSE) for details.
