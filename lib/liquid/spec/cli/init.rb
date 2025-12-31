# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      module Init
        TEMPLATE = <<~'RUBY'
          # frozen_string_literal: true

          # Liquid Spec Adapter
          # 
          # This file defines how your Liquid implementation compiles and renders templates.
          # Implement the two methods below to test your implementation against the spec.
          #
          # Run with: liquid-spec run %<filename>s

          LiquidSpec.configure do |config|
            # Which spec suites to run: :all, :liquid_ruby, :dawn
            config.suite = :liquid_ruby

            # Optional: filter specs by name pattern
            # config.filter = /assign/
          end

          # Called to compile a template string into your implementation's template object.
          # This is optional - if not defined, the template string is passed directly to render.
          #
          # @param source [String] The Liquid template source code
          # @param options [Hash] Parse options (e.g., :error_mode, :line_numbers)
          # @return [Object] Your compiled template object (passed to render)
          #
          LiquidSpec.compile do |source, options|
            # Example for Shopify/liquid:
            #   Liquid::Template.parse(source, options)
            #
            # Example for a custom implementation:
            #   MyLiquid::Template.new(source)
            #
            raise NotImplementedError, "Implement LiquidSpec.compile to parse templates"
          end

          # Called to render a compiled template with the given context.
          #
          # @param template [Object] The compiled template (from compile block, or source string)
          # @param context [Hash] The render context with :assigns, :registers, :environment
          #   - :assigns [Hash] Variables available as {{ var }}
          #   - :registers [Hash] Internal registers (file_system, etc.)
          #   - :environment [Hash] Static environment variables
          # @return [String] The rendered output
          #
          LiquidSpec.render do |template, context|
            # Example for Shopify/liquid:
            #   liquid_context = Liquid::Context.build(
            #     environments: [context[:environment]],
            #     registers: context[:registers]
            #   )
            #   liquid_context.merge(context[:assigns])
            #   template.render(liquid_context)
            #
            # Example for a custom implementation:
            #   template.render(context[:assigns].merge(context[:environment]))
            #
            raise NotImplementedError, "Implement LiquidSpec.render to render templates"
          end
        RUBY

        LIQUID_RUBY_TEMPLATE = <<~'RUBY'
          # frozen_string_literal: true

          # Liquid Spec Adapter for Shopify/liquid
          #
          # Run with: liquid-spec run %<filename>s

          require "liquid"

          LiquidSpec.configure do |config|
            config.suite = :liquid_ruby
          end

          LiquidSpec.compile do |source, options|
            Liquid::Template.parse(source, **options)
          end

          LiquidSpec.render do |template, context|
            liquid_context = Liquid::Context.build(
              environments: [context[:environment] || {}],
              registers: Liquid::Registers.new(context[:registers] || {})
            )
            liquid_context.merge(context[:assigns] || {})
            template.render(liquid_context)
          end
        RUBY

        def self.run(args)
          filename = args.shift || "liquid_adapter.rb"
          template_type = :basic

          # Check for --liquid-ruby flag
          if args.include?("--liquid-ruby") || args.include?("-l")
            template_type = :liquid_ruby
          end

          if File.exist?(filename)
            $stderr.puts "Error: #{filename} already exists"
            $stderr.puts "Delete it first or choose a different name"
            exit 1
          end

          template = case template_type
          when :liquid_ruby
            format(LIQUID_RUBY_TEMPLATE, filename: filename)
          else
            format(TEMPLATE, filename: filename)
          end

          File.write(filename, template)
          puts "Created #{filename}"
          puts ""
          puts "Next steps:"
          puts "  1. Edit #{filename} to implement compile and render"
          puts "  2. Run: liquid-spec run #{filename}"
        end
      end
    end
  end
end
