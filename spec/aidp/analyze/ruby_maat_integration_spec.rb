# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Analyze::RubyMaatIntegration do
  describe "RubyMaat integration" do
    it "integrates with RubyMaat for repository analysis" do
      # Test placeholder for RubyMaat integration functionality
      expect(Aidp::Analyze::RubyMaatIntegration).to be_a(Class)
    end

    describe "#check_prerequisites" do
      it "checks for Git repository and log availability" do
        integration = Aidp::Analyze::RubyMaatIntegration.new
        prerequisites = integration.check_prerequisites

        expect(prerequisites).to have_key(:git_repository)
        expect(prerequisites).to have_key(:git_log_available)
      end
    end
  end
end
