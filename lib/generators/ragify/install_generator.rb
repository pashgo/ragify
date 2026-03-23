# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Ragify
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    argument :model_name, type: :string, desc: "Model to add embeddings to (e.g., FaqEntry)"

    def create_migration
      migration_template "add_embedding_migration.rb.erb",
                         "db/migrate/add_ragify_embedding_to_#{table_name}.rb"
    end

    def show_post_install
      say ""
      say "Ragify installed! Next steps:", :green
      say ""
      say "  1. Run the migration:"
      say "     rails db:migrate"
      say ""
      say "  2. Add to your model:"
      say "     class #{model_name} < ApplicationRecord"
      say "       include Ragify::Embeddable"
      say '       ragify_content { |r| r.question + " " + r.answer }'
      say "     end"
      say ""
      say "  3. Generate embeddings for existing records:"
      say "     #{model_name}.embed_all!"
      say ""
      say "  4. Search:"
      say "     #{model_name}.semantic_search(\"your query\")"
      say ""
    end

    private

    def table_name
      model_name.underscore.pluralize
    end

    def dimensions
      Ragify.configuration.embedding_dimensions
    end
  end
end
