module RubygemSearchable
  extend ActiveSupport::Concern

  included do
    include Elasticsearch::Model

    index_name "rubygems-#{Rails.env}"

    delegate :index_document, to: :__elasticsearch__
    delegate :update_document, to: :__elasticsearch__


    settings number_of_shards: 1,
             number_of_replicas: 1,
             analysis: {
               analyzer: {
                 rubygem: {
                   type: "pattern",
                   pattern: "[\s#{Regexp.escape(Patterns::SPECIAL_CHARACTERS)}]+"
                 }
               }
             }

    mapping do
      indexes :name, type: "text", analyzer: "rubygem" do
        indexes :suggest, analyzer: "simple"
        indexes :unanalyzed, type: "keyword", index: "true"
      end
      indexes :summary, type: "text", analyzer: "english" do
        indexes :raw, analyzer: "simple"
      end
      indexes :description, type: "text", analyzer: "english" do
        indexes :raw, analyzer: "simple"
      end
      indexes :yanked, type: "boolean"
      indexes :downloads, type: "integer"
      indexes :updated, type: "date"
    end

    def self.legacy_search(query)
      conditions = <<-SQL
        versions.indexed and
          (UPPER(name) LIKE UPPER(:query) OR
           UPPER(TRANSLATE(name, :match, :replace)) LIKE UPPER(:query))
      SQL

      replace_characters = " " * Patterns::SPECIAL_CHARACTERS.length
      where(conditions, query: "%#{query.strip}%", match: Patterns::SPECIAL_CHARACTERS, replace: replace_characters)
        .includes(:latest_version, :gem_download)
        .references(:versions)
        .by_downloads
    end
  end
end
