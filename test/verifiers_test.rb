# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "liquid/spec/verifiers"

class VerifiersTest < Minitest::Test
  def teardown
    Object.send(:remove_const, :SpecSchemaVerifier) if Object.const_defined?(:SpecSchemaVerifier)
    Object.send(:remove_const, :LaxPlacementVerifier) if Object.const_defined?(:LaxPlacementVerifier)
  end

  def test_runs_every_registered_verifier_and_keeps_advisories_non_blocking
    Dir.mktmpdir do |dir|
      write_verifier(dir, "spec_schema", "SpecSchemaVerifier", exit_code: 0)
      write_verifier(dir, "lax_placement", "LaxPlacementVerifier", exit_code: 1, advisory: true)
      output = StringIO.new
      error = StringIO.new

      status = Liquid::Spec::Verifiers.run(verifiers_dir: dir, output: output, error: error)

      assert_equal 0, status
      assert_includes output.string, "PASS  spec_schema"
      assert_includes output.string, "ADVISORY  lax_placement"
      assert_includes output.string, "All 2 checks passed"
      assert_empty error.string
    end
  end

  def test_blocking_verifier_failure_fails_the_gate
    Dir.mktmpdir do |dir|
      write_verifier(dir, "spec_schema", "SpecSchemaVerifier", exit_code: 1)
      output = StringIO.new

      status = Liquid::Spec::Verifiers.run(
        verifiers_dir: dir,
        output: output,
        error: StringIO.new
      )

      assert_equal 1, status
      assert_includes output.string, "FAIL  spec_schema"
      assert_includes output.string, "1 of 1 checks failed"
    end
  end

  def test_unregistered_verifier_is_not_silently_skipped
    Dir.mktmpdir do |dir|
      write_verifier(dir, "new_rule", "NewRuleVerifier", exit_code: 0)
      output = StringIO.new
      error = StringIO.new

      status = Liquid::Spec::Verifiers.run(verifiers_dir: dir, output: output, error: error)

      assert_equal 1, status
      assert_includes output.string, "FAIL  new_rule"
      assert_includes error.string, "is not registered"
    end
  end

  private

  def write_verifier(dir, name, module_name, exit_code:, advisory: false)
    header = advisory ? "# advisory: true\n" : ""
    File.write(
      File.join(dir, "#{name}.rb"),
      <<~RUBY
        #{header}module #{module_name}
          def self.run
            puts "ran #{name}"
            #{exit_code}
          end
        end
      RUBY
    )
  end
end
