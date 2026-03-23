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

      it "raises for invalid threshold" do
        config.similarity_threshold = 5.0
        expect { config.validate! }.to raise_error(Ragify::Error, /threshold/)
      end

      it "raises for invalid temperature" do
        config.temperature = 3.0
        expect { config.validate! }.to raise_error(Ragify::Error, /temperature/)
      end
    end
  end

  describe Ragify::HttpClient do
    subject(:client) { described_class.new }

    it "raises ApiError on non-200 response" do
      Ragify.configure { |c| c.openai_api_key = "test" }

      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 401, body: '{"error":"invalid_api_key"}')

      expect { client.post_json("https://api.openai.com/v1/embeddings", body: {}) }
        .to raise_error(Ragify::HttpClient::ApiError, /401/)
    ensure
      Ragify.configuration.openai_api_key = nil
    end
  end

  describe Ragify::EmbeddingClient do
    subject(:client) { described_class.new }

    before { Ragify.configure { |c| c.openai_api_key = "test" } }

    after { Ragify.configuration.openai_api_key = nil }

    it "returns nil for blank text" do
      expect(client.generate(nil)).to be_nil
      expect(client.generate("")).to be_nil
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

    it "returns nil on API error" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 500, body: "Internal Server Error")

      expect(client.generate("test")).to be_nil
    end
  end
end
