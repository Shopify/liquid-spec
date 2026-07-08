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

            puts "Liquid implementation docs"
            puts "=" * 60
            puts ""
            puts "Docs directory:"
            puts "  #{DOCS_PATH}"
            puts ""
            puts "Docs:"
            docs.each_with_index do |doc, index|
              connector = index == docs.length - 1 ? "└──" : "├──"
              puts "#{connector} #{doc[:name]}"
            end

            puts ""
            puts "Open a doc:  \e[1mliquid-spec docs <name>\e[0m"
            puts "Start here:  liquid-spec docs curriculum"
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
            # implementers/ first, then the docs/ root (json-rpc-protocol.md
            # lives there) — exact name, then with .md appended.
            [DOCS_PATH, File.expand_path("..", DOCS_PATH)].each do |dir|
              exact = File.join(dir, name)
              return exact if File.file?(exact)

              with_ext = File.join(dir, "#{name}.md")
              return with_ext if File.file?(with_ext)
            end

            nil
          end

          def load_all_docs
            return [] unless File.directory?(DOCS_PATH)

            Dir[File.join(DOCS_PATH, "*.md")].map do |file|
              load_doc_metadata(file)
            end.compact.sort_by { |d| [d[:position] || 100, d[:name]] }
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
                    position: frontmatter["position"] || frontmatter["order"] || 100,
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
              position: 100,
            }
          end
        end
      end
    end
  end
end
