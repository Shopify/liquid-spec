# frozen_string_literal: true

require "yaml"

module Liquid
  module Spec
    module CLI
      # Command to list and display implementer documentation
      module Docs
        DOCS_PATH = File.expand_path("../../../../docs/implementers", __dir__)

        class << self
          def run(args)
            if args.empty?
              list_docs
            else
              show_doc(args.first)
            end
          end

          private

          def list_docs
            docs = load_all_docs

            if docs.empty?
              puts "No documentation found."
              return
            end

            # Sort: required docs first, then optional
            required = docs.reject { |d| d[:optional] }
            optional = docs.select { |d| d[:optional] }

            puts "Implementer Documentation"
            puts "=" * 60
            puts ""

            unless required.empty?
              puts "\e[1mCore Documentation (Start Here)\e[0m"
              puts ""
              required.each { |doc| print_doc_summary(doc) }
            end

            unless optional.empty?
              puts "\e[2mOptional (Performance/Advanced)\e[0m"
              puts ""
              optional.each { |doc| print_doc_summary(doc) }
            end

            puts ""
            puts "View a document: \e[1mliquid-spec docs <name>\e[0m"
            puts "Example: liquid-spec docs core-abstractions"
          end

          def print_doc_summary(doc)
            puts "\e[1m#{doc[:title]}\e[0m"
            puts doc[:description]
            puts "\e[2mliquid-spec docs #{doc[:name]}\e[0m"
            puts ""
          end

          def show_doc(name)
            # Try exact match first, then with .md extension
            doc_file = find_doc_file(name)

            unless doc_file
              $stderr.puts "Document not found: #{name}"
              $stderr.puts ""
              $stderr.puts "Available documents:"
              load_all_docs.each do |doc|
                $stderr.puts "  #{doc[:name]}"
              end
              exit(1)
            end

            content = File.read(doc_file)

            # Strip frontmatter for display
            if content.start_with?("---")
              parts = content.split("---", 3)
              content = parts[2].strip if parts.length >= 3
            end

            puts content
          end

          def find_doc_file(name)
            # Try exact match
            exact = File.join(DOCS_PATH, name)
            return exact if File.exist?(exact)

            # Try with .md extension
            with_ext = File.join(DOCS_PATH, "#{name}.md")
            return with_ext if File.exist?(with_ext)

            nil
          end

          def load_all_docs
            return [] unless File.directory?(DOCS_PATH)

            Dir[File.join(DOCS_PATH, "*.md")].map do |file|
              load_doc_metadata(file)
            end.compact.sort_by { |d| [d[:optional] ? 1 : 0, d[:order] || 100, d[:title]] }
          end

          def load_doc_metadata(file)
            content = File.read(file)
            name = File.basename(file, ".md")

            # Parse YAML frontmatter if present
            if content.start_with?("---")
              parts = content.split("---", 3)
              if parts.length >= 3
                begin
                  frontmatter = YAML.safe_load(parts[1], permitted_classes: [Symbol])
                  return {
                    name: name,
                    title: frontmatter["title"] || name.tr("-", " ").capitalize,
                    description: frontmatter["description"] || "",
                    optional: frontmatter["optional"] || false,
                    order: frontmatter["order"] || 100,
                  }
                rescue Psych::SyntaxError
                  # Fall through to defaults
                end
              end
            end

            # Default metadata from first heading
            title = content.match(/^#\s+(.+)$/)&.captures&.first || name.tr("-", " ").capitalize

            {
              name: name,
              title: title,
              description: "(No description available)",
              optional: false,
              order: 100,
            }
          end
        end
      end
    end
  end
end
