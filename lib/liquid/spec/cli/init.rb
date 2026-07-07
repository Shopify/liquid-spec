# frozen_string_literal: true

module Liquid
  module Spec
    module CLI
      module Init
        TEMPLATE = <<~RUBY
          #!/usr/bin/env ruby
          # frozen_string_literal: true

          # Liquid Spec Adapter (Ruby)
          #
          # This file defines how your Liquid implementation compiles and renders templates.
          # Implement the methods below to test your implementation against the spec.
          #
          # Run directly:  ./%<filename>s                  # re-launches via liquid-spec
          # Run directly:  ./%<filename>s -n assign        # filter specs by name
          # Or run via:    liquid-spec run %<filename>s
          #
          # Not using Ruby? liquid-spec can drive an implementation in any language
          # (Rust, Go, Python, Node.js, ...) over JSON-RPC. Generate a JSON-RPC
          # adapter instead:
          #
          #   liquid-spec init --jsonrpc my_adapter.rb
          #
          # See docs/json-rpc-protocol.md for the full protocol specification.

          # When executed directly, re-launch through liquid-spec on this file.
          # When loaded by liquid-spec, this guard is skipped and the adapter DSL runs.
          if __FILE__ == $PROGRAM_NAME
            cmd = ["liquid-spec", "run", __FILE__, *ARGV]
            cmd = ["bundle", "exec"] + cmd if File.exist?("Gemfile")
            exec(*cmd)
          end

          require "liquid/spec/cli/adapter_dsl"

          LiquidSpec.setup do |ctx|
            # ctx is a hash for storing adapter state (environment, file_system, etc.)
            # Example: ctx[:environment] = MyLiquid::Environment.new
          end

          LiquidSpec.configure do |config|
            # Which spec suites to run: :all, :basics, :liquid_ruby, :liquid_ruby_lax,
            # :partials, :parser_errors, :benchmarks, :shopify_theme_dawn, ...
            config.suite = :liquid_ruby

            # Optional: filter specs by name pattern
            # config.filter = /assign/
            # Specs that need Ruby-specific behavior (Hash#inspect output format
            # `{"k"=>"v"}`, symbol keys, binary bytes) are tagged `ruby_types`.
            # A Ruby implementation should leave these ENABLED (do not list them
            # here). A non-Ruby implementation that is not yet emulating Ruby's
            # inspect/to_s format can opt out temporarily:
            #   config.missing_features = [:ruby_types, :binary_data]
            # See docs/ruby_hash_inspect_format.md for what opting in requires.
          end

          # Called to compile a template string into your implementation's template object.
          #
          # @param ctx [Hash] Adapter context (from setup block)
          # @param source [String] The Liquid template source code
          # @param options [Hash] Parse options (e.g., :error_mode, :line_numbers)
          # @return [Object] Your compiled template object (passed to render)
          #
          # ERROR MODES
          # -----------
          # options[:error_mode] is set by the spec when a spec targets a specific mode.
          # When no mode is requested, default to :strict2 (the modern Liquid 5.12+
          # parser with relaxed trailing comma/colon syntax). This is the recommended
          # default for new implementations.
          #
          # Legacy modes exist but are NOT recommended unless you need backwards
          # compatibility with older Liquid versions or Shopify production:
          #
          #   :strict - The original strict parser. Rejects trailing commas/colons that
          #             :strict2 accepts. Use only if you must match pre-5.12 behavior.
          #   :lax    - Lenient parsing that silently ignores syntax errors and renders
          #             broken tags as text. Legacy compatibility only; new
          #             implementations should NOT support lax mode.
          #   :raise  - Alias for :lax parsing with errors raised at render time instead
          #             of rendered inline. Legacy behavior preserved for backwards
          #             compatibility; new implementations should NOT support it.
          #
          # Unless you have a specific backwards-compatibility requirement, implement
          # only :strict2 and let specs targeting :strict, :lax, or :raise be skipped.
          #
          LiquidSpec.compile do |ctx, source, options|
            # Default to strict2 when the spec doesn't request a specific error mode
            options[:error_mode] ||= :strict2

            # Example for Shopify/liquid:
            #   Liquid::Template.parse(source, options)
            #
            # Example for a custom implementation:
            #   MyLiquid::Template.new(source, error_mode: options[:error_mode])
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
          # RENDER ERROR HANDLING
          # ----------------------
          # options[:strict_errors] controls whether render-time errors are raised
          # (thrown) or rendered inline as text in the output. liquid-spec defaults
          # to strict_errors: true (raise) — only specs that opt into render_errors
          # set it to false. Pass it through to your implementation so both modes work.
          #
          LiquidSpec.render do |ctx, template, assigns, options|
            # Example for Shopify/liquid:
            #   context = Liquid::Context.build(
            #     static_environments: assigns,
            #     registers: Liquid::Registers.new(options[:registers] || {}),
            #     rethrow_errors: options[:strict_errors]
            #   )
            #   template.render(context)
            #
            # Example for a custom implementation:
            #   template.render(assigns, raise_errors: options[:strict_errors])
            #
            raise NotImplementedError, "Implement LiquidSpec.render to render templates"
          end
        RUBY

        JSON_RPC_TEMPLATE = <<~RUBY
          #!/usr/bin/env ruby
          # frozen_string_literal: true

          # When executed directly, re-launch through liquid-spec on this file.
          # When loaded by liquid-spec, this guard is skipped and the adapter DSL runs.
          if __FILE__ == $PROGRAM_NAME
            cmd = ["liquid-spec", "run", __FILE__, *ARGV]
            cmd = ["bundle", "exec"] + cmd if File.exist?("Gemfile")
            exec(*cmd)
          end

          require "liquid/spec/cli/adapter_dsl"

          # ==============================================================================
          # JSON-RPC Liquid Adapter
          # ==============================================================================
          #
          # This adapter communicates with a Liquid implementation subprocess via
          # JSON-RPC 2.0 over stdin/stdout. Implement the protocol below in any language.
          #
          # Usage:
          #   ./%<filename>s                         # run directly (re-launches via liquid-spec)
          #   liquid-spec run %<filename>s
          #   liquid-spec run %<filename>s --command="./my-liquid-server"
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
          #    Response: {"jsonrpc":"2.0","id":1,"result":{"version":"1.0","features":[]}}
          #    Note: features are informational. The Ruby adapter controls spec
          #    selection with config.missing_features below.
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
          #         "error_mode": "strict2", // "strict2" (default), "strict", "lax", "raise", or null
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
          # Response (parse error, preferred):
          #   {"jsonrpc":"2.0","id":2,"result":{"template_id":null,"error":{"type":"parse_error","line":1,"message":"Unknown tag 'foo'"}}}
          #
          # Legacy response also accepted:
          #   {"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"Parse error","data":{"type":"parse_error","line":1,"message":"Unknown tag 'foo'"}}}
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
          #         "strict_errors": true  // true = report render errors, false = render inline text
          #       }
          #     }
          #   }
          #
          # Response (success):
          #   {"jsonrpc":"2.0","id":3,"result":{"output":"HELLO"}}
          #
          # Response (render error with strict_errors=true, preferred):
          #   {"jsonrpc":"2.0","id":3,"result":{"output":null,"error":{"type":"render_error","line":1,"message":"undefined method"}}}
          #
          # Response (inline render error with strict_errors=false):
          #   {"jsonrpc":"2.0","id":3,"result":{"output":"Liquid error: undefined method","errors":[{"type":"render_error","message":"undefined method"}]}}
          #
          # Legacy render-error JSON-RPC error code -32001 is also accepted.
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
          # -32000  Legacy parse error (accepted; prefer result.error)
          # -32001  Legacy render error (accepted; prefer result.error)
          # -32002  Drop access error (property/method not found)
          # -32700  JSON parse error (invalid JSON received)
          # -32600  Invalid request (malformed JSON-RPC)
          # -32601  Method not found (unknown method name)
          #
          # ==============================================================================
          #
          # DEBUG OUTPUT
          # ------------
          # Your server can write to stderr for debug output. liquid-spec forwards all
          # stderr to the terminal, prefixed with [server-name]. Example:
          #   console.error("Compiling:", template);  // Node.js
          #   eprintln!("Compiling: {}", template);   // Rust
          #   print("Compiling:", template, file=sys.stderr)  # Python
          #
          # ==============================================================================

          DEFAULT_COMMAND = "path/to/your/liquid-server"
          DEFAULT_TIMEOUT = 2  # seconds - increase if your server needs more time

          LiquidSpec.setup do |ctx|
            require "liquid"
            require "liquid/spec/json_rpc/adapter"

            # CLI --command flag overrides DEFAULT_COMMAND
            command = LiquidSpec.cli_options[:command] || DEFAULT_COMMAND
            timeout = LiquidSpec.cli_options[:timeout]&.to_i || DEFAULT_TIMEOUT

            ctx[:adapter] = Liquid::Spec::JsonRpc::Adapter.new(command, timeout: timeout)
            ctx[:adapter].start

            # Features reported by the subprocess are informational. Spec
            # selection is controlled by config.missing_features below.
            ctx[:features] = ctx[:adapter].features

            at_exit { ctx[:adapter]&.shutdown }
          end

          LiquidSpec.configure do |config|
            # Opt out of specs your implementation doesn't support yet.
            # List features here that should be SKIPPED (the adapter is "missing" them).
            #
            # For a JSON-RPC server that doesn't implement bidirectional drop
            # callbacks (drop_get/drop_call/drop_iterate), opt out of :runtime_drops.
            # Once you add drop callbacks, remove it from this list.
            #
            # Common opt-out features:
            #   :runtime_drops  - drop_get/drop_call/drop_iterate callbacks
            #   :lax_parsing    - error_mode: :lax (lenient parsing)
            #   :ruby_types             - Ruby-specific types (symbols, ranges, etc.)
            #   :ruby_drops             - Ruby-specific object/drop fixtures
            #   :drop_class_output      - Ruby-specific Drop class-name string output
            #   :self_environment_shadowing - optional `self` lookup compatibility behavior
            #   :binary_data            - Raw bytes that JSON cannot transport safely
            #   :shopify_*              - Shopify platform/theme extensions
            config.missing_features = [
              :runtime_drops,
              :ruby_types,
              :ruby_drops,
              :drop_class_output,
              :self_environment_shadowing,
              :binary_data,
              :template_factory,
              :shopify_filters,
              :shopify_includes,
              :shopify_blank,
              :shopify_error_handling,
              :shopify_error_format,
              :shopify_string_access,
              :strict2_blank_body_errors,
            ]
          end

          # ERROR MODES
          # -----------
          # Default to :strict2 (the modern Liquid 5.12+ parser) when the spec
          # doesn't request a specific mode. This default is sent to your subprocess
          # in the compile request's options.error_mode field.
          #
          # Legacy modes (:strict, :lax, :raise) exist for backwards compatibility
          # with older Liquid versions or Shopify production but are NOT recommended
          # for new implementations unless you need that compatibility. Let specs
          # targeting those modes be skipped.
          LiquidSpec.compile do |ctx, source, options|
            options[:error_mode] ||= :strict2
            ctx[:adapter].compile(source, options)
          end

          # Render errors are raised by default (strict_errors: true). Only specs
          # that opt into render_errors set strict_errors to false.
          LiquidSpec.render do |ctx, template_id, assigns, options|
            ctx[:adapter].render(template_id, assigns, options)
          end
        RUBY

        def self.agents_md_content(filename, json_rpc: false)
          <<~MARKDOWN
            # Implementing a Liquid Template Engine

            You are building a production-grade [Liquid](https://shopify.github.io/liquid/)
            template engine. This directory is wired to **liquid-spec**, which defines what
            "correct" means: 7,000+ executable specs, ordered by complexity from trivial
            passthrough (score 0) to full production compatibility (score 1000). Your job is
            to climb that ramp. The suite is the definition of done — when it is green, you
            have a real Liquid implementation.

            #{json_rpc ? non_ruby_notice : ""}
            ## Which adapter file?

            - **Implementing in Ruby?** Use `liquid_adapter.rb`. It calls your code directly
              (see "The Adapter Pattern" below).
            - **Implementing in ANY other language** (Rust, Go, Python, Node, Zig, ...)? Use
              `liquid_adapter_jsonrpc.rb`. It talks to your engine over a simple JSON-RPC
              protocol on stdin/stdout — run `liquid-spec docs json-rpc-protocol` for the
              full protocol.

            ## The loop (follow this exactly)

            ```bash
            liquid-spec run #{filename}
            ```

            1. Run the suite. Specs execute in complexity order, so the FIRST failure is
               always the right thing to work on. Do not skip ahead: later features depend
               on earlier ones, and the ramp is designed so each fix is small.
            2. Read the failing spec completely — template, environment, expected, got, and
               especially the `hint:`. Hints are written by implementers for implementers;
               they usually state the exact rule you are missing.
            3. If the behavior is unclear, read the relevant guide first
               (see "Documentation" below) — minutes of reading routinely save hours of
               guessing. Reproduce interactively before coding:
               ```bash
               cat <<'EOF' | liquid-spec eval #{filename} --compare
               name: scratch_assign
               template: "{% assign x = 1 %}{{ x }}"
               expected: "1"
               complexity: 40
               hint: "Assign stores a value in the current scope."
               EOF

               cat <<'EOF' | liquid-spec eval #{filename} --compare
               name: scratch_array_size
               template: "{{ x | size }}"
               environment:
                 x: [1, 2, 3]
               expected: "3"
               complexity: 40
               hint: "The size filter returns array length."
               EOF
               ```
               `--compare` shows the reference implementation's output next to yours.
            4. Implement the smallest change that makes the spec pass for the RIGHT reason.
            5. Re-run. Every previously-passing spec must still pass — a fix that breaks
               earlier specs is wrong, not a tradeoff.
            6. Judge progress by **`Complexity level cleared`**, not the raw pass count. A
               partial implementation accidentally passes many later specs whose expected
               output happens to be empty; complexity-reached is the honest meter.

            ## Hard rules

            1. **Never special-case a spec.** No matching on spec names, template strings,
               or expected outputs. Every fix must implement the general rule the spec is
               an instance of. (Passing a spec without implementing its rule will break on
               the next spec of the same family anyway.)
            2. **The expected output is recorded reference behavior — conform, don't
               argue.** When an expectation looks insane, it is usually a real, documented
               quirk: read the spec's hint, then `QUIRKS.md` in the liquid-spec repository.
               Liquid has many deliberate oddities (they are what "compatible" means).
            3. **Use `missing_features` honestly.** It exists for surface you are
               deliberately not building — `shopify_*` features (needed only to render
               Shopify themes) and legacy parse modes are the legitimate entries. It is
               not for dodging hard specs; every entry is debt that keeps specs from
               running.
            4. **Never delete or edit specs to make them pass.**
            5. **Keep your engine's behavior in ONE place per rule.** If you find yourself
               patching the same symptom at several call sites, you modeled the rule at the
               wrong layer.

            ## Error modes: build for strict2 (read this before complexity 100)

            **Target `:strict2` from the start** — it is the modern parser contract
            (Liquid 5.12+) and the adapters generated here default to it. The legacy
            parse modes exist only for compatibility:

            - `:strict` / `:lax` — implement these ONLY if compatibility with older
              Liquid or Shopify production behavior matters to you. Until then, let the
              specs that target those modes skip; do not contort your parser around
              them. (One example of what lives there: lax mode suppresses the error
              TEXT of blank-bodied tags — a backwards-compatibility quirk with its own
              spec suite whose hints explain it if and when you take it on.)
            - `shopify_*` feature-gated specs (Shopify platform filters and tags)
              matter only if you want to render Shopify themes. Declare them in
              `missing_features` until that is a goal.

            Render-time error rules apply in every mode — get these right early:

            - Undefined variables are NOT errors: they render as empty string and
              lookups on them return nil. (`{{ missing }}` → ``, `{{ missing.a.b }}` → ``.)
            - Real runtime errors (bad comparison, invalid filter argument, ...) render
              inline as `Liquid error (line N): <message>` when the spec sets
              `render_errors: true`; otherwise rendering raises. Match the message
              TEXT — specs pin it.
            - Parse errors render as `Liquid syntax error (line N): <message>` or
              raise; specs that expect them say so.
            - When a failing spec's expected output surprises you, the rule you are
              missing is almost always stated in its `hint:` — the suite is designed
              to teach the semantics just-in-time, in complexity order. Read the hint
              before reading anything else.

            ## Documentation

            All implementer guides are served by the CLI — `liquid-spec docs` lists
            them, `liquid-spec docs <name>` prints one (works from this directory; no
            paths or checkouts needed):

            | `liquid-spec docs ...` | What it explains |
            |---|---|
            | `complexity` | the full ramp: what to build at every score |
            | `grammar` | the syntax: tags, output, expressions, literals |
            | `parsing` | tokenizer/parser structure, error modes, whitespace control |
            | `core-abstractions` | truthiness, nil, coercion, drops, special keys |
            | `filters` | filter dispatch, arguments, coercion rules |
            | `scopes` | variable scoping: assign, capture, loops, includes |
            | `for-loops` | for/forloop/offset/limit/else, iteration protocol |
            | `interrupts` | break/continue, incl. across include boundaries |
            | `partials` | include vs render semantics |
            | `filesystem` | partial lookup, extensions, path rules |
            | `cycle`, `tablerow` | the stateful tags |
            | `ruby-quirks` | behaviors inherited from Ruby's semantics |
            | `json-rpc-protocol` | the non-Ruby adapter protocol |

            Also read `QUIRKS.md` in the liquid-spec repository when an expectation looks
            wrong — if the quirk is documented there, it is intentional.

            ## Architecture advice for a fresh implementation

            Start boring: tokenizer → parser → node tree → tree-walking renderer with a
            scope stack. Do not build a compiler or VM first — correctness across 7,000+
            specs is the hard part, and a simple renderer is much easier to make correct.
            Two things ARE worth designing in from day one, because they weave through
            everything and are painful to retrofit:

            1. **Error plumbing** — every node needs a line number and a uniform way to
               either emit `Liquid error (line N): ...` text or raise, per the error model
               above.
            2. **The value model** — one module that answers "is this truthy?",
               "how does this print?", "how does this coerce to a number?",
               "how does this iterate?" for every type. Most spec failures at
               complexity 150+ are inconsistencies between call sites that answered those
               questions independently.

            ### Implementation phases

            | Phase | Complexity | Features |
            |-------|------------|----------|
            | 0 | 0-20 | Pipeline, static text, object tags, literal output, nil-as-empty |
            | 1 | 30-50 | Variables, missing variables, simple filters, assign |
            | 2 | 55-100 | Basic conditionals, loops, comparisons, capture/case/forloop basics |
            | 3 | 105-180 | Standard filters/tags, comments/raw, whitespace control, interrupts, collection helpers |
            | 4 | 190-400 | Partials/filesystem, scope interactions, generated compatibility breadth |
            | 5 | 500-900 | Parser error matrices, error-model matrix, recursion/deep nesting, security/date/time/Ruby quirks |
            | 6 | 1000 | Production recordings and unscored mature-compatibility checks |
            #{json_rpc ? json_rpc_section(filename) : ruby_adapter_section}

            ## Local specs for development

            Any `.yml` under a local `specs/` directory is picked up automatically — use it
            to isolate a behavior before fixing it, and as regression tests afterwards:

            ```yaml
            ---
            specs:
            - name: my_assign_test
              template: "{% assign x = 'hello' %}{{ x }}"
              expected: "hello"
              complexity: 50
              hint: "What rule this checks, for your future self"
            ```

            Specs support `environment:` (variables), `filesystem:` (partials),
            `error_mode:`, `render_errors: true` (required whenever `expected` contains
            error text), and `errors:` for parse-error expectations — copy shapes from the
            built-in suites.

            ## Command reference

            ```bash
            liquid-spec run #{filename}                 # the loop
            liquid-spec run #{filename} -n case         # only specs matching a pattern
            liquid-spec run #{filename} -n /^case_b/    # regex form
            liquid-spec run #{filename} -s basics       # one suite
            liquid-spec run #{filename} --list-suites   # what suites exist
            liquid-spec run #{filename} -l              # list specs without running
            liquid-spec run #{filename} --list-passed   # audit accidental passes
            liquid-spec run #{filename} --json          # machine-readable results
            cat spec.yml | liquid-spec eval #{filename} --compare           # one-off YAML spec
            liquid-spec docs complexity                 # any guide from the table above
            ```

            ## Reference

            - [Liquid documentation](https://shopify.github.io/liquid/) (user-facing; the
              specs and `liquid-spec docs` guides are the implementer-facing truth)
            - [liquid-spec repository](https://github.com/Shopify/liquid-spec)
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
              #   :error_mode - :strict2 (default), :strict, :lax, or :raise
              #   :line_numbers - true/false
              #   :file_system - for include/render tags
              options[:error_mode] ||= :strict2
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

        def self.non_ruby_notice
          <<~MARKDOWN
            ## Not Using Ruby?

            **This adapter uses JSON-RPC** to communicate with your Liquid implementation over stdin/stdout.
            You can implement your Liquid engine in **any language** (Rust, Go, Python, Node.js, etc.).

            See `docs/json-rpc-protocol.md` for the full protocol specification, or check the comments
            in your adapter file for a quick reference.

            **Key points:**
            - Your server reads JSON-RPC requests from stdin, writes responses to stdout
            - Debug output goes to stderr (liquid-spec forwards it to the terminal)
            - Implement 4 methods: `initialize`, `compile`, `render`, `quit`

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

            1. **initialize** - liquid-spec sends version info, your server responds with informational metadata/features
            2. **compile** - Parse a template, return a template_id
            3. **render** - Render a compiled template with variables
            4. **quit** - Notification to exit cleanly (no response expected)

            ### Debug Output

            Your server can write debug information to **stderr** at any time. liquid-spec forwards
            all stderr output to the terminal, prefixed with your server name:

            ```
            [my-liquid-server] Compiling template: {{ x | upcase }}
            [my-liquid-server] Render complete in 0.5ms
            ```

            This is useful for debugging your implementation without interfering with the JSON-RPC
            protocol (which uses stdout). Write to stderr liberally during development.

            **Important:** The default timeout is 2 seconds per request. If your server doesn't
            respond within 2 seconds, liquid-spec will fail with a timeout error.

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
                // features is informational. Spec selection is configured in
                // the Ruby adapter's config.missing_features list.
                respond(id, { version: '1.0', features: [] });
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
              "options": {"error_mode": "strict2"},
              "filesystem": {"snippet.liquid": "Hello"}
            }}

            // Success response
            {"jsonrpc":"2.0","id":1,"result":{"template_id":"abc123"}}

            // Parse error response (preferred)
            {"jsonrpc":"2.0","id":1,"result":{"template_id":null,"error":{"type":"parse_error","message":"Unknown tag"}}}

            // Legacy parse error response also accepted
            {"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"Parse error","data":{"type":"parse_error","message":"Unknown tag"}}}
            ```

            ### Render Request/Response

            ```json
            // Request
            {"jsonrpc":"2.0","id":2,"method":"render","params":{
              "template_id": "abc123",
              "environment": {"x": "hello", "items": [1,2,3]},
              "options": {"strict_errors": true}
            }}

            // Success response
            {"jsonrpc":"2.0","id":2,"result":{"output":"HELLO"}}

            // Render error response with strict_errors=true (preferred)
            {"jsonrpc":"2.0","id":2,"result":{"output":null,"error":{"type":"render_error","message":"undefined variable"}}}

            // Inline render error response with strict_errors=false
            {"jsonrpc":"2.0","id":2,"result":{"output":"Liquid error: undefined variable","errors":[{"type":"render_error","message":"undefined variable"}]}}

            // Legacy render error response also accepted
            {"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"Render error","data":{"type":"render_error","message":"undefined variable"}}}
            ```

            ### Error Codes

            | Code | Meaning |
            |------|---------|
            | -32000 | Legacy parse error (accepted; prefer result.error) |
            | -32001 | Legacy render error (accepted; prefer result.error) |
            | -32700 | JSON parse error |
            | -32600 | Invalid request |
            | -32601 | Method not found |

            See the adapter file (`#{filename}`) for the complete protocol specification.
          MARKDOWN
        end

        LIQUID_RUBY_TEMPLATE = <<~RUBY
          #!/usr/bin/env ruby
          # frozen_string_literal: true

          # Liquid Spec Adapter for Shopify/liquid
          #
          # Run directly:  ./%<filename>s                  # re-launches via liquid-spec
          # Run directly:  ./%<filename>s -n assign        # filter specs by name
          # Or run via:    liquid-spec run %<filename>s
          #
          # Not using Ruby? liquid-spec can drive an implementation in any language
          # (Rust, Go, Python, Node.js, ...) over JSON-RPC. Generate a JSON-RPC
          # adapter instead:
          #
          #   liquid-spec init --jsonrpc my_adapter.rb

          # When executed directly, re-launch through liquid-spec on this file.
          # When loaded by liquid-spec, this guard is skipped and the adapter DSL runs.
          if __FILE__ == $PROGRAM_NAME
            cmd = ["liquid-spec", "run", __FILE__, *ARGV]
            cmd = ["bundle", "exec"] + cmd if File.exist?("Gemfile")
            exec(*cmd)
          end

          require "liquid/spec/cli/adapter_dsl"
          require "liquid"

          LiquidSpec.setup do |ctx|
            # ctx can store adapter state like custom environments
          end

          LiquidSpec.configure do |config|
            config.suite = :liquid_ruby
          end

          # ERROR MODES
          # -----------
          # Default to :strict2 (the modern Liquid 5.12+ parser) when the spec
          # doesn't request a specific mode.
          #
          # Legacy modes (:strict, :lax, :raise) exist for backwards compatibility
          # with older Liquid versions or Shopify production but are NOT recommended
          # for new implementations unless you need that compatibility.
          LiquidSpec.compile do |ctx, source, options|
            options[:error_mode] ||= :strict2
            Liquid::Template.parse(source, **options)
          end

          # Render errors are raised by default (strict_errors: true). Only specs
          # that opt into render_errors set strict_errors to false.
          LiquidSpec.render do |ctx, template, assigns, options|
            context = Liquid::Context.build(
              static_environments: assigns,
              registers: Liquid::Registers.new(options[:registers] || {}),
              rethrow_errors: options[:strict_errors]
            )
            template.render(context)
          end
        RUBY

        def self.run(args)
          filename = args.find { |a| !a.start_with?("-") }

          # Check for template type flags
          # --json, --jsonrpc, and --json-rpc (plus -j) all select the JSON-RPC adapter
          json_rpc_flag = args.intersect?(%w[--json-rpc --jsonrpc --json -j])
          liquid_ruby_flag = args.intersect?(%w[--liquid-ruby -l])

          # A type flag without a filename selects single-file mode with the
          # canonical filename for that type (previously the flag was
          # silently ignored and both adapters were generated).
          filename ||= "liquid_adapter_jsonrpc.rb" if json_rpc_flag
          filename ||= "liquid_adapter.rb" if liquid_ruby_flag

          if filename
            # Single-file mode: generate one adapter, type determined by flags
            template_type = if json_rpc_flag
              :json_rpc
            elsif liquid_ruby_flag
              :liquid_ruby
            else
              :basic
            end
            generate_adapter(filename, template_type)
            create_agents_md(filename, json_rpc: template_type == :json_rpc)
            print_next_steps(filename, template_type)
          else
            # Default mode: generate both a Ruby adapter and a JSON-RPC adapter
            puts "Generating both adapters..."
            puts ""
            generate_adapter("liquid_adapter.rb", :basic)
            generate_adapter("liquid_adapter_jsonrpc.rb", :json_rpc)

            # Create AGENTS.md once (covers both adapters)
            create_agents_md("liquid_adapter.rb", json_rpc: false)

            puts ""
            puts "Next steps:"
            puts "  Ruby implementation:"
            puts "    1. Edit liquid_adapter.rb to implement compile and render"
            puts "    2. Run: ./liquid_adapter.rb   (or: liquid-spec liquid_adapter.rb)"
            puts ""
            puts "  Any language (JSON-RPC):"
            puts "    1. Edit DEFAULT_COMMAND in liquid_adapter_jsonrpc.rb"
            puts "    2. Implement the JSON-RPC protocol in your server (see comments)"
            puts "    3. Run: ./liquid_adapter_jsonrpc.rb   (or: liquid-spec liquid_adapter_jsonrpc.rb)"
            puts ""
            puts "If using an AI agent, point it at AGENTS.md for implementation guidance."
          end
        end

        def self.generate_adapter(filename, template_type)
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
          File.chmod(0o755, filename)
          puts "Created #{filename} (executable)"
        end

        def self.create_agents_md(filename, json_rpc:)
          agents_filename = "AGENTS.md"
          if File.exist?(agents_filename)
            puts "AGENTS.md already exists, skipping"
          else
            agents_md = agents_md_content(filename, json_rpc: json_rpc)
            File.write(agents_filename, agents_md)
            puts "Created AGENTS.md"
          end
        end

        def self.print_next_steps(filename, template_type)
          puts ""
          case template_type
          when :json_rpc
            puts "Next steps:"
            puts "  1. Edit DEFAULT_COMMAND in #{filename} to point to your Liquid server"
            puts "  2. Implement the JSON-RPC protocol in your server (see comments in file)"
            puts "  3. Run: ./#{filename}"
            puts "     Or:  liquid-spec #{filename} --command='./your-server'"
          else
            puts "Next steps:"
            puts "  1. Edit #{filename} to implement compile and render"
            puts "  2. Run: ./#{filename}   (or: liquid-spec #{filename})"
          end

          puts ""
          puts "If using an AI agent, point it at AGENTS.md for implementation guidance."
        end
      end
    end
  end
end
