# frozen_string_literal: true

require 'yaml'
require 'liquid'
require 'fileutils'
require 'pry-byebug'

namespace :generate do
  desc 'Generate spec tests from Shopify/liquid'
  task :dawn_specs do
    load_dawn
    copy_sections
    copy_filesystem
  end
end

def load_dawn
  if File.exist?("./tmp/dawn")
    `git -C tmp/dawn pull --depth 1 https://github.com/Shopify/dawn.git`
  else
    `git clone --depth 1 https://github.com/Shopify/dawn.git ./tmp/dawn`
  end
end

DAWN_SPECS_DIR = File.join(
  __dir__, # liquid-spec/tasks
  "..",    # liquid-spec/
  "specs",
  "dawn",
)

DAWN_DIR = File.join(
  __dir__, # liquid-spec/tasks
  "..",    # liquid-spec/
  "tmp",
  "dawn",
)

def copy_sections
  Dir[File.join(DAWN_DIR, "sections", "*")].each do |file|
    spec_name = File.basename(file, ".liquid")
    spec_dir = File.join(DAWN_SPECS_DIR, spec_name)
    FileUtils.mkdir_p(spec_dir)
    FileUtils.cp(file, File.join(spec_dir, "template.liquid"))
  end
end

def copy_filesystem
end
