# frozen_string_literal: true

require "spec_helper"
require "aidp/shell_executor"

RSpec.describe Aidp::ShellExecutor do
  let(:executor) { described_class.new }

  describe "#run" do
    it "captures combined stdout and stderr output" do
      expect(executor.run("echo", "hello world")).to eq("hello world\n")
    end

    it "passes arguments verbatim without shell interpretation" do
      malicious = "file; rm -rf /"
      expect(executor.run("printf", "%s", malicious)).to include(malicious)
    end

    it "does not execute shell metacharacters from arguments" do
      output = executor.run("printf", "%s", "$(echo injected)")

      expect(output).to eq("$(echo injected)")
      expect(output).not_to include("injected\n")
    end
  end

  describe "#success?" do
    it "returns true after a successful run" do
      executor.run("true")

      expect(executor.success?).to be true
    end

    it "returns false after a failed run" do
      executor.run("false")

      expect(executor.success?).to be false
    end

    it "reflects the most recent run" do
      executor.run("false")
      executor.run("true")

      expect(executor.success?).to be true
    end
  end

  describe "#system" do
    it "runs commands given as argument arrays" do
      expect(executor.system("echo", "hi", out: File::NULL, err: File::NULL)).to be true
    end
  end
end
