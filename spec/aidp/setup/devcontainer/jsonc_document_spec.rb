# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/setup/devcontainer/jsonc_document"

RSpec.describe Aidp::Setup::Devcontainer::JsoncDocument do
  describe ".parse" do
    it "parses objects whose body contains only comments" do
      document = described_class.parse(<<~JSONC)
        {
          "customizations": {
            // optional settings
          }
        }
      JSONC

      expect(document.data).to eq({"customizations" => {}})
    end

    it "parses objects with trailing commas before closing braces" do
      document = described_class.parse(<<~JSONC)
        {
          "name": "x",
          "customizations": {
            "vscode": {} // keep me
          },
        }
      JSONC

      expect(document.data).to eq(
        {
          "name" => "x",
          "customizations" => {"vscode" => {}}
        }
      )
    end

    it "parses arrays with trailing commas before closing brackets" do
      document = described_class.parse(<<~JSONC)
        {
          "forwardPorts": [
            3000,
          ],
        }
      JSONC

      expect(document.data).to eq({"forwardPorts" => [3000]})
    end
  end

  describe ".dump" do
    it "keeps trailing property comments after the property they annotate" do
      existing = described_class.parse(<<~JSONC)
        {
          "remote.portsAttributes": {
            "*": {
              "requireLocalPort": true
            } // prefer same-number local port
          }
        }
      JSONC

      output = described_class.dump(existing.data, comments: existing.comments)

      expect(output).to include(<<~JSONC.chomp)
        "requireLocalPort": true
            } // prefer same-number local port
      JSONC
    end

    it "keeps trailing comment blocks below the last property" do
      existing = described_class.parse(<<~JSONC)
        {
          "mounts": []
          // Optional: uncomment to keep container running
          // "overrideCommand": true
        }
      JSONC

      output = described_class.dump(existing.data, comments: existing.comments)

      expect(output).to include(<<~JSONC.chomp)
        "mounts": []
          // Optional: uncomment to keep container running
          // "overrideCommand": true
        }
      JSONC
    end

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

    it "keeps trailing array comments with reordered values" do
      existing = described_class.parse(<<~JSONC)
        {
          "ports": [
            3000 // app
          ]
        }
      JSONC

      output = described_class.dump(
        {"ports" => [1000, 3000]},
        comments: existing.comments
      )

      expect(output).to include("1000,\n    3000 // app\n")
    end

    it "keeps trailing root comments after the document" do
      existing = described_class.parse(<<~JSONC)
        {
          "mounts": []
        }
        // preserve me
      JSONC

      output = described_class.dump(existing.data, comments: existing.comments)

      expect(output).to end_with("}\n// preserve me\n")
    end
  end
end
