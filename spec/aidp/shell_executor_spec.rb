require "spec_helper"
require "aidp/shell_executor"
require "rbconfig"
require "tmpdir"

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

    it "treats a signal-terminated command as a failure rather than exit code 0" do
      result = described_class.new.run_argv(RbConfig.ruby, "-e", "Process.kill('KILL', Process.pid)")

      expect(result).not_to be_success
      expect(result.exit_status).not_to eq(0)
    end
  end

  describe "#run_line" do
    it "tokenizes a quoted command line and captures output" do
      result = described_class.new.run_line("printf 'hello world'")

      expect(result).to be_success
      expect(result.stdout).to eq("hello world")
    end

    it "does not interpret shell metacharacters from the command line" do
      result = described_class.new.run_line("printf '%s' '42; touch /tmp/aidp-pwned-line'")

      expect(result).to be_success
      expect(result.stdout).to eq("42; touch /tmp/aidp-pwned-line")
      expect(File.exist?("/tmp/aidp-pwned-line")).to be false
    end

    it "runs the command in the given directory" do
      Dir.mktmpdir do |dir|
        result = described_class.new.run_line("pwd", chdir: dir)

        expect(result).to be_success
        expect(result.stdout.strip).to eq(File.realpath(dir))
      end
    end

    it "reports non-zero exit status" do
      result = described_class.new.run_line(RbConfig.ruby + " -e 'exit 3'")

      expect(result).not_to be_success
      expect(result.exit_status).to eq(3)
    end

    it "raises for a blank command line" do
      expect { described_class.new.run_line("   ") }.to raise_error(ArgumentError)
    end

    it "raises for a command line with unbalanced quotes" do
      expect { described_class.new.run_line("echo 'unclosed") }.to raise_error(ArgumentError)
    end

    it "rejects shell operators rather than running them as literal arguments" do
      ["bundle exec rspec && bundle exec rubocop",
        "bundle exec rspec || bundle exec rubocop",
        "echo one ; echo two",
        "cat file | wc -l"].each do |command|
        expect { described_class.new.run_line(command) }
          .to raise_error(ArgumentError, /shell operators are not supported/)
      end
    end

    it "rejects redirections rather than running them as literal arguments" do
      ["echo hello > /tmp/aidp-line-out",
        "cat < /tmp/aidp-line-in",
        "echo hello >> /tmp/aidp-line-out",
        "echo hello &"].each do |command|
        expect { described_class.new.run_line(command) }
          .to raise_error(ArgumentError, /shell operators are not supported/)
      end
    end

    it "allows shell metacharacters inside a single quoted argument" do
      result = described_class.new.run_line("bash -c 'echo error >&2 && exit 1'")

      expect(result).not_to be_success
      expect(result.stderr).to eq("error\n")
    end
  end
end
