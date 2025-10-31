# frozen_string_literal: true

# Shared context to clean up background threads spawned by provider specs.
# Usage:
#   include_context "provider_thread_cleanup", "providers/anthropic.rb"
# Will kill and join any threads whose backtrace includes the provided substring.
# Keeps specs isolated and prevents RSpec double leakage across examples.
RSpec.shared_context "provider_thread_cleanup" do |file_fragment|
  after do
    Thread.list.each do |t|
      bt = t.backtrace
      next unless bt&.any? { |l| l.include?(file_fragment) }
      t.kill
      t.join(0.1)
    end
  end
end
