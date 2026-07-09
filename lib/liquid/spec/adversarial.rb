# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "timeout"
require "yaml"
require_relative "adapter_runner"
require_relative "spec_loader"
require_relative "suite"

module Liquid
  module Spec
    # Generated differential testing for Liquid implementations.
    #
    # Existing specs are the seed corpus. Mutators make small, attributable
    # changes to their templates, then the reference and subject adapters run
    # the same generated case. This is deliberately not coverage-guided
    # fuzzing: it is deterministic corpus mutation with a differential oracle.
    module Adversarial
      Mutation = Struct.new(:id, :description, :template, keyword_init: true)
      Case = Struct.new(:id, :parent, :spec, :mutations, :original_template, keyword_init: true)
      Outcome = Struct.new(
        :status, :output, :error_category, :error_class, :error_message,
        keyword_init: true
      )
      Finding = Struct.new(
        :case, :classification, :reference, :subject, :saved_to,
        keyword_init: true
      )
      Summary = Struct.new(
        :mode, :seed, :generated, :executed, :passed, :skipped, :findings,
        keyword_init: true
      ) do
        def success?
          findings.empty?
        end

        def to_h
          {
            mode: mode.to_s,
            seed: seed,
            generated: generated,
            executed: executed,
            passed: passed,
            failed: findings.length,
            skipped: skipped,
            failures: findings.map do |finding|
              {
                id: finding.case.id,
                parent: finding.case.parent.name,
                source_file: finding.case.parent.source_file,
                mutations: finding.case.mutations.map(&:id),
                classification: finding.classification.to_s,
                template: finding.case.spec.template,
                reference: Adversarial.outcome_to_h(finding.reference),
                subject: Adversarial.outcome_to_h(finding.subject),
                saved_to: finding.saved_to,
              }
            end,
          }
        end
      end

      module_function

      def outcome_to_h(outcome)
        {
          status: outcome.status.to_s,
          output: outcome.output,
          error_category: outcome.error_category&.to_s,
          error_class: outcome.error_class,
          error_message: outcome.error_message,
        }.compact
      end

      # Lightweight, scanner-based mutations over proven templates. Mutators
      # return all meaningful variants they can make and never alter assigns or
      # filesystem inputs. The reference implementation supplies expectations.
      module Mutators
        class Base
          attr_reader :id, :description, :tags

          def initialize(id, description, *tags)
            @id = id
            @description = description
            @tags = tags.map(&:to_s)
          end

          def mutation(template, changed, suffix = nil)
            return if changed == template
            Mutation.new(
              id: suffix ? "#{id}_#{suffix}" : id,
              description: description,
              template: changed,
            )
          end

          def replace_first(template, pattern, replacement)
            template.sub(pattern, replacement)
          end

          def compact(mutations)
            seen = {}
            mutations.compact.select { |entry| !seen.key?(entry.template) && (seen[entry.template] = true) }
          end
        end

        class TextBoundary < Base
          def initialize
            super("text_boundary", "Compose the template with Unicode and newline text", "text", "unicode", "whitespace")
          end

          def variants(template)
            compact([
              mutation(template, "α#{template}ω", "unicode"),
              mutation(template, "\n#{template}\n", "newlines"),
            ])
          end
        end

        class DelimiterWhitespace < Base
          def initialize
            super("delimiter_whitespace", "Vary whitespace at Liquid delimiter boundaries", "whitespace", "parser")
          end

          def variants(template)
            variants = []
            variants << mutation(template, template.sub(/\{\{[ \t]*/, "{{\n"), "output_open") if template.include?("{{")
            variants << mutation(template, template.sub(/[ \t]*\}\}/, "\n}}"), "output_close") if template.include?("}}")
            variants << mutation(template, template.sub(/\{%[ \t]*/, "{%\n"), "tag_open") if template.include?("{%")
            variants << mutation(template, template.sub(/[ \t]*%\}/, "\n%}"), "tag_close") if template.include?("%}")
            compact(variants)
          end
        end

        class TrimMarkers < Base
          def initialize
            super("trim_markers", "Toggle Liquid whitespace-control markers", "whitespace", "parser")
          end

          def variants(template)
            variants = []
            if template.match?(/\{\{(?!-)/)
              variants << mutation(template, template.sub("{{", "{{-"), "output_open")
            elsif template.include?("{{-")
              variants << mutation(template, template.sub("{{-", "{{"), "output_open")
            end
            if template.match?(/(?<!-)\}\}/)
              variants << mutation(template, template.sub(/(?<!-)\}\}/, "-}}"), "output_close")
            elsif template.include?("-}}")
              variants << mutation(template, template.sub("-}}", "}}"), "output_close")
            end
            if template.match?(/\{%(?!-)/)
              variants << mutation(template, template.sub("{%", "{%-"), "tag_open")
            elsif template.include?("{%-")
              variants << mutation(template, template.sub("{%-", "{%"), "tag_open")
            end
            if template.match?(/(?<!-)%\}/)
              variants << mutation(template, template.sub(/(?<!-)%\}/, "-%}"), "tag_close")
            elsif template.include?("-%}")
              variants << mutation(template, template.sub("-%}", "%}"), "tag_close")
            end
            compact(variants)
          end
        end

        class Literals < Base
          QUOTED = /(['"])(.*?)\1/m
          NUMBER = /(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])/

          def initialize
            super("literal_boundary", "Replace a literal with a boundary value", "literal", "value")
          end

          def variants(template)
            variants = []
            if (match = template.match(QUOTED))
              quote = match[1]
              ["", " ", "0", "é"].each_with_index do |value, index|
                replacement = "#{quote}#{value}#{quote}"
                variants << mutation(template, template.sub(QUOTED, replacement), "string_#{index}")
              end
            end
            if template.match?(NUMBER)
              ["0", "-1", "2147483648"].each_with_index do |value, index|
                variants << mutation(template, template.sub(NUMBER, value), "number_#{index}")
              end
            end
            compact(variants)
          end
        end

        class Lookups < Base
          DOT_LOOKUP = /\b([A-Za-z_][\w-]*)\.([A-Za-z_][\w-]*)\b/
          OUTPUT_NAME = /(\{\{[-]?\s*)([A-Za-z_][\w-]*)(?=[.\[\s|}]|$)/

          def initialize
            super("lookup_boundary", "Vary property syntax and missing-variable lookup", "lookup", "variable")
          end

          def variants(template)
            variants = []
            if (match = template.match(DOT_LOOKUP))
              bracket = "#{match[1]}['#{match[2]}']"
              variants << mutation(template, template.sub(DOT_LOOKUP, bracket), "bracket")
            end
            if template.match?(OUTPUT_NAME)
              variants << mutation(
                template,
                template.sub(OUTPUT_NAME) { "#{$1}__liquid_spec_missing__" },
                "missing"
              )
            end
            compact(variants)
          end
        end

        class Filters < Base
          FILTER = /\s*\|\s*([A-Za-z_][\w-]*)(?:\s*:\s*([^|}]*))?/

          def initialize
            super("filter_boundary", "Vary filter dispatch and argument structure", "filter")
          end

          def variants(template)
            return [] unless (match = template.match(FILTER))

            segment = match[0]
            compact([
              mutation(template, template.sub(FILTER, ""), "remove"),
              mutation(template, template.sub(FILTER, "#{segment}#{segment}"), "duplicate"),
              mutation(template, template.sub(match[1], "__liquid_spec_unknown_filter__"), "unknown"),
              mutation(template, template.sub(FILTER, "#{segment.sub(/\s*\z/, "")}, nil"), "extra_argument"),
            ])
          end
        end

        class Conditionals < Base
          OPERATOR = /\s(==|!=|>=|<=|>|<|contains)\s/

          def initialize
            super("conditional_boundary", "Vary conditional tags and comparison operators", "if", "unless", "condition")
          end

          def variants(template)
            variants = []
            if template.include?("{% if ") && template.include?("{% endif %}")
              changed = template.sub("{% if ", "{% unless ").sub("{% endif %}", "{% endunless %}")
              variants << mutation(template, changed, "if_to_unless")
            elsif template.include?("{% unless ") && template.include?("{% endunless %}")
              changed = template.sub("{% unless ", "{% if ").sub("{% endunless %}", "{% endif %}")
              variants << mutation(template, changed, "unless_to_if")
            end
            if (match = template.match(OPERATOR))
              %w[== != > < contains].each do |operator|
                variants << mutation(template, template.sub(OPERATOR, " #{operator} "), "operator_#{operator.gsub(/\W/, "x")}") unless operator == match[1]
              end
            end
            compact(variants)
          end
        end

        class Loops < Base
          FOR_OPEN = /\{%\s*for\s+([A-Za-z_][\w-]*)\s+in\s+([^%]+?)\s*%\}/m

          def initialize
            super("for_boundary", "Vary for-loop collection and bounds", "for", "for_loop", "loop")
          end

          def variants(template)
            return [] unless (match = template.match(FOR_OPEN))

            variable = match[1]
            expression = match[2].strip
            base = "{% for #{variable} in #{expression}"
            compact([
              mutation(template, template.sub(FOR_OPEN, "#{base} limit: 0 %}"), "limit_zero"),
              mutation(template, template.sub(FOR_OPEN, "#{base} limit: 1 %}"), "limit_one"),
              mutation(template, template.sub(FOR_OPEN, "#{base} offset: 1 %}"), "offset_one"),
              mutation(template, template.sub(FOR_OPEN, "#{base} reversed %}"), "reversed"),
              mutation(template, template.sub(FOR_OPEN, "{% for #{variable} in __liquid_spec_missing__ %}"), "missing_collection"),
            ])
          end
        end

        class TagStructure < Base
          BLOCKS = %w[if unless for case capture comment raw tablerow].freeze

          def initialize
            super("tag_structure", "Damage a block boundary to exercise parser recovery", "parser", "error")
          end

          def variants(template)
            variants = []
            BLOCKS.each do |tag|
              pattern = /\{%\s*end#{tag}\s*%\}/
              next unless template.match?(pattern)

              variants << mutation(template, template.sub(pattern, ""), "missing_end#{tag}")
              variants << mutation(template, template.sub(pattern, "{% end__liquid_spec_wrong__ %}"), "wrong_end#{tag}")
              break
            end
            compact(variants)
          end
        end

        class OpaqueBodies < Base
          def initialize
            super("opaque_body", "Put delimiter-looking text inside raw or comment bodies", "raw", "comment", "parser")
          end

          def variants(template)
            variants = []
            %w[raw comment].each do |tag|
              pattern = /(\{%\s*#{tag}\s*%\})(.*?)(\{%\s*end#{tag}\s*%\})/m
              next unless template.match?(pattern)

              changed = template.sub(pattern) { "#{$1}{{ x }}{% if true %}#{$2}#{$3}" }
              variants << mutation(template, changed, tag)
            end
            compact(variants)
          end
        end

        class StructuralStress < Base
          def initialize(depth:, repetitions:)
            super("structural_stress", "Increase valid template size and nesting", "stress", "depth")
            @depth = depth
            @repetitions = repetitions
          end

          def variants(template)
            nested = ("{% if true %}" * @depth) + template + ("{% endif %}" * @depth)
            repeated = template * @repetitions
            compact([
              mutation(template, nested, "if_depth_#{@depth}"),
              mutation(template, repeated, "repeat_#{@repetitions}"),
            ])
          end
        end

        def self.default
          [
            TextBoundary.new,
            DelimiterWhitespace.new,
            TrimMarkers.new,
            Literals.new,
            Lookups.new,
            Filters.new,
            Conditionals.new,
            Loops.new,
            TagStructure.new,
            OpaqueBodies.new,
          ]
        end
      end

      class SeedLoader
        def initialize(suite: :all, around: nil, name: nil, features: [], seed: 1)
          @suite = suite
          @around = around
          @name = name
          @features = Array(features).map(&:to_sym)
          @seed = seed
        end

        def load
          specs = SpecLoader.load_all(suite: @suite, filter: @name, random_seed: @seed)
          specs = specs.select { |spec| around?(spec) } if @around
          specs = specs.select { |spec| (@features - spec.features).empty? } if @features.any?
          specs.sort_by { |spec| [spec.complexity || 1000, spec.name.to_s, spec.source_file.to_s] }
        end

        private

        def around?(spec)
          needle = normalize(@around)
          haystack = normalize([
            spec.name,
            spec.source_file,
            spec.template,
            spec.hint,
            spec.doc,
            spec.features.join(" "),
          ].compact.join(" "))
          needle.split.all? { |token| haystack.include?(token) }
        end

        def normalize(value)
          value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
        end
      end

      class Generator
        def initialize(mutators: Mutators.default, seed: 1)
          @mutators = mutators
          @seed = seed
          @random = Random.new(seed)
        end

        def generate(seeds, mode:, limit:, rounds: nil)
          return generate_fuzz(seeds, limit: limit, rounds: rounds || limit * 5) if mode == :fuzz

          selected_mutators = if mode == :stress
            @mutators.select { |mutator| mutator.tags.include?("stress") }
          else
            @mutators.reject { |mutator| mutator.tags.include?("stress") }
          end

          generated = []
          seeds.each do |parent|
            selected_mutators.each do |mutator|
              mutator.variants(parent.template).each do |mutation|
                generated << build_case(parent, [mutation])
                return generated if generated.length >= limit
              end
            end
          end
          generated
        end

        private

        def generate_fuzz(seeds, limit:, rounds:)
          return [] if seeds.empty?

          generated = []
          seen = {}
          rounds.times do
            parent = seeds[@random.rand(seeds.length)]
            template = parent.template
            mutations = []

            @random.rand(1..3).times do
              candidates = @mutators.flat_map do |mutator|
                mutator.variants(template).map { |mutation| [mutator, mutation] }
              end
              break if candidates.empty?

              _mutator, mutation = candidates[@random.rand(candidates.length)]
              template = mutation.template
              mutations << mutation
            end

            next if mutations.empty?
            digest = Digest::SHA256.hexdigest("#{parent.name}\0#{template}")[0, 12]
            next if seen[digest]

            seen[digest] = true
            generated << build_case(parent, mutations)
            break if generated.length >= limit
          end
          generated
        end

        def build_case(parent, mutations)
          template = mutations.last.template
          digest = Digest::SHA256.hexdigest("#{parent.name}\0#{mutations.map(&:id).join("+")}\0#{template}")[0, 12]
          generated_spec = LazySpec.new(
            name: "adversarial_#{sanitize(parent.name)}_#{digest}",
            template: template,
            expected: nil,
            errors: {},
            hint: "Generated from #{parent.name} with #{mutations.map(&:id).join(", ")}",
            doc: parent.doc,
            complexity: parent.complexity,
            error_mode: parent.error_modes,
            render_errors: parent.render_errors,
            features: parent.features,
            source_file: "generated from #{parent.location}",
            raw_environment: parent.raw_environment,
            raw_filesystem: parent.raw_filesystem,
            raw_template_factory: parent.raw_template_factory,
            raw_resource_limits: parent.raw_resource_limits,
            source_required_options: parent.source_required_options,
          )
          Case.new(
            id: digest,
            parent: parent,
            spec: generated_spec,
            mutations: mutations,
            original_template: parent.template,
          )
        end

        def sanitize(name)
          name.to_s.downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_+/, "")[0, 60]
        end
      end

      class Comparator
        def compare(reference, subject)
          return :reference_inconclusive if [:timeout, :crash, :adapter_error, :skipped].include?(reference.status)
          return :subject_timeout if subject.status == :timeout
          return :subject_crash if subject.status == :crash
          return :subject_adapter_error if subject.status == :adapter_error
          return :subject_skipped if subject.status == :skipped

          if reference.status == :ok && subject.status == :ok
            return nil if reference.output == subject.output
            return :output_mismatch
          end

          return :reference_error_subject_ok if reference.status == :error && subject.status == :ok
          return :reference_ok_subject_error if reference.status == :ok && subject.status == :error

          if reference.status == :error && subject.status == :error
            return nil if reference.error_category == subject.error_category
            return :error_category_mismatch
          end

          :outcome_mismatch
        end
      end

      class Oracle
        attr_reader :subject, :reference

        def initialize(subject:, reference:, command: nil, timeout: 2)
          @subject = runner?(subject) ? subject : load_runner(subject, command: command, timeout: timeout)
          @reference = runner?(reference) ? reference : load_runner(reference, command: nil, timeout: timeout)
          @timeout = timeout.to_f
        end

        def run_pair(spec)
          [run_one(reference, spec), run_one(subject, spec)]
        end

        def shutdown
          [subject, reference].each do |runner|
            adapter = runner.respond_to?(:ctx) ? runner.ctx[:adapter] : nil
            adapter.shutdown if adapter&.respond_to?(:shutdown)
          rescue IOError, Errno::EPIPE
            nil
          end
        end

        private

        def runner?(value)
          value.respond_to?(:run) && value.respond_to?(:ensure_setup!)
        end

        def load_runner(path, command:, timeout:)
          raise ArgumentError, "Adapter file not found: #{path}" unless path && File.exist?(path)

          runner = AdapterRunner.new.load_dsl(path)
          LiquidSpec.cli_options = { command: command, timeout: timeout }.compact
          runner.ensure_setup!
          runner
        end

        def run_one(runner, spec)
          result = nil
          Timeout.timeout(@timeout) do
            run_result = runner.run([spec]) { |entry| result = entry }
            result ||= run_result.results.first
          end
          normalize(result)
        rescue Timeout::Error => error
          Outcome.new(status: :timeout, error_category: :timeout, error_class: error.class.name, error_message: error.message)
        rescue SystemExit, SignalException
          raise
        rescue Exception => error
          category = error.message.match?(/closed stdout|exited|signal/i) ? :crash : :adapter
          Outcome.new(
            status: category == :crash ? :crash : :adapter_error,
            error_category: category,
            error_class: error.class.name,
            error_message: error.message,
          )
        end

        def normalize(result)
          return Outcome.new(status: :adapter_error, error_category: :adapter, error_message: "adapter returned no result") unless result
          return Outcome.new(status: :skipped, error_category: :skipped, error_message: result.reason) if result.skipped?
          return Outcome.new(status: :ok, output: result.output.to_s) if result.passed?

          message = result.output.to_s
          error_class = message[/\A([^:]+(?:Error|Exception)):/, 1]
          category = classify_error(message)
          Outcome.new(
            status: [:timeout, :crash].include?(category) ? category : :error,
            error_category: category,
            error_class: error_class,
            error_message: message,
          )
        end

        def classify_error(message)
          case message
          when /timeout|timed out/i then :timeout
          when /closed stdout|subprocess.*(?:exited|signal)|segmentation|abort/i then :crash
          when /unknown tag/i then :unknown_tag
          when /unknown filter/i then :unknown_filter
          when /syntax|parse error|parser/i then :syntax
          when /render|argument|zero.?division|undefined/i then :render
          else :unknown
          end
        end
      end

      class Minimizer
        def initialize(budget: 40)
          @budget = budget
        end

        # Best-effort delta debugging. It returns a smaller reproducer, not a
        # promise of global minimality.
        def minimize(template, &interesting)
          candidate = template.dup
          attempts = 0
          granularity = 2

          while candidate.length > 1 && attempts < @budget
            chunk_size = (candidate.length.to_f / granularity).ceil
            reduced = false

            granularity.times do |index|
              start = index * chunk_size
              break if start >= candidate.length

              proposal = candidate[0...start].to_s + candidate[(start + chunk_size)..].to_s
              next if proposal.empty?

              attempts += 1
              if interesting.call(proposal)
                candidate = proposal
                granularity = [granularity - 1, 2].max
                reduced = true
                break
              end
              break if attempts >= @budget
            end

            unless reduced
              break if granularity >= candidate.length
              granularity = [granularity * 2, candidate.length].min
            end
          end

          candidate
        end
      end

      class RegressionWriter
        def initialize(directory)
          @directory = directory
        end

        def write(finding)
          FileUtils.mkdir_p(@directory)
          path = File.join(@directory, "#{finding.case.spec.name}.yml")
          File.write(path, YAML.dump("specs" => [spec_hash(finding)]))
          path
        end

        private

        def spec_hash(finding)
          generated = finding.case.spec
          parent = finding.case.parent
          hash = {
            "name" => generated.name,
            "template" => generated.template,
            "complexity" => [parent.complexity || 1000, 1000].min,
            "hint" => <<~HINT.strip,
              Differential case generated from #{parent.name} (#{parent.location}).
              Mutations: #{finding.case.mutations.map(&:id).join(", ")}.
              Classification: #{finding.classification}.
            HINT
          }

          environment = portable(parent.raw_environment)
          filesystem = portable(parent.raw_filesystem)
          hash["environment"] = environment unless environment.nil? || environment.empty?
          hash["filesystem"] = filesystem unless filesystem.nil? || filesystem.empty?
          hash["features"] = parent.features.map(&:to_s) if parent.features.any?
          hash["error_mode"] = parent.error_mode.to_s if parent.error_mode

          if finding.reference.status == :ok
            hash["expected"] = finding.reference.output
          else
            error_type = finding.reference.error_category == :syntax ? "parse_error" : "render_error"
            pattern = finding.reference.error_class || finding.reference.error_category.to_s
            hash["errors"] = { error_type => [pattern] }
            hash["error_mode"] ||= "strict2"
          end
          hash
        end

        def portable(value)
          case value
          when Hash
            value.each_with_object({}) { |(key, item), copy| copy[key.to_s] = portable(item) }
          when Array
            value.map { |item| portable(item) }
          when nil, true, false, Numeric, String
            value
          else
            value.to_s
          end
        end
      end

      class Engine
        DEFAULT_REFERENCE = File.expand_path("../../../examples/liquid_ruby.rb", __dir__)

        def initialize(
          adapter:, mode: :mutate, reference: DEFAULT_REFERENCE, suite: :all,
          around: nil, name: nil, features: [], seed: 1, limit: 100,
          rounds: nil, command: nil, timeout: 2, save_dir: nil,
          minimize: false, minimize_budget: 40, depth: 32, repetitions: 32,
          subject_runner: nil, reference_runner: nil
        )
          @adapter = adapter
          @mode = mode.to_sym
          @reference_path = reference
          @suite = suite.to_sym
          @around = around
          @name = name
          @features = features
          @seed = seed.to_i
          @limit = limit.to_i
          @rounds = rounds&.to_i
          @command = command
          @timeout = timeout.to_f
          @save_dir = save_dir
          @minimize = minimize
          @minimize_budget = minimize_budget.to_i
          @depth = depth.to_i
          @repetitions = repetitions.to_i
          @subject_runner = subject_runner
          @reference_runner = reference_runner
        end

        def run
          seeds = SeedLoader.new(
            suite: @suite,
            around: @around,
            name: @name,
            features: @features,
            seed: @seed,
          ).load
          raise ArgumentError, "No seed specs matched the requested filters" if seeds.empty?

          mutators = if @mode == :stress
            [Mutators::StructuralStress.new(depth: @depth, repetitions: @repetitions)]
          else
            Mutators.default
          end
          cases = Generator.new(mutators: mutators, seed: @seed).generate(
            seeds,
            mode: @mode,
            limit: @limit,
            rounds: @rounds,
          )

          raise ArgumentError, "No mutations could be generated from the selected specs" if cases.empty?

          oracle = Oracle.new(
            subject: @subject_runner || @adapter,
            reference: @reference_runner || @reference_path,
            command: @command,
            timeout: @timeout,
          )
          comparator = Comparator.new
          writer = @save_dir ? RegressionWriter.new(@save_dir) : nil
          findings = []
          passed = 0
          skipped = 0
          executed = 0

          cases.each do |generated_case|
            reference_outcome, subject_outcome = oracle.run_pair(generated_case.spec)
            classification = comparator.compare(reference_outcome, subject_outcome)

            if classification == :reference_inconclusive || classification == :subject_skipped
              skipped += 1
              next
            end

            executed += 1
            if classification
              finding = Finding.new(
                case: generated_case,
                classification: classification,
                reference: reference_outcome,
                subject: subject_outcome,
              )
              minimize!(finding, oracle, comparator) if @minimize
              finding.saved_to = writer.write(finding) if writer
              findings << finding
            else
              passed += 1
            end
          end

          Summary.new(
            mode: @mode,
            seed: @seed,
            generated: cases.length,
            executed: executed,
            passed: passed,
            skipped: skipped,
            findings: findings,
          )
        ensure
          oracle&.shutdown
        end

        private

        def minimize!(finding, oracle, comparator)
          target_classification = finding.classification
          minimizer = Minimizer.new(budget: @minimize_budget)
          minimized = minimizer.minimize(finding.case.spec.template) do |template|
            candidate = clone_with_template(finding.case.spec, template)
            reference, subject = oracle.run_pair(candidate)
            comparator.compare(reference, subject) == target_classification
          end
          return if minimized == finding.case.spec.template

          finding.case.spec = clone_with_template(finding.case.spec, minimized)
          finding.reference, finding.subject = oracle.run_pair(finding.case.spec)
        end

        def clone_with_template(spec, template)
          LazySpec.new(
            name: spec.name,
            template: template,
            expected: nil,
            errors: {},
            hint: spec.hint,
            doc: spec.doc,
            complexity: spec.complexity,
            error_mode: spec.error_modes,
            render_errors: spec.render_errors,
            features: spec.features,
            source_file: spec.source_file,
            raw_environment: spec.raw_environment,
            raw_filesystem: spec.raw_filesystem,
            raw_template_factory: spec.raw_template_factory,
            raw_resource_limits: spec.raw_resource_limits,
            source_required_options: spec.source_required_options,
          )
        end
      end
    end
  end
end
