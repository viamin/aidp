# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/storage_command"
require "aidp/database"

RSpec.describe Aidp::CLI::StorageCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:command) { described_class.new(prompt: prompt, project_dir: temp_dir) }
  let(:aidp_dir) { File.join(temp_dir, ".aidp") }

  before do
    FileUtils.mkdir_p(aidp_dir)
    allow(prompt).to receive(:yes?).and_return(true)
    allow(prompt).to receive(:say)
  end

  after do
    Aidp::Database.close(temp_dir) if Aidp::Database.exists?(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run" do
    context "with no subcommand" do
      it "displays usage" do
        expect { command.run([]) }.to output(/Usage:.*storage/).to_stdout
      end
    end

    context "with --help" do
      it "displays usage" do
        expect { command.run(["--help"]) }.to output(/Usage:.*storage/).to_stdout
      end
    end

    context "with unknown subcommand" do
      it "displays error and usage" do
        expect { command.run(["unknown"]) }.to output(/Unknown subcommand/).to_stdout
      end
    end
  end

  describe "migrate subcommand" do
    context "when no file storage exists" do
      it "reports nothing to migrate" do
        expect { command.run(["migrate"]) }.to output(/No file-based storage found/).to_stdout
      end
    end

    context "when file storage exists" do
      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), YAML.dump("step" => "test"))
      end

      it "performs migration" do
        expect { command.run(["migrate"]) }.to output(/Migration Results/).to_stdout
      end

      it "supports dry run" do
        expect { command.run(["migrate", "--dry-run"]) }.to output(/DRY RUN/).to_stdout
      end
    end

    context "when already migrated" do
      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), YAML.dump("step" => "test"))
        Aidp::Database::Migrations.run!(temp_dir)
        db = Aidp::Database.connection(temp_dir)
        db.execute("INSERT INTO checkpoints (project_dir, step_name, status) VALUES (?, ?, ?)",
          [temp_dir, "test", "completed"])
      end

      it "warns about existing data" do
        expect { command.run(["migrate"]) }.to output(/already contains migrated data/).to_stdout
      end

      it "allows force migration" do
        expect { command.run(["migrate", "--force"]) }.to output(/Migration Results/).to_stdout
      end
    end
  end

  describe "status subcommand" do
    it "displays storage status" do
      expect { command.run(["status"]) }.to output(/Storage Migration Status/).to_stdout
    end

    context "with file storage" do
      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), "test")
      end

      it "indicates migration needed" do
        expect { command.run(["status"]) }.to output(/File-based storage: Found/).to_stdout
      end
    end

    context "with database" do
      before do
        Aidp::Database::Migrations.run!(temp_dir)
        db = Aidp::Database.connection(temp_dir)
        db.execute("INSERT INTO checkpoints (project_dir, step_name, status) VALUES (?, ?, ?)",
          [temp_dir, "test", "completed"])
      end

      it "indicates database has data" do
        expect { command.run(["status"]) }.to output(/SQLite database: Contains data/).to_stdout
      end
    end
  end

  describe "cleanup subcommand" do
    context "when not migrated" do
      it "refuses to cleanup" do
        expect { command.run(["cleanup"]) }.to output(/Cannot cleanup/).to_stdout
      end
    end

    context "when migrated" do
      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), "test")
        Aidp::Database::Migrations.run!(temp_dir)
        db = Aidp::Database.connection(temp_dir)
        db.execute("INSERT INTO checkpoints (project_dir, step_name, status) VALUES (?, ?, ?)",
          [temp_dir, "test", "completed"])
      end

      it "cleans up old storage" do
        expect { command.run(["cleanup", "--force"]) }.to output(/Cleanup complete/).to_stdout
        expect(File.exist?(File.join(aidp_dir, "checkpoint.yml"))).to be false
      end
    end
  end
end
