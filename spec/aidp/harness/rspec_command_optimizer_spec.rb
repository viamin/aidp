# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/rspec_command_optimizer"

RSpec.describe Aidp::Harness::RSpecCommandOptimizer do
  let(:project_dir) { Dir.mktmpdir }
  let(:optimizer) { described_class.new(project_dir) }

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe "#rspec_command?" do
    it "returns true for rspec commands" do
      expect(optimizer.rspec_command?("bundle exec rspec")).to be true
      expect(optimizer.rspec_command?("rspec spec/")).to be true
      expect(optimizer.rspec_command?("bundle exec rspec spec/foo_spec.rb")).to be true
    end

    it "returns false for non-rspec commands" do
      expect(optimizer.rspec_command?("bundle exec rake test")).to be false
      expect(optimizer.rspec_command?("pytest")).to be false
      expect(optimizer.rspec_command?(nil)).to be false
    end
  end

  describe "#optimize_command" do
    context "when not an RSpec command" do
      it "returns original command without optimization" do
        result = optimizer.optimize_command("pytest", iteration: 2, had_failures: true)

        expect(result[:command]).to eq("pytest")
        expect(result[:optimized]).to be false
        expect(result[:reason]).to eq("not an RSpec command")
      end
    end

    context "on first iteration" do
      it "returns original command without optimization" do
        result = optimizer.optimize_command("bundle exec rspec", iteration: 1, had_failures: false)

        expect(result[:command]).to eq("bundle exec rspec")
        expect(result[:optimized]).to be false
        expect(result[:reason]).to eq("first iteration")
      end
    end

    context "when no previous failures" do
      it "returns original command without optimization" do
        result = optimizer.optimize_command("bundle exec rspec", iteration: 2, had_failures: false)

        expect(result[:command]).to eq("bundle exec rspec")
        expect(result[:optimized]).to be false
        expect(result[:reason]).to eq("no previous failures")
      end
    end

    context "when command already has --only-failures" do
      it "returns original command without double-adding flag" do
        result = optimizer.optimize_command("bundle exec rspec --only-failures", iteration: 2, had_failures: true)

        expect(result[:command]).to eq("bundle exec rspec --only-failures")
        expect(result[:optimized]).to be false
        expect(result[:reason]).to eq("already has --only-failures")
      end
    end

    context "when no .rspec_status file exists" do
      it "returns original command with warning reason" do
        result = optimizer.optimize_command("bundle exec rspec", iteration: 2, had_failures: true)

        expect(result[:command]).to eq("bundle exec rspec")
        expect(result[:optimized]).to be false
        expect(result[:reason]).to include("no .rspec_status file")
      end
    end

    context "when .rspec_status file exists" do
      before do
        File.write(File.join(project_dir, ".rspec_status"), "example_id | status\nspec/foo_spec.rb[1:1] | failed")
      end

      it "adds --only-failures flag" do
        result = optimizer.optimize_command("bundle exec rspec", iteration: 2, had_failures: true)

        expect(result[:command]).to eq("bundle exec rspec --only-failures")
        expect(result[:optimized]).to be true
        expect(result[:reason]).to include("using --only-failures")
      end

      it "inserts flag correctly with file arguments" do
        result = optimizer.optimize_command("bundle exec rspec spec/foo_spec.rb", iteration: 2, had_failures: true)

        expect(result[:command]).to eq("bundle exec rspec --only-failures spec/foo_spec.rb")
        expect(result[:optimized]).to be true
      end

      it "includes status file path in result" do
        result = optimizer.optimize_command("bundle exec rspec", iteration: 2, had_failures: true)

        expect(result[:status_file]).to eq(".rspec_status")
      end
    end

    context "when .rspec_status is in tmp directory" do
      before do
        FileUtils.mkdir_p(File.join(project_dir, "tmp"))
        File.write(File.join(project_dir, "tmp", ".rspec_status"), "example_id | status")
      end

      it "finds the status file in tmp" do
        result = optimizer.optimize_command("bundle exec rspec", iteration: 2, had_failures: true)

        expect(result[:optimized]).to be true
        expect(result[:status_file]).to eq("tmp/.rspec_status")
      end
    end
  end

  describe "#find_status_file" do
    it "returns nil when no status file exists" do
      expect(optimizer.find_status_file).to be_nil
    end

    it "finds .rspec_status in project root" do
      File.write(File.join(project_dir, ".rspec_status"), "content")
      optimizer.reset_caches!

      expect(optimizer.find_status_file).to eq(".rspec_status")
    end

    it "finds .rspec_status in tmp directory" do
      FileUtils.mkdir_p(File.join(project_dir, "tmp"))
      File.write(File.join(project_dir, "tmp", ".rspec_status"), "content")
      optimizer.reset_caches!

      expect(optimizer.find_status_file).to eq("tmp/.rspec_status")
    end

    it "caches the result" do
      File.write(File.join(project_dir, ".rspec_status"), "content")
      optimizer.reset_caches!

      expect(optimizer.find_status_file).to eq(".rspec_status")

      # Remove file - cached value should still be returned
      File.delete(File.join(project_dir, ".rspec_status"))
      expect(optimizer.find_status_file).to eq(".rspec_status")
    end
  end

  describe "#check_persistence_configuration" do
    context "when spec_helper.rb doesn't exist" do
      it "returns not configured" do
        result = optimizer.check_persistence_configuration

        expect(result[:configured]).to be false
        expect(result[:message]).to include("not configured")
      end
    end

    context "when spec_helper.rb exists but lacks persistence config" do
      before do
        FileUtils.mkdir_p(File.join(project_dir, "spec"))
        File.write(File.join(project_dir, "spec", "spec_helper.rb"), <<~RUBY)
          RSpec.configure do |config|
            config.expect_with :rspec do |expectations|
              expectations.syntax = :expect
            end
          end
        RUBY
      end

      it "returns not configured with instructions" do
        result = optimizer.check_persistence_configuration

        expect(result[:configured]).to be false
        expect(result[:message]).to include("config.example_status_persistence_file_path")
      end
    end

    context "when spec_helper.rb has persistence configured" do
      before do
        FileUtils.mkdir_p(File.join(project_dir, "spec"))
        File.write(File.join(project_dir, "spec", "spec_helper.rb"), <<~RUBY)
          RSpec.configure do |config|
            config.example_status_persistence_file_path = '.rspec_status'
          end
        RUBY
      end

      it "returns configured" do
        result = optimizer.check_persistence_configuration

        expect(result[:configured]).to be true
        expect(result[:message]).to include("RSpec persistence configured")
      end

      context "when status file exists" do
        before do
          File.write(File.join(project_dir, ".rspec_status"), "content")
          optimizer.reset_caches!
        end

        it "includes file path in result" do
          result = optimizer.check_persistence_configuration

          expect(result[:file_path]).to eq(".rspec_status")
          expect(result[:message]).to include(".rspec_status exists")
        end
      end
    end

    context "when rails_helper.rb has persistence configured" do
      before do
        FileUtils.mkdir_p(File.join(project_dir, "spec"))
        File.write(File.join(project_dir, "spec", "rails_helper.rb"), <<~RUBY)
          RSpec.configure do |config|
            config.example_status_persistence_file_path = 'tmp/.rspec_status'
          end
        RUBY
      end

      it "returns configured" do
        result = optimizer.check_persistence_configuration

        expect(result[:configured]).to be true
      end
    end
  end

  describe "#reset_caches!" do
    it "clears status file cache" do
      File.write(File.join(project_dir, ".rspec_status"), "content")
      optimizer.reset_caches!
      expect(optimizer.find_status_file).to eq(".rspec_status")

      # Delete file and reset
      File.delete(File.join(project_dir, ".rspec_status"))
      optimizer.reset_caches!

      expect(optimizer.find_status_file).to be_nil
    end

    it "clears persistence configuration cache" do
      result1 = optimizer.check_persistence_configuration
      expect(result1[:configured]).to be false

      # Add config
      FileUtils.mkdir_p(File.join(project_dir, "spec"))
      File.write(File.join(project_dir, "spec", "spec_helper.rb"), <<~RUBY)
        RSpec.configure do |config|
          config.example_status_persistence_file_path = '.rspec_status'
        end
      RUBY
      optimizer.reset_caches!

      result2 = optimizer.check_persistence_configuration
      expect(result2[:configured]).to be true
    end
  end
end
