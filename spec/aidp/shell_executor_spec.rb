require "spec_helper"
require "aidp/shell_executor"
require "rbconfig"

RSpec.describe Aidp::ShellExecutor do
  describe "#run_argv" do
    it "captures output of a successful command" do
      result = described_class.new.run_argv("printf", "hello")

      expect(result).to be_success
      expect(result.stdout).to eq("hello")
      expect(result.output).to eq("hello")
    end

    it "treats shell metacharacters in arguments as literal data" do
      result = described_class.new.run_argv("printf", "42; touch /tmp/aidp-pwned")

      expect(result).to be_success
      expect(result.stdout).to eq("42; touch /tmp/aidp-pwned")
      expect(File.exist?("/tmp/aidp-pwned")).to be false
    end

    it "reports non-zero exit status and stderr" do
      result = described_class.new.run_argv(RbConfig.ruby, "-e", "warn 'boom'; exit 3")

      expect(result).not_to be_success
      expect(result.exit_status).to eq(3)
      expect(result.stderr).to eq("boom\n".b)
      expect(result.output).to eq("boom\n".b)
    end
  end
end
