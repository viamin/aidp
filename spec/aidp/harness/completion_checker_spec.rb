# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/completion_checker"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Harness::CompletionChecker do
  let(:project_dir) { Dir.mktmpdir("aidp-completion") }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "basic criteria" do
    it "returns true for all_criteria_met? when minimal project" do
      checker = described_class.new(project_dir, :exploration)
      expect(checker.all_criteria_met?).to be true
    end

    it "includes extended criteria for full workflow" do
      checker = described_class.new(project_dir, :full)
      expect(checker.completion_criteria.keys).to include(:build_successful, :documentation_complete)
    end
  end

  describe "documentation_complete?" do
    it "returns false when docs missing" do
      checker = described_class.new(project_dir, :full)
      expect(checker.send(:documentation_complete?)).to be false
    end

    it "returns true when required docs exist" do
      File.write(File.join(project_dir, "README.md"), "# Readme")
      FileUtils.mkdir_p(File.join(project_dir, "docs"))
      File.write(File.join(project_dir, "docs", "PRD.md"), "# PRD")
      checker = described_class.new(project_dir, :full)
      expect(checker.send(:documentation_complete?)).to be true
    end
  end

  describe "has_tests? detection" do
    it "detects spec directory" do
      FileUtils.mkdir_p(File.join(project_dir, "spec"))
      checker = described_class.new(project_dir)
      expect(checker.send(:has_tests?)).to be true
    end

    it "detects test files pattern" do
      FileUtils.mkdir_p(File.join(project_dir, "lib"))
      File.write(File.join(project_dir, "lib", "sample_spec.rb"), "puts 'hi'")
      checker = described_class.new(project_dir)
      expect(checker.send(:has_tests?)).to be true
    end
  end

  describe "summary generation" do
    it "reports all criteria passed" do
      checker = described_class.new(project_dir)
      status = checker.completion_status
      expect(status[:summary]).to match(/All .* completion criteria met/)
    end

    it "reports failed criteria" do
      # Force a failure by stubbing linting_clean? to false
      checker = described_class.new(project_dir)
      allow(checker).to receive(:linting_clean?).and_return(false)
      status = checker.completion_status
      expect(status[:summary]).to match(/criteria failed/)
    end
  end

  describe "detect_test_commands (Ruby)" do
    it "returns rspec command when Gemfile includes rspec" do
      File.write(File.join(project_dir, "Gemfile"), "gem 'rspec'")
      FileUtils.mkdir_p(File.join(project_dir, "spec"))
      checker = described_class.new(project_dir)
      commands = checker.send(:detect_test_commands)
      expect(commands).to include("bundle exec rspec")
    end
  end

  describe "detect_lint_commands (Ruby)" do
    it "includes rubocop if present" do
      File.write(File.join(project_dir, "Gemfile"), "gem 'rubocop'")
      checker = described_class.new(project_dir)
      cmds = checker.send(:detect_lint_commands)
      expect(cmds).to include("bundle exec rubocop")
    end
  end

  describe "detect_build_commands" do
    it "returns empty when no build config" do
      checker = described_class.new(project_dir)
      expect(checker.send(:detect_build_commands)).to eq([])
    end
  end
end
