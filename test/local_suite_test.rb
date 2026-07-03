# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

# Local suite discovery: projects can ship their own suites under
# ./specs/<name>/suite.yml and select them with -s <name>.
class LocalSuiteTest < Minitest::Test
  def with_local_suite
    Dir.mktmpdir do |dir|
      suite_dir = File.join(dir, "specs", "my_partials")
      FileUtils.mkdir_p(suite_dir)
      File.write(File.join(suite_dir, "suite.yml"), <<~YML)
        name: "My Partials"
        default: false
        timings: true
      YML
      File.write(File.join(suite_dir, "specs.yml"), <<~YML)
        specs:
          - name: bench_local_example
            template: "{{ 'hi' | upcase }}"
            expected: "HI"
      YML
      prev = ENV["LIQUID_SPEC_LOCAL_DIR"]
      ENV["LIQUID_SPEC_LOCAL_DIR"] = dir
      Liquid::Spec::Suite.reset!
      yield
    ensure
      ENV["LIQUID_SPEC_LOCAL_DIR"] = prev
      Liquid::Spec::Suite.reset!
    end
  end

  def test_local_suite_is_discovered
    with_local_suite do
      suite = Liquid::Spec::Suite.find(:my_partials)
      refute_nil suite, "local suite should be discoverable by id"
      assert_equal "My Partials", suite.name
      assert suite.timings?, "timings: true should mark the suite benchmarkable"
      refute suite.default?, "default: false should keep it out of default runs"
    end
  end

  def test_local_suite_specs_load
    with_local_suite do
      suite = Liquid::Spec::Suite.find(:my_partials)
      specs = Liquid::Spec::SpecLoader.load_suite(suite)
      assert_equal ["bench_local_example"], specs.map(&:name)
    end
  end

  def test_gem_suites_still_present
    with_local_suite do
      refute_nil Liquid::Spec::Suite.find(:benchmarks)
      refute_nil Liquid::Spec::Suite.find(:basics)
    end
  end
end
