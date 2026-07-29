# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/setup/devcontainer/jsonc_document"

RSpec.describe Aidp::Setup::Devcontainer::JsoncDocument do
  describe ".dump" do
    it "keeps array comments attached to their values after reordering" do
      existing = described_class.parse(<<~JSONC)
        {
          "forwardPorts": [
            // app
            3000,
            // admin
            8080
          ]
        }
      JSONC

      output = described_class.dump(
        {"forwardPorts" => [1000, 3000, 8080]},
        comments: existing.comments
      )

      expect(output).to include(<<~JSONC.chomp)
        "forwardPorts": [
            1000,
            // app
            3000,
            // admin
            8080
      JSONC
    end

    it "preserves distinct comments for duplicate array values in order" do
      existing = described_class.parse(<<~JSONC)
        {
          "ports": [
            // first
            3000,
            // second
            3000
          ]
        }
      JSONC

      output = described_class.dump(
        {"ports" => [3000, 3000]},
        comments: existing.comments
      )

      expect(output).to include("// first\n    3000,\n")
      expect(output).to include("// second\n    3000\n")
    end
  end
end
