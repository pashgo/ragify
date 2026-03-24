# frozen_string_literal: true

RSpec.describe Ragify do
  it "has a version number" do
    expect(Ragify::VERSION).not_to be_nil
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(Ragify::Configuration)
    end

    it "allows setting openai_api_key" do
      described_class.configure do |config|
        config.openai_api_key = "test-key"
      end

      expect(described_class.configuration.openai_api_key).to eq("test-key")
    ensure
      described_class.configuration.openai_api_key = nil
    end
  end

  describe Ragify::Configuration do
    subject(:config) { described_class.new }

    it "has sensible defaults" do
      expect(config.embedding_model).to eq("text-embedding-3-small")
      expect(config.embedding_dimensions).to eq(1536)
      expect(config.chat_model).to eq("gpt-4o-mini")
      expect(config.similarity_threshold).to eq(0.2)
      expect(config.search_limit).to eq(5)
      expect(config.async).to be(false)
      expect(config.ivfflat_probes).to eq(10)
      expect(config.max_tokens).to eq(1000)
      expect(config.temperature).to eq(0.3)
    end

    describe "#openai_api_key!" do
      it "raises when key is not set" do
        config.openai_api_key = nil
        expect { config.openai_api_key! }.to raise_error(Ragify::Error, /not configured/)
      end

      it "returns the key when set" do
        config.openai_api_key = "sk-test"
        expect(config.openai_api_key!).to eq("sk-test")
      end
    end

    describe "#validate!" do
      it "passes with valid defaults" do
        expect(config.validate!).to be(true)
      end

      it "raises for invalid dimensions" do
        config.embedding_dimensions = -1
        expect { config.validate! }.to raise_error(Ragify::Error, /dimensions/)
      end

      it "raises for zero dimensions" do
        config.embedding_dimensions = 0
        expect { config.validate! }.to raise_error(Ragify::Error, /dimensions/)
      end

      it "raises for invalid threshold" do
        config.similarity_threshold = 5.0
        expect { config.validate! }.to raise_error(Ragify::Error, /threshold/)
      end

      it "raises for negative threshold" do
        config.similarity_threshold = -0.1
        expect { config.validate! }.to raise_error(Ragify::Error, /threshold/)
      end

      it "raises for invalid temperature" do
        config.temperature = 3.0
        expect { config.validate! }.to raise_error(Ragify::Error, /temperature/)
      end

      it "raises for zero search_limit" do
        config.search_limit = 0
        expect { config.validate! }.to raise_error(Ragify::Error, /search_limit/)
      end

      it "raises for zero max_tokens" do
        config.max_tokens = 0
        expect { config.validate! }.to raise_error(Ragify::Error, /max_tokens/)
      end

      it "accepts boundary values" do
        config.similarity_threshold = 0.0
        config.temperature = 2.0
        expect(config.validate!).to be(true)
      end
    end
  end

  describe Ragify::HttpClient do
    subject(:client) { described_class.new }

    before { Ragify.configure { |c| c.openai_api_key = "test" } }

    after { Ragify.configuration.openai_api_key = nil }

    it "raises AuthenticationError on 401" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 401, body: '{"error":"invalid_api_key"}')

      expect { client.post_json("https://api.openai.com/v1/embeddings", body: {}) }
        .to raise_error(Ragify::HttpClient::AuthenticationError, /401/)
    end

    it "raises ApiError on 500" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 500, body: "Internal Server Error")

      expect { client.post_json("https://api.openai.com/v1/embeddings", body: {}) }
        .to raise_error(Ragify::HttpClient::ApiError, /500/)
    end

    it "retries on 429 rate limit with backoff" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 429, body: "Rate limited")
        .then.to_return(status: 200, body: '{"data":[]}', headers: { "Content-Type" => "application/json" })

      allow(client).to receive(:sleep) # skip actual sleep in tests

      result = client.post_json("https://api.openai.com/v1/embeddings", body: {})
      expect(result).to eq({ "data" => [] })
    end

    it "raises after max retries on persistent rate limit" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 429, body: "Rate limited").times(4)

      allow(client).to receive(:sleep)

      expect { client.post_json("https://api.openai.com/v1/embeddings", body: {}) }
        .to raise_error(Ragify::HttpClient::ApiError, /retries/)
    end

    it "retries on timeout" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_timeout
        .then.to_return(status: 200, body: '{"data":[]}', headers: { "Content-Type" => "application/json" })

      allow(client).to receive(:sleep)

      result = client.post_json("https://api.openai.com/v1/embeddings", body: {})
      expect(result).to eq({ "data" => [] })
    end

    it "parses JSON response" do
      stub_request(:post, "https://api.openai.com/v1/test")
        .to_return(status: 200, body: '{"result":"ok"}', headers: { "Content-Type" => "application/json" })

      result = client.post_json("https://api.openai.com/v1/test", body: { foo: "bar" })
      expect(result).to eq({ "result" => "ok" })
    end

    it "sends authorization header" do
      stub_request(:post, "https://api.openai.com/v1/test")
        .with(headers: { "Authorization" => "Bearer test" })
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.post_json("https://api.openai.com/v1/test", body: {})
    end
  end

  describe Ragify::EmbeddingClient do
    subject(:client) { described_class.new }

    before { Ragify.configure { |c| c.openai_api_key = "test" } }

    after { Ragify.configuration.openai_api_key = nil }

    it "returns nil for blank text" do
      expect(client.generate(nil)).to be_nil
      expect(client.generate("")).to be_nil
      expect(client.generate("   ")).to be_nil
    end

    it "returns empty array for blank batch" do
      expect(client.generate_batch(nil)).to eq([])
      expect(client.generate_batch([])).to eq([])
    end

    it "generates embedding from OpenAI response" do
      embedding = Array.new(1536) { rand }

      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 200, body: { data: [{ embedding: embedding, index: 0 }] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = client.generate("test text")
      expect(result).to eq(embedding)
    end

    it "sends dimensions to OpenAI" do
      Ragify.configuration.embedding_dimensions = 512

      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .with(body: hash_including("dimensions" => 512))
        .to_return(status: 200, body: { data: [{ embedding: Array.new(512) { 0.1 }, index: 0 }] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      client.generate("test")
    ensure
      Ragify.configuration.embedding_dimensions = 1536
    end

    it "sends configured model to OpenAI" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .with(body: hash_including("model" => "text-embedding-3-small"))
        .to_return(status: 200, body: { data: [{ embedding: [0.1], index: 0 }] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      client.generate("test")
    end

    it "returns nil on API error" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 500, body: "Internal Server Error")

      expect(client.generate("test")).to be_nil
    end

    it "truncates long text" do
      long_text = "a" * 50_000

      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .with { |req| JSON.parse(req.body)["input"].length <= 30_000 }
        .to_return(status: 200, body: { data: [{ embedding: [0.1], index: 0 }] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      client.generate(long_text)
    end

    describe "#generate_batch" do
      it "sends multiple texts and returns ordered embeddings" do
        emb1 = [0.1, 0.2]
        emb2 = [0.3, 0.4]

        stub_request(:post, "https://api.openai.com/v1/embeddings")
          .to_return(status: 200,
                     body: { data: [{ embedding: emb2, index: 1 }, { embedding: emb1, index: 0 }] }.to_json,
                     headers: { "Content-Type" => "application/json" })

        result = client.generate_batch(%w[text1 text2])
        expect(result).to eq([emb1, emb2])
      end

      it "returns array of nils on error" do
        stub_request(:post, "https://api.openai.com/v1/embeddings")
          .to_return(status: 500, body: "error")

        result = client.generate_batch(%w[a b c])
        expect(result).to eq([nil, nil, nil])
      end
    end
  end

  describe Ragify::Chat do
    before { Ragify.configure { |c| c.openai_api_key = "test" } }

    after { Ragify.configuration.openai_api_key = nil }

    it "builds messages with system prompt and context" do
      # Stub search to return empty (no context)
      search = instance_double(Ragify::Search, call: [])
      allow(Ragify::Search).to receive(:new).and_return(search)

      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with do |req|
          body = JSON.parse(req.body)
          messages = body["messages"]
          messages.first["role"] == "system" && messages.last["role"] == "user"
        end
        .to_return(status: 200,
                   body: { choices: [{ message: { content: "Hello!" } }], usage: { total_tokens: 50 } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = Ragify.chat("hi", context_model: Class.new)
      expect(result[:answer]).to eq("Hello!")
      expect(result[:tokens]).to eq(50)
      expect(result[:had_context]).to be(false)
    end

    it "includes conversation history" do
      search = instance_double(Ragify::Search, call: [])
      allow(Ragify::Search).to receive(:new).and_return(search)

      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with do |req|
          messages = JSON.parse(req.body)["messages"]
          messages.any? { |m| m["content"] == "previous question" }
        end
        .to_return(status: 200,
                   body: { choices: [{ message: { content: "answer" } }], usage: { total_tokens: 10 } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      Ragify.chat("new question",
                  context_model: Class.new,
                  history: [{ role: "user", content: "previous question" }])
    end

    it "returns error hash on API failure" do
      search = instance_double(Ragify::Search, call: [])
      allow(Ragify::Search).to receive(:new).and_return(search)

      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 401, body: "Unauthorized")

      result = Ragify.chat("test", context_model: Class.new)
      expect(result[:answer]).to be_nil
      expect(result[:error]).to include("401")
    end
  end
end
