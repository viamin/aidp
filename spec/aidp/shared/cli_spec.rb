# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Shared::CLI do
  describe "CLI commands" do
    it "defines execute command" do
      expect(Aidp::Shared::CLI.commands.keys).to include("execute")
    end

    it "defines analyze command" do
      expect(Aidp::Shared::CLI.commands.keys).to include("analyze")
    end

    it "defines status command" do
      expect(Aidp::Shared::CLI.commands.keys).to include("status")
    end

    it "defines version command" do
      expect(Aidp::Shared::CLI.commands.keys).to include("version")
    end
  end
end
