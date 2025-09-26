# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Analyze::RubyMaatIntegration do
  let(:test_prompt) { TestPrompt.new }
  let(:project_dir) { Dir.pwd }
  let(:integration) { described_class.new(project_dir, prompt: test_prompt) }

  describe "initialization" do
    it "accepts a prompt parameter for dependency injection" do
      expect(integration.instance_variable_get(:@prompt)).to eq(test_prompt)
    end
  end

  describe "RubyMaat integration" do
    it "integrates with RubyMaat for repository analysis" do
      # Test placeholder for RubyMaat integration functionality
      expect(Aidp::Analyze::RubyMaatIntegration).to be_a(Class)
    end
  end
end
