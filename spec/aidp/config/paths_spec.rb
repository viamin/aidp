# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::ConfigPaths do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:project_dir) { tmp_dir }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe ".aidp_dir" do
    it "returns the .aidp directory path" do
      expect(described_class.aidp_dir(project_dir)).to eq(File.join(project_dir, ".aidp"))
    end

    it "uses current directory when no argument provided" do
      Dir.chdir(project_dir) do
        result = described_class.aidp_dir
        expected = File.join(Dir.pwd, ".aidp")
        # On macOS, /tmp -> /private/tmp so compare using File.expand_path
        expect(File.expand_path(result)).to eq(File.expand_path(expected))
      end
    end
  end

  describe ".config_file" do
    it "returns the path to aidp.yml" do
      expect(described_class.config_file(project_dir)).to eq(File.join(project_dir, ".aidp", "aidp.yml"))
    end
  end

  describe ".config_dir" do
    it "returns the configuration directory path" do
      expect(described_class.config_dir(project_dir)).to eq(File.join(project_dir, ".aidp"))
    end
  end

  describe ".progress_dir" do
    it "returns the progress directory path" do
      expect(described_class.progress_dir(project_dir)).to eq(File.join(project_dir, ".aidp", "progress"))
    end
  end

  describe ".execute_progress_file" do
    it "returns the execute progress file path" do
      expect(described_class.execute_progress_file(project_dir)).to eq(File.join(project_dir, ".aidp", "progress", "execute.yml"))
    end
  end

  describe ".analyze_progress_file" do
    it "returns the analyze progress file path" do
      expect(described_class.analyze_progress_file(project_dir)).to eq(File.join(project_dir, ".aidp", "progress", "analyze.yml"))
    end
  end

  describe ".harness_state_dir" do
    it "returns the harness state directory path" do
      expect(described_class.harness_state_dir(project_dir)).to eq(File.join(project_dir, ".aidp", "harness"))
    end
  end

  describe ".harness_state_file" do
    it "returns the harness state file path for a given mode" do
      expect(described_class.harness_state_file("analyze", project_dir)).to eq(File.join(project_dir, ".aidp", "harness", "analyze_state.json"))
    end
  end

  describe ".providers_dir" do
    it "returns the providers directory path" do
      expect(described_class.providers_dir(project_dir)).to eq(File.join(project_dir, ".aidp", "providers"))
    end
  end

  describe ".provider_info_file" do
    it "returns the provider info file path for a given provider" do
      expect(described_class.provider_info_file("claude", project_dir)).to eq(File.join(project_dir, ".aidp", "providers", "claude_info.yml"))
    end
  end

  describe ".jobs_dir" do
    it "returns the jobs directory path" do
      expect(described_class.jobs_dir(project_dir)).to eq(File.join(project_dir, ".aidp", "jobs"))
    end
  end

  describe ".checkpoint_file" do
    it "returns the checkpoint file path" do
      expect(described_class.checkpoint_file(project_dir)).to eq(File.join(project_dir, ".aidp", "checkpoint.yml"))
    end
  end

  describe ".checkpoint_history_file" do
    it "returns the checkpoint history file path" do
      expect(described_class.checkpoint_history_file(project_dir)).to eq(File.join(project_dir, ".aidp", "checkpoint_history.jsonl"))
    end
  end

  describe ".json_storage_dir" do
    it "returns the JSON storage directory path" do
      expect(described_class.json_storage_dir(project_dir)).to eq(File.join(project_dir, ".aidp", "json"))
    end
  end

  describe ".config_exists?" do
    it "returns false when config file does not exist" do
      expect(described_class.config_exists?(project_dir)).to be false
    end

    it "returns true when config file exists" do
      FileUtils.mkdir_p(described_class.aidp_dir(project_dir))
      File.write(described_class.config_file(project_dir), "---")

      expect(described_class.config_exists?(project_dir)).to be true
    end
  end

  describe ".ensure_aidp_dir" do
    it "creates the .aidp directory if it does not exist" do
      dir = described_class.ensure_aidp_dir(project_dir)

      expect(Dir.exist?(dir)).to be true
      expect(dir).to eq(File.join(project_dir, ".aidp"))
    end

    it "returns the directory path if it already exists" do
      existing_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(existing_dir)

      dir = described_class.ensure_aidp_dir(project_dir)

      expect(dir).to eq(existing_dir)
    end
  end

  describe ".ensure_config_dir" do
    it "ensures the configuration directory exists" do
      dir = described_class.ensure_config_dir(project_dir)

      expect(Dir.exist?(dir)).to be true
    end
  end

  describe ".ensure_progress_dir" do
    it "creates the progress directory if it does not exist" do
      dir = described_class.ensure_progress_dir(project_dir)

      expect(Dir.exist?(dir)).to be true
      expect(dir).to eq(File.join(project_dir, ".aidp", "progress"))
    end
  end

  describe ".ensure_harness_state_dir" do
    it "creates the harness state directory if it does not exist" do
      dir = described_class.ensure_harness_state_dir(project_dir)

      expect(Dir.exist?(dir)).to be true
      expect(dir).to eq(File.join(project_dir, ".aidp", "harness"))
    end
  end

  describe ".ensure_providers_dir" do
    it "creates the providers directory if it does not exist" do
      dir = described_class.ensure_providers_dir(project_dir)

      expect(Dir.exist?(dir)).to be true
      expect(dir).to eq(File.join(project_dir, ".aidp", "providers"))
    end
  end

  describe ".ensure_jobs_dir" do
    it "creates the jobs directory if it does not exist" do
      dir = described_class.ensure_jobs_dir(project_dir)

      expect(Dir.exist?(dir)).to be true
      expect(dir).to eq(File.join(project_dir, ".aidp", "jobs"))
    end
  end

  describe ".ensure_json_storage_dir" do
    it "creates the JSON storage directory if it does not exist" do
      dir = described_class.ensure_json_storage_dir(project_dir)

      expect(Dir.exist?(dir)).to be true
      expect(dir).to eq(File.join(project_dir, ".aidp", "json"))
    end
  end
end
