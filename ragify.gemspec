# frozen_string_literal: true

require_relative "lib/ragify/version"

Gem::Specification.new do |spec|
  spec.name = "ragify"
  spec.version = Ragify::VERSION
  spec.authors = ["Pavel Skripin"]
  spec.email = ["skripin.pavel@gmail.com"]

  spec.summary = "RAG (Retrieval-Augmented Generation) for Rails with pgvector and OpenAI"
  spec.description = "Add semantic search and AI-powered chat to any ActiveRecord model. " \
                     "Uses pgvector for vector storage, OpenAI for embeddings, and your existing PostgreSQL database."
  spec.homepage = "https://github.com/pashgo/ragify"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/pashgo/ragify"
  spec.metadata["changelog_uri"] = "https://github.com/pashgo/ragify/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "neighbor", ">= 0.3"
end
