module Helpers
  extend self

  def load_shopify_liquid
    git_tag = "v5.4.0"

    FileUtils.mkdir_p("tmp")
    FileUtils.rm_rf("tmp/liquid")

    puts "Loading Shopify/liquid@#{git_tag}..."

    `git clone --depth 1 https://github.com/Shopify/liquid.git ./tmp/liquid`
    `git -C tmp/liquid checkout #{git_tag}`
  end


  def insert_patch(file_path, patch)
    return if File.read(file_path).include?(patch)
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
