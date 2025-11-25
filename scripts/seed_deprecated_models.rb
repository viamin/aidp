#!/usr/bin/env ruby
# frozen_string_literal: true

# Seed deprecation cache with known deprecated models
# This is a one-time migration from hardcoded constants to dynamic cache

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "json"
require "fileutils"
require "time"

# Simple cache implementation for seeding
cache_path = File.expand_path("../.aidp/deprecated_models.json", __dir__)
FileUtils.mkdir_p(File.dirname(cache_path))

# Known deprecated Anthropic models
deprecated_models = {
  "claude-3-7-sonnet-20250219" => "claude-sonnet-4-5-20250929",
  "claude-3-7-sonnet-latest" => "claude-sonnet-4-5",
  "claude-3-5-sonnet-20241022" => "claude-sonnet-4-5-20250929",
  "claude-3-5-sonnet-latest" => "claude-sonnet-4-5",
  "claude-3-opus-20240229" => "claude-opus-4-20250514"
}

puts "Seeding deprecation cache with #{deprecated_models.size} known deprecated models..."

# Build cache structure
cache_data = {
  "version" => "1.0",
  "updated_at" => Time.now.iso8601,
  "providers" => {
    "anthropic" => {}
  }
}

deprecated_models.each do |model_id, replacement|
  cache_data["providers"]["anthropic"][model_id] = {
    "deprecated_at" => Time.now.iso8601,
    "replacement" => replacement,
    "reason" => "Known deprecated model (seeded from previous hardcoded list)"
  }
  puts "  ✓ #{model_id} → #{replacement}"
end

File.write(cache_path, JSON.pretty_generate(cache_data))

puts "\nDeprecation cache seeded successfully!"
puts "Cache location: #{cache_path}"
puts "\nStats:"
puts "  Total deprecated: #{cache_data["providers"]["anthropic"].size}"
puts "  Provider: anthropic"
