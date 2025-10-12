# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/guard_policy"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Execute::GuardPolicy do
  let(:project_dir) { Dir.mktmpdir }
  let(:config) { {enabled: false} }
  let(:guard_policy) { described_class.new(project_dir, config) }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#enabled?" do
    context "when guards are disabled" do
      it "returns false" do
        expect(guard_policy.enabled?).to be false
      end
    end

    context "when guards are enabled" do
      let(:config) { {enabled: true} }

      it "returns true" do
        expect(guard_policy.enabled?).to be true
      end
    end
  end

  describe "#can_modify_file?" do
    context "when guards are disabled" do
      it "allows all files" do
        result = guard_policy.can_modify_file?("any_file.rb")
        expect(result[:allowed]).to be true
      end
    end

    context "when guards are enabled" do
      let(:config) { {enabled: true} }

      context "with no patterns configured" do
        it "allows all files" do
          result = guard_policy.can_modify_file?("any_file.rb")
          expect(result[:allowed]).to be true
        end
      end

      context "with exclude patterns" do
        let(:config) do
          {
            enabled: true,
            exclude_files: ["config/*.yml", "*.env"]
          }
        end

        it "rejects excluded files" do
          result = guard_policy.can_modify_file?("config/database.yml")
          expect(result[:allowed]).to be false
          expect(result[:reason]).to include("exclude pattern")
        end

        it "allows non-excluded files" do
          result = guard_policy.can_modify_file?("lib/file.rb")
          expect(result[:allowed]).to be true
        end

        it "rejects files matching wildcard pattern" do
          result = guard_policy.can_modify_file?(".env")
          expect(result[:allowed]).to be false
        end
      end

      context "with include patterns" do
        let(:config) do
          {
            enabled: true,
            include_files: ["lib/**/*.rb", "spec/**/*_spec.rb"]
          }
        end

        it "allows files matching include pattern" do
          result = guard_policy.can_modify_file?("lib/foo/bar.rb")
          expect(result[:allowed]).to be true
        end

        it "rejects files not matching include pattern" do
          result = guard_policy.can_modify_file?("app/models/user.rb")
          expect(result[:allowed]).to be false
          expect(result[:reason]).to include("does not match any include pattern")
        end
      end

      context "with both include and exclude patterns" do
        let(:config) do
          {
            enabled: true,
            include_files: ["lib/**/*.rb"],
            exclude_files: ["lib/legacy/**/*"]
          }
        end

        it "rejects excluded files even if they match include" do
          result = guard_policy.can_modify_file?("lib/legacy/old_code.rb")
          expect(result[:allowed]).to be false
          expect(result[:reason]).to include("exclude pattern")
        end

        it "allows files matching include but not exclude" do
          result = guard_policy.can_modify_file?("lib/new_code.rb")
          expect(result[:allowed]).to be true
        end
      end

      context "with confirmation required files" do
        let(:config) do
          {
            enabled: true,
            confirm_files: ["Gemfile", "package.json"]
          }
        end

        it "requires confirmation for unconfirmed files" do
          result = guard_policy.can_modify_file?("Gemfile")
          expect(result[:allowed]).to be false
          expect(result[:requires_confirmation]).to be true
        end

        it "allows confirmed files" do
          guard_policy.confirm_file("Gemfile")
          result = guard_policy.can_modify_file?("Gemfile")
          expect(result[:allowed]).to be true
        end
      end
    end
  end

  describe "#validate_changes" do
    let(:config) { {enabled: true} }

    context "with no constraints" do
      it "validates successfully" do
        diff_stats = {
          "file1.rb" => {additions: 10, deletions: 5}
        }
        result = guard_policy.validate_changes(diff_stats)
        expect(result[:valid]).to be true
      end
    end

    context "with max_lines_per_commit" do
      let(:config) do
        {
          enabled: true,
          max_lines_per_commit: 50
        }
      end

      it "validates within limit" do
        diff_stats = {
          "file1.rb" => {additions: 20, deletions: 10},
          "file2.rb" => {additions: 15, deletions: 5}
        }
        result = guard_policy.validate_changes(diff_stats)
        expect(result[:valid]).to be true
      end

      it "rejects when exceeding limit" do
        diff_stats = {
          "file1.rb" => {additions: 30, deletions: 30},
          "file2.rb" => {additions: 20, deletions: 20}
        }
        result = guard_policy.validate_changes(diff_stats)
        expect(result[:valid]).to be false
        expect(result[:errors].first).to include("exceeds limit")
      end
    end

    context "with file exclusions" do
      let(:config) do
        {
          enabled: true,
          exclude_files: ["config/*.yml"]
        }
      end

      it "rejects changes to excluded files" do
        diff_stats = {
          "config/database.yml" => {additions: 5, deletions: 0}
        }
        result = guard_policy.validate_changes(diff_stats)
        expect(result[:valid]).to be false
        expect(result[:errors].first).to include("database.yml")
      end
    end
  end

  describe "#confirm_file" do
    let(:config) { {enabled: true} }

    it "marks file as confirmed" do
      expect(guard_policy.confirmed?("Gemfile")).to be false
      guard_policy.confirm_file("Gemfile")
      expect(guard_policy.confirmed?("Gemfile")).to be true
    end

    it "normalizes file paths" do
      # Both paths should normalize to the same form
      guard_policy.confirm_file("lib/file.rb")
      expect(guard_policy.confirmed?("lib/file.rb")).to be true
    end
  end

  describe "#summary" do
    context "when disabled" do
      it "returns disabled status" do
        summary = guard_policy.summary
        expect(summary[:enabled]).to be false
      end
    end

    context "when enabled" do
      let(:config) do
        {
          enabled: true,
          include_files: ["lib/**/*.rb"],
          exclude_files: ["config/*.yml"],
          confirm_files: ["Gemfile"],
          max_lines_per_commit: 500
        }
      end

      it "returns complete summary" do
        summary = guard_policy.summary
        expect(summary[:enabled]).to be true
        expect(summary[:include_patterns]).to eq(["lib/**/*.rb"])
        expect(summary[:exclude_patterns]).to eq(["config/*.yml"])
        expect(summary[:confirm_patterns]).to eq(["Gemfile"])
        expect(summary[:max_lines_per_commit]).to eq(500)
      end
    end
  end

  describe "pattern matching" do
    let(:config) { {enabled: true} }

    describe "glob patterns" do
      it "matches * for any characters except /" do
        config[:exclude_files] = ["*.yml"]
        result = guard_policy.can_modify_file?("config.yml")
        expect(result[:allowed]).to be false
      end

      it "matches ** for any characters including /" do
        config[:exclude_files] = ["lib/**/*.rb"]
        result = guard_policy.can_modify_file?("lib/foo/bar.rb")
        expect(result[:allowed]).to be false
      end

      it "matches ? for single character" do
        config[:exclude_files] = ["file?.rb"]
        result = guard_policy.can_modify_file?("file1.rb")
        expect(result[:allowed]).to be false
      end

      it "matches alternatives with {a,b}" do
        config[:exclude_files] = ["*.{yml,yaml}"]
        expect(guard_policy.can_modify_file?("config.yml")[:allowed]).to be false
        expect(guard_policy.can_modify_file?("config.yaml")[:allowed]).to be false
      end
    end
  end

  describe "#bypass?" do
    context "with environment variable" do
      it "returns true when AIDP_BYPASS_GUARDS is set" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("AIDP_BYPASS_GUARDS").and_return("1")
        expect(guard_policy.bypass?).to be true
      end
    end

    context "with config option" do
      let(:config) { {enabled: true, bypass: true} }

      it "returns true" do
        expect(guard_policy.bypass?).to be true
      end
    end

    context "without bypass" do
      let(:config) { {enabled: true} }

      it "returns false" do
        expect(guard_policy.bypass?).to be false
      end
    end
  end
end
