require 'pathname'

module Helpers
  extend self

  def load_shopify_liquid
    if File.exist?("./tmp/liquid")
      `git -C tmp/liquid pull --depth 1 https://github.com/Shopify/liquid.git`
    else
      `git clone --depth 1 https://github.com/Shopify/liquid.git ./tmp/liquid`
    end
  end


  def insert_patch(file_path, patch)
    repo_path = Pathname.new(file_path).relative_path_from("tmp/liquid").to_s
    unless system("git -C tmp/liquid diff --exit-code --quiet #{repo_path.inspect}")
      unless system("git -C tmp/liquid checkout -q HEAD #{repo_path.inspect}")
        raise "Failed to reset #{file_path.inspect} for patching"
      end
    end
    File.write(file_path, patch, mode: "a+")
  end

  def reset_captures(path)
    if File.exist?(path)
      File.delete(path)
      File.write(path, "---\n", mode: "a+")
    end
  end

  def format_and_write_specs(capture_path, outfile)
    yaml = File.read(capture_path)
    data = YAML.unsafe_load(yaml)
    data.sort_by! { |h| h["name"] }
    data.uniq!
    File.write(outfile, YAML.dump(data))
  end
end
