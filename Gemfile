# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "benchmark" # Suppress Ruby 3.5.0 deprecation warning
  gem "rake"
  gem "reline" # Suppress Ruby 3.5.0 deprecation warning
  gem "simplecov-mcp", require: false
  gem "standard"
end

group :test do
  gem "aruba" # System testing framework
  gem "rspec"
  gem "simplecov", require: false
  gem "webmock"
end
