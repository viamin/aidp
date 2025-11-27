# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/aidp/tooling_detector"

RSpec.describe Aidp::ToolingDetector do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write(path, content)
    full = File.join(tmpdir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  it "detects rspec and standard in a Ruby project" do
    write("Gemfile", "source 'https://rubygems.org'\ngem 'rspec'\ngem 'standard'\n")
    write("spec/example_spec.rb", "RSpec.describe('x'){ }")

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("bundle exec rspec")
    expect(result.lint_commands).to include("bundle exec standardrb")
  end

  it "detects npm scripts with npm" do
    write("package.json", '{"scripts":{"test":"jest","lint":"eslint ."}}')

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("npm run test")
    expect(result.lint_commands.first).to match(/npm run (lint|eslint)/)
  end

  it "detects yarn if yarn.lock present" do
    write("package.json", '{"scripts":{"test":"jest"}}')
    write("yarn.lock", "# lock file")

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("yarn test")
  end

  it "detects pytest" do
    write("pytest.ini", "[pytest]")

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("pytest -q")
  end

  it "is empty when nothing detectable" do
    result = described_class.detect(tmpdir)
    expect(result.test_commands).to be_empty
    expect(result.lint_commands).to be_empty
  end

  describe ".framework_from_command" do
    it "detects rspec from command" do
      expect(described_class.framework_from_command("bundle exec rspec")).to eq(:rspec)
      expect(described_class.framework_from_command("rspec spec/")).to eq(:rspec)
    end

    it "detects minitest from command" do
      expect(described_class.framework_from_command("ruby -Itest test/test_user.rb")).to eq(:minitest)
      expect(described_class.framework_from_command("rake test")).to eq(:minitest)
    end

    it "detects jest from command" do
      expect(described_class.framework_from_command("yarn jest")).to eq(:jest)
      expect(described_class.framework_from_command("npx jest")).to eq(:jest)
    end

    it "detects pytest from command" do
      expect(described_class.framework_from_command("pytest")).to eq(:pytest)
      expect(described_class.framework_from_command("python -m pytest")).to eq(:pytest)
    end

    it "returns unknown for unrecognized commands" do
      expect(described_class.framework_from_command("./custom-test-runner")).to eq(:unknown)
      expect(described_class.framework_from_command("make test")).to eq(:unknown)
      # npm run test doesn't contain 'jest' so returns unknown
      expect(described_class.framework_from_command("npm run test")).to eq(:unknown)
    end

    it "handles nil input" do
      expect(described_class.framework_from_command(nil)).to eq(:unknown)
    end

    it "handles empty string" do
      expect(described_class.framework_from_command("")).to eq(:unknown)
    end
  end

  describe ".recommended_flags" do
    it "returns format flags for rspec as hash" do
      flags = described_class.recommended_flags(:rspec)
      expect(flags).to be_a(Hash)
      expect(flags[:standard]).to include("--format progress")
      expect(flags[:verbose]).to include("--format documentation")
      expect(flags[:failures_only]).to include("--format failures")
    end

    it "returns verbose flag for minitest" do
      flags = described_class.recommended_flags(:minitest)
      expect(flags).to be_a(Hash)
      expect(flags[:verbose]).to eq("-v")
    end

    it "returns verbose flag for jest" do
      flags = described_class.recommended_flags(:jest)
      expect(flags).to be_a(Hash)
      expect(flags[:verbose]).to eq("--verbose")
    end

    it "returns verbose flag for pytest" do
      flags = described_class.recommended_flags(:pytest)
      expect(flags).to be_a(Hash)
      expect(flags[:verbose]).to eq("-v")
    end

    it "returns hash with empty strings for unknown framework" do
      flags = described_class.recommended_flags(:unknown)
      expect(flags).to be_a(Hash)
      expect(flags[:standard]).to eq("")
      expect(flags[:verbose]).to eq("")
      expect(flags[:failures_only]).to eq("")
    end
  end

  describe "frameworks detection" do
    it "detects rspec framework and maps command" do
      write("Gemfile", "source 'https://rubygems.org'\ngem 'rspec'\n")
      write("spec/example_spec.rb", "RSpec.describe('x'){ }")

      result = described_class.detect(tmpdir)
      # Frameworks hash maps command -> framework, not framework -> boolean
      expect(result.frameworks.values).to include(:rspec)
    end

    it "detects minitest framework and maps command" do
      write("Gemfile", "source 'https://rubygems.org'\ngem 'minitest'\n")
      write("test/user_test.rb", "class UserTest < Minitest::Test; end")

      result = described_class.detect(tmpdir)
      expect(result.frameworks.values).to include(:minitest)
    end

    it "detects jest from package.json" do
      write("package.json", '{"devDependencies":{"jest":"^29.0.0"},"scripts":{"test":"jest"}}')

      result = described_class.detect(tmpdir)
      expect(result.frameworks.values).to include(:jest)
    end

    it "detects pytest" do
      write("pytest.ini", "[pytest]")

      result = described_class.detect(tmpdir)
      expect(result.frameworks.values).to include(:pytest)
    end
  end

  describe "#test_command_frameworks" do
    it "maps test commands to their frameworks" do
      write("Gemfile", "source 'https://rubygems.org'\ngem 'rspec'\n")
      write("spec/example_spec.rb", "RSpec.describe('x'){ }")

      result = described_class.detect(tmpdir)
      frameworks = result.test_command_frameworks

      expect(frameworks["bundle exec rspec"]).to eq(:rspec)
    end
  end
end
