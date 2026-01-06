# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      module Init
        TEMPLATE = <<~RUBY
          # frozen_string_literal: true

          # Liquid Spec Adapter
          #
          # This file defines how your Liquid implementation compiles and renders templates.
          # Implement the methods below to test your implementation against the spec.
          #
          # Run with: liquid-spec run %<filename>s

          LiquidSpec.setup do |ctx|
            # ctx is a hash for storing adapter state (environment, file_system, etc.)
            # Example: ctx[:environment] = MyLiquid::Environment.new
          end

          LiquidSpec.configure do |config|
            # Which spec suites to run: :all, :liquid_ruby, :dawn
            config.suite = :liquid_ruby

            # Optional: filter specs by name pattern
            # config.filter = /assign/
          end

          # Called to compile a template string into your implementation's template object.
          #
          # @param ctx [Hash] Adapter context (from setup block)
          # @param source [String] The Liquid template source code
          # @param options [Hash] Parse options (e.g., :error_mode, :line_numbers)
          # @return [Object] Your compiled template object (passed to render)
          #
          LiquidSpec.compile do |ctx, source, options|
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
          # @param ctx [Hash] Adapter context (from setup block)
          # @param template [Object] The compiled template (from compile block)
          # @param assigns [Hash] Variables available as {{ var }}
          # @param options [Hash] Render options (:registers, :strict_errors, :error_mode)
          # @return [String] The rendered output
          #
          LiquidSpec.render do |ctx, template, assigns, options|
            # Example for Shopify/liquid:
            #   context = Liquid::Context.build(
            #     static_environments: assigns,
            #     registers: Liquid::Registers.new(options[:registers] || {})
            #   )
            #   template.render(context)
            #
            # Example for a custom implementation:
            #   template.render(assigns)
            #
            raise NotImplementedError, "Implement LiquidSpec.render to render templates"
          end
        RUBY

        JSON_RPC_TEMPLATE = <<~RUBY
          #!/usr/bin/env ruby
          # frozen_string_literal: true

          require "liquid/spec/cli/adapter_dsl"

          # ==============================================================================
          # JSON-RPC Liquid Adapter
          # ==============================================================================
          #
          # This adapter communicates with a Liquid implementation subprocess via
          # JSON-RPC 2.0 over stdin/stdout. Implement the protocol below in any language.
          #
          # Usage:
          #   liquid-spec %<filename>s
          #   liquid-spec %<filename>s --command="./my-liquid-server"
          #
          # ==============================================================================
          # PROTOCOL SPECIFICATION
          # ==============================================================================
          #
          # All messages are JSON-RPC 2.0, one JSON object per line (newline-delimited).
          # The subprocess reads requests from stdin and writes responses to stdout.
          #
          # --- LIFECYCLE ---
          #
          # 1. initialize (parent -> subprocess)
          #    Request:  {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"version":"1.0"}}
          #    Response: {"jsonrpc":"2.0","id":1,"result":{"version":"1.0","features":["core"]}}
          #
          # 2. quit (parent -> subprocess) - notification, no response expected
          #    Notification: {"jsonrpc":"2.0","method":"quit","params":{}}
          #    Subprocess should exit cleanly within 1 second.
          #
          # --- COMPILE ---
          #
          # Compile a template and return an ID for later rendering.
          #
          # Request:
          #   {
          #     "jsonrpc": "2.0",
          #     "id": 2,
          #     "method": "compile",
          #     "params": {
          #       "template": "{{ x | upcase }}",
          #       "options": {
          #         "error_mode": "strict",   // "strict", "lax", or null
          #         "line_numbers": true
          #       },
          #       "filesystem": {             // templates for {% include %} / {% render %}
          #         "snippet.liquid": "hello {{ name }}"
          #       }
          #     }
          #   }
          #
          # Response (success):
          #   {"jsonrpc":"2.0","id":2,"result":{"template_id":"abc123"}}
          #
          # Response (parse error):
          #   {
          #     "jsonrpc": "2.0",
          #     "id": 2,
          #     "error": {
          #       "code": -32000,
          #       "message": "Parse error",
          #       "data": {"type": "parse_error", "line": 1, "message": "Unknown tag 'foo'"}
          #     }
          #   }
          #
          # --- RENDER ---
          #
          # Render a previously compiled template with variables.
          #
          # Request:
          #   {
          #     "jsonrpc": "2.0",
          #     "id": 3,
          #     "method": "render",
          #     "params": {
          #       "template_id": "abc123",
          #       "environment": {
          #         "x": "hello",
          #         "items": [1, 2, 3],
          #         "user": {"_rpc_drop": "drop_1", "type": "UserDrop"}
          #       },
          #       "options": {
          #         "render_errors": false  // true = render errors as text, false = throw
          #       }
          #     }
          #   }
          #
          # Response (success):
          #   {"jsonrpc":"2.0","id":3,"result":{"output":"HELLO"}}
          #
          # Response (render error):
          #   {
          #     "jsonrpc": "2.0",
          #     "id": 3,
          #     "error": {
          #       "code": -32001,
          #       "message": "Render error",
          #       "data": {"type": "render_error", "line": 1, "message": "undefined method"}
          #     }
          #   }
          #
          # --- RPC DROPS (subprocess -> parent) ---
          #
          # When environment contains {"_rpc_drop": "ID", "type": "ClassName"},
          # the subprocess must call back to parent to access properties/methods.
          # Send the request to stdout, read the response from stdin.
          #
          # drop_get - Get a property value:
          #   Request:  {"jsonrpc":"2.0","id":100,"method":"drop_get","params":{"drop_id":"drop_1","property":"name"}}
          #   Response: {"jsonrpc":"2.0","id":100,"result":{"value":"John"}}
          #   Note: value may itself be {"_rpc_drop": "drop_2", "type": "..."} for nested drops
          #
          # drop_call - Call a method with arguments:
          #   Request:  {"jsonrpc":"2.0","id":101,"method":"drop_call","params":{"drop_id":"drop_1","method":"calculate","args":[1,2]}}
          #   Response: {"jsonrpc":"2.0","id":101,"result":{"value":3}}
          #
          # drop_iterate - Get all items from enumerable (for {% for %} loops):
          #   Request:  {"jsonrpc":"2.0","id":102,"method":"drop_iterate","params":{"drop_id":"drop_1"}}
          #   Response: {"jsonrpc":"2.0","id":102,"result":{"items":[1,2,3,4,5]}}
          #
          # --- ERROR CODES ---
          #
          # -32000  Parse error (template syntax error)
          # -32001  Render error (runtime error)
          # -32002  Drop access error (property/method not found)
          # -32700  JSON parse error (invalid JSON received)
          # -32600  Invalid request (malformed JSON-RPC)
          # -32601  Method not found (unknown method name)
          #
          # ==============================================================================

          DEFAULT_COMMAND = "path/to/your/liquid-server"

          LiquidSpec.setup do |ctx|
            require "liquid"
            require "liquid/spec/json_rpc/adapter"

            # CLI --command flag overrides DEFAULT_COMMAND
            command = LiquidSpec.cli_options[:command] || DEFAULT_COMMAND
            ctx[:adapter] = Liquid::Spec::JsonRpc::Adapter.new(command)
            ctx[:adapter].start

            at_exit { ctx[:adapter]&.shutdown }
          end

          LiquidSpec.configure do |config|
            config.features = [:core]  # Adjust based on your implementation's capabilities
          end

          LiquidSpec.compile do |ctx, source, options|
            ctx[:adapter].compile(source, options)
          end

          LiquidSpec.render do |ctx, template_id, assigns, options|
            ctx[:adapter].render(template_id, assigns, options)
          end
        RUBY

        def self.agents_md_content(filename, json_rpc: false)
          <<~MARKDOWN
            # Implementing a Liquid Template Engine

            This document guides AI agents through implementing a Liquid template engine using liquid-spec for verification.

            ## Quick Start

            ```bash
            # Run your adapter against the spec suite
            liquid-spec run #{filename}

            # Run with verbose output to see each test
            liquid-spec run #{filename} -v

            # Filter tests by name pattern
            liquid-spec run #{filename} -n assign

            # Show all failures (default stops at 10)
            liquid-spec run #{filename} --no-max-failures
            ```

            ## How It Works

            1. **Your adapter** defines `compile` and `render` blocks that bridge liquid-spec to your implementation
            2. **liquid-spec** runs test cases in **complexity order** (simplest features first)
            3. **You implement features** incrementally, fixing failing specs from lowest to highest complexity

            ## Complexity-Ordered Implementation

            Specs are sorted by complexity score before running. This means you'll see failures for basic features first, then progressively harder ones. **Fix specs in the order they fail.**

            ### Implementation Phases

            | Phase | Complexity | Features |
            |-------|------------|----------|
            | 1 | 10-60 | Raw text, literals, variables, assign, if/else |
            | 2 | 70-100 | For loops, operators, math filters, capture |
            | 3 | 105-150 | String filters, increment, comment, raw, arrays |
            | 4 | 170-220 | Edge cases, truthy/falsy, cycle, tablerow, partials |
            | 5 | 300+ | Advanced edge cases, production behaviors |

            ### Complexity Reference

            | Score | What to Implement |
            |-------|-------------------|
            | 10 | Raw text passthrough (no parsing) |
            | 20 | Literal values: `{{ 'hello' }}`, `{{ 42 }}`, `{{ true }}` |
            | 30 | Variable lookup: `{{ name }}` |
            | 40 | Basic filters: `{{ x \\| upcase }}` |
            | 50 | Assign tag: `{% assign x = 'foo' %}` |
            | 55 | Whitespace control: `{{- x -}}` |
            | 60 | If/else/unless: `{% if x %}...{% endif %}` |
            | 70 | For loops: `{% for i in items %}` |
            | 75 | Loop modifiers: limit, offset, reversed, break, continue |
            | 80 | Filter chains, and/or, contains, comparison operators |
            | 85-100 | Math filters, forloop object, capture, case/when |
            #{json_rpc ? json_rpc_section(filename) : ruby_adapter_section}

            ## Debugging Failures

            When a spec fails, you'll see:

            ```
            1) test_assign_basic
               Template: "{% assign x = 'hello' %}{{ x }}"
               Expected: "hello"
               Got:      ""
            ```

            Use `liquid-spec eval` to test individual templates:

            ```bash
            # Quick test with comparison to reference
            liquid-spec eval #{filename} -n test_assign --liquid="{% assign x = 1 %}{{ x }}"

            # Test with environment variables
            liquid-spec eval #{filename} -n test_var -l "{{ x | size }}" -a '{"x": [1,2,3]}'
            ```

            ## Common Implementation Mistakes

            1. **Truthy/falsy**: In Liquid, only `false` and `nil` are falsy. Empty strings and `0` are truthy.
            2. **Variable scope**: Assign creates variables in the current scope. For loops have their own scope.
            3. **Filter arguments**: Filters can have arguments: `{{ x | slice: 0, 3 }}`
            4. **Whitespace**: `{{-` and `-}}` strip adjacent whitespace.
            5. **Error handling**: Undefined variables return empty string, not an error.

            ## Feature Flags

            Some specs require specific features. Your adapter declares what it supports:

            ```ruby
            LiquidSpec.configure do |config|
              config.features = [
                :core,           # Basic Liquid (always included)
                :lax_parsing,    # Supports error_mode: :lax
              ]
            end
            ```

            ## Iterative Development Loop

            1. Run `liquid-spec run #{filename}`
            2. Note the first failure and its complexity score
            3. Implement the minimal feature to pass that spec
            4. Re-run and repeat

            The complexity ordering ensures you build a solid foundation. Don't skip ahead—later features often depend on earlier ones working correctly.

            ## Useful Commands

            ```bash
            # List all available specs
            liquid-spec run #{filename} -l

            # List available suites
            liquid-spec run #{filename} --list-suites

            # Run specific suite
            liquid-spec run #{filename} -s basics

            # Compare your output to reference implementation
            liquid-spec run #{filename} --compare
            ```

            ## Reference

            - [Liquid Documentation](https://shopify.github.io/liquid/)
            - [liquid-spec repository](https://github.com/Shopify/liquid-spec)
            - See `COMPLEXITY.md` in liquid-spec for full complexity scoring guide
          MARKDOWN
        end

        def self.ruby_adapter_section
          <<~MARKDOWN

            ## The Adapter Pattern (Ruby)

            Your adapter has three main blocks. All receive `ctx` (a hash) as the first parameter for storing adapter state.

            ### setup(ctx) - Initialize once

            Set up your Liquid environment, register custom tags/filters.

            ```ruby
            LiquidSpec.setup do |ctx|
              require "my_liquid"
              ctx[:environment] = MyLiquid::Environment.build do |env|
                env.register_tag("custom", CustomTag)
                env.register_filter(CustomFilters)
              end
            end
            ```

            ### compile(ctx, source, options) → template

            Parse the source string into your template representation. Called once per template.

            ```ruby
            LiquidSpec.compile do |ctx, source, options|
              # options may include:
              #   :error_mode - :strict or :lax
              #   :line_numbers - true/false
              #   :file_system - for include/render tags
              MyLiquid::Template.parse(source, environment: ctx[:environment])
            end
            ```

            ### render(ctx, template, assigns, options) → string

            Render a compiled template with variables. Called for each test.

            ```ruby
            LiquidSpec.render do |ctx, template, assigns, options|
              # assigns: Hash of variables available as {{ var }}
              # options may include:
              #   :registers - internal state (file_system, etc.)
              #   :strict_errors - whether to raise or capture errors
              template.render(assigns)
            end
            ```
          MARKDOWN
        end

        def self.json_rpc_section(filename)
          <<~MARKDOWN

            ## JSON-RPC Protocol (Non-Ruby Implementations)

            Your implementation communicates with liquid-spec via JSON-RPC 2.0 over stdin/stdout.
            Implement a server that reads JSON requests from stdin and writes responses to stdout.

            ### Running Your Implementation

            ```bash
            # Run with your server command
            liquid-spec run #{filename} --command="./your-liquid-server"

            # Or set DEFAULT_COMMAND in the adapter file
            ```

            ### Protocol Overview

            All messages are newline-delimited JSON. The lifecycle is:

            1. **initialize** - liquid-spec sends version info, your server responds with supported features
            2. **compile** - Parse a template, return a template_id
            3. **render** - Render a compiled template with variables
            4. **quit** - Notification to exit cleanly (no response expected)

            ### Example: Minimal Server (Node.js)

            ```javascript
            #!/usr/bin/env node
            const readline = require('readline');
            const templates = new Map();
            let nextId = 1;

            const rl = readline.createInterface({ input: process.stdin });

            rl.on('line', (line) => {
              const { id, method, params = {} } = JSON.parse(line);

              if (method === 'initialize') {
                respond(id, { version: '1.0', features: ['core'] });
              } else if (method === 'compile') {
                const templateId = `t${nextId++}`;
                templates.set(templateId, { source: params.template, filesystem: params.filesystem || {} });
                respond(id, { template_id: templateId });
              } else if (method === 'render') {
                const t = templates.get(params.template_id);
                const output = renderLiquid(t.source, params.environment || {}, t.filesystem);
                respond(id, { output });
              } else if (method === 'quit') {
                process.exit(0);  // No response needed for quit notification
              }
            });

            function respond(id, result) {
              console.log(JSON.stringify({ jsonrpc: '2.0', id, result }));
            }

            function renderLiquid(source, env, filesystem) {
              // Your Liquid implementation here!
              return source;
            }
            ```

            ### Compile Request/Response

            ```json
            // Request
            {"jsonrpc":"2.0","id":1,"method":"compile","params":{
              "template": "{{ x | upcase }}",
              "options": {"error_mode": "strict"},
              "filesystem": {"snippet.liquid": "Hello"}
            }}

            // Success response
            {"jsonrpc":"2.0","id":1,"result":{"template_id":"abc123"}}

            // Parse error response
            {"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"Parse error","data":{"type":"parse_error","message":"Unknown tag"}}}
            ```

            ### Render Request/Response

            ```json
            // Request
            {"jsonrpc":"2.0","id":2,"method":"render","params":{
              "template_id": "abc123",
              "environment": {"x": "hello", "items": [1,2,3]},
              "options": {"render_errors": false}
            }}

            // Success response
            {"jsonrpc":"2.0","id":2,"result":{"output":"HELLO"}}

            // Render error response
            {"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"Render error","data":{"type":"render_error","message":"undefined variable"}}}
            ```

            ### Error Codes

            | Code | Meaning |
            |------|---------|
            | -32000 | Parse error (template syntax error) |
            | -32001 | Render error (runtime error) |
            | -32700 | JSON parse error |
            | -32600 | Invalid request |
            | -32601 | Method not found |

            See the adapter file (`#{filename}`) for the complete protocol specification.
          MARKDOWN
        end

        LIQUID_RUBY_TEMPLATE = <<~RUBY
          # frozen_string_literal: true

          # Liquid Spec Adapter for Shopify/liquid
          #
          # Run with: liquid-spec run %<filename>s

          require "liquid"

          LiquidSpec.setup do |ctx|
            # ctx can store adapter state like custom environments
          end

          LiquidSpec.configure do |config|
            config.suite = :liquid_ruby
          end

          LiquidSpec.compile do |ctx, source, options|
            Liquid::Template.parse(source, **options)
          end

          LiquidSpec.render do |ctx, template, assigns, options|
            context = Liquid::Context.build(
              static_environments: assigns,
              registers: Liquid::Registers.new(options[:registers] || {})
            )
            template.render(context)
          end
        RUBY

        def self.run(args)
          filename = args.shift || "liquid_adapter.rb"
          template_type = :basic

          # Check for template type flags
          if args.include?("--json-rpc") || args.include?("-j")
            template_type = :json_rpc
          elsif args.include?("--liquid-ruby") || args.include?("-l")
            template_type = :liquid_ruby
          end

          if File.exist?(filename)
            $stderr.puts "Error: #{filename} already exists"
            $stderr.puts "Delete it first or choose a different name"
            exit(1)
          end

          template = case template_type
          when :json_rpc
            # JSON-RPC template uses gsub because format() chokes on JSON examples
            JSON_RPC_TEMPLATE.gsub("%<filename>s", filename)
          when :liquid_ruby
            format(LIQUID_RUBY_TEMPLATE, filename: filename)
          else
            format(TEMPLATE, filename: filename)
          end

          File.write(filename, template)
          puts "Created #{filename}"

          # Create AGENTS.md alongside the adapter
          agents_md = agents_md_content(filename, json_rpc: template_type == :json_rpc)
          agents_filename = "AGENTS.md"
          if File.exist?(agents_filename)
            puts "AGENTS.md already exists, skipping"
          else
            File.write(agents_filename, agents_md)
            puts "Created AGENTS.md"
          end

          puts ""

          case template_type
          when :json_rpc
            puts "Next steps:"
            puts "  1. Edit DEFAULT_COMMAND in #{filename} to point to your Liquid server"
            puts "  2. Implement the JSON-RPC protocol in your server (see comments in file)"
            puts "  3. Run: liquid-spec #{filename}"
            puts "     Or:  liquid-spec #{filename} --command='./your-server'"
          else
            puts "Next steps:"
            puts "  1. Edit #{filename} to implement compile and render"
            puts "  2. Run: liquid-spec run #{filename}"
          end

          puts ""
          puts "If using an AI agent, point it at AGENTS.md for implementation guidance."
        end
      end
    end
  end
end
