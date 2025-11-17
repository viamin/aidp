# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/analyze/progress"
require_relative "../../../lib/aidp/analyze/steps"

RSpec.describe Aidp::Analyze::Progress do
  let(:project_dir) { "/tmp/test_project" }
  let(:progress_file) { File.join(project_dir, ".aidp", "progress", "analyze.yml") }

  describe "#initialize" do
    context "when progress file exists" do
      let(:existing_progress) do
        {
          "completed_steps" => ["01_REPOSITORY_ANALYSIS"],
          "current_step" => "02_ARCHITECTURE_ANALYSIS",
          "started_at" => "2025-01-15T10:30:00Z"
        }
      end

      before do
        allow(File).to receive(:exist?).with(progress_file).and_return(true)
        allow(YAML).to receive(:safe_load_file).with(
          progress_file,
          permitted_classes: [Date, Time, Symbol],
          aliases: true
        ).and_return(existing_progress)
      end

      it "loads existing progress" do
        progress = described_class.new(project_dir)
        expect(progress.completed_steps).to eq(["01_REPOSITORY_ANALYSIS"])
        expect(progress.current_step).to eq("02_ARCHITECTURE_ANALYSIS")
      end

      it "sets the progress file path" do
        progress = described_class.new(project_dir)
        expect(progress.progress_file).to eq(progress_file)
      end
    end

    context "when progress file does not exist" do
      before do
        allow(File).to receive(:exist?).with(progress_file).and_return(false)
      end

      it "initializes with empty progress" do
        progress = described_class.new(project_dir)
        expect(progress.completed_steps).to eq([])
        expect(progress.current_step).to be_nil
      end
    end

    context "when YAML.safe_load_file returns nil" do
      before do
        allow(File).to receive(:exist?).with(progress_file).and_return(true)
        allow(YAML).to receive(:safe_load_file).and_return(nil)
      end

      it "initializes with empty progress" do
        progress = described_class.new(project_dir)
        expect(progress.completed_steps).to eq([])
        expect(progress.current_step).to be_nil
      end
    end

    context "when skip_persistence is true and file does not exist" do
      before do
        allow(File).to receive(:exist?).with(progress_file).and_return(false)
      end

      it "initializes with empty progress without loading" do
        progress = described_class.new(project_dir, skip_persistence: true)
        expect(progress.completed_steps).to eq([])
      end
    end

    context "when skip_persistence is true and file exists" do
      before do
        allow(File).to receive(:exist?).with(progress_file).and_return(true)
        allow(YAML).to receive(:safe_load_file).and_return({})
      end

      it "initializes with empty progress without loading" do
        progress = described_class.new(project_dir, skip_persistence: true)
        expect(progress.completed_steps).to eq([])
      end
    end
  end

  describe "#completed_steps" do
    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    it "returns empty array when no steps completed" do
      progress = described_class.new(project_dir, skip_persistence: true)
      expect(progress.completed_steps).to eq([])
    end

    it "returns array of completed step names" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "completed_steps" => ["01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS"]
      })

      progress = described_class.new(project_dir)
      expect(progress.completed_steps).to eq(["01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS"])
    end
  end

  describe "#current_step" do
    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    it "returns nil when no step in progress" do
      progress = described_class.new(project_dir, skip_persistence: true)
      expect(progress.current_step).to be_nil
    end

    it "returns current step name" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "current_step" => "03_TEST_ANALYSIS"
      })

      progress = described_class.new(project_dir)
      expect(progress.current_step).to eq("03_TEST_ANALYSIS")
    end
  end

  describe "#started_at" do
    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    it "returns nil when not started" do
      progress = described_class.new(project_dir, skip_persistence: true)
      expect(progress.started_at).to be_nil
    end

    it "returns parsed Time when started_at exists" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "started_at" => "2025-01-15T10:30:00Z"
      })

      progress = described_class.new(project_dir)
      expect(progress.started_at).to eq(Time.parse("2025-01-15T10:30:00Z"))
    end
  end

  describe "#step_completed?" do
    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    it "returns false when step not completed" do
      progress = described_class.new(project_dir, skip_persistence: true)
      expect(progress.step_completed?("01_REPOSITORY_ANALYSIS")).to be false
    end

    it "returns true when step is completed" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "completed_steps" => ["01_REPOSITORY_ANALYSIS"]
      })

      progress = described_class.new(project_dir)
      expect(progress.step_completed?("01_REPOSITORY_ANALYSIS")).to be true
    end

    it "returns false when different step is completed" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "completed_steps" => ["01_REPOSITORY_ANALYSIS"]
      })

      progress = described_class.new(project_dir)
      expect(progress.step_completed?("02_ARCHITECTURE_ANALYSIS")).to be false
    end
  end

  describe "#mark_step_completed" do
    before do
      allow(File).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    it "adds step to completed_steps" do
      progress = described_class.new(project_dir, skip_persistence: true)
      progress.mark_step_completed("01_REPOSITORY_ANALYSIS")
      expect(progress.completed_steps).to eq(["01_REPOSITORY_ANALYSIS"])
    end

    it "does not duplicate completed steps" do
      progress = described_class.new(project_dir, skip_persistence: true)
      progress.mark_step_completed("01_REPOSITORY_ANALYSIS")
      progress.mark_step_completed("01_REPOSITORY_ANALYSIS")
      expect(progress.completed_steps).to eq(["01_REPOSITORY_ANALYSIS"])
    end

    it "clears current_step" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "current_step" => "01_REPOSITORY_ANALYSIS"
      })

      progress = described_class.new(project_dir, skip_persistence: true)
      progress.mark_step_completed("01_REPOSITORY_ANALYSIS")
      expect(progress.current_step).to be_nil
    end

    it "saves progress when persistence enabled" do
      progress = described_class.new(project_dir)

      expect(FileUtils).to receive(:mkdir_p).with(File.dirname(progress_file))
      expect(File).to receive(:write).with(progress_file, anything)

      progress.mark_step_completed("01_REPOSITORY_ANALYSIS")
    end

    it "does not save when skip_persistence is true" do
      progress = described_class.new(project_dir, skip_persistence: true)

      expect(File).not_to receive(:write)

      progress.mark_step_completed("01_REPOSITORY_ANALYSIS")
    end
  end

  describe "#mark_step_in_progress" do
    before do
      allow(File).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
      allow(Time).to receive(:now).and_return(Time.parse("2025-01-15T10:30:00Z"))
    end

    it "sets current_step" do
      progress = described_class.new(project_dir, skip_persistence: true)
      progress.mark_step_in_progress("02_ARCHITECTURE_ANALYSIS")
      expect(progress.current_step).to eq("02_ARCHITECTURE_ANALYSIS")
    end

    it "sets started_at on first step" do
      progress = described_class.new(project_dir, skip_persistence: true)
      progress.mark_step_in_progress("01_REPOSITORY_ANALYSIS")
      expect(progress.started_at).to eq(Time.parse("2025-01-15T10:30:00Z"))
    end

    it "does not overwrite started_at on subsequent steps" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "started_at" => "2025-01-15T09:00:00Z"
      })

      progress = described_class.new(project_dir)
      progress.mark_step_in_progress("02_ARCHITECTURE_ANALYSIS")
      expect(progress.started_at).to eq(Time.parse("2025-01-15T09:00:00Z"))
    end

    it "saves progress when persistence enabled" do
      progress = described_class.new(project_dir)

      expect(FileUtils).to receive(:mkdir_p).with(File.dirname(progress_file))
      expect(File).to receive(:write).with(progress_file, anything)

      progress.mark_step_in_progress("01_REPOSITORY_ANALYSIS")
    end

    it "does not save when skip_persistence is true" do
      progress = described_class.new(project_dir, skip_persistence: true)

      expect(File).not_to receive(:write)

      progress.mark_step_in_progress("01_REPOSITORY_ANALYSIS")
    end
  end

  describe "#reset" do
    before do
      allow(File).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    it "clears completed_steps" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "completed_steps" => ["01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS"]
      })

      progress = described_class.new(project_dir, skip_persistence: true)
      progress.reset
      expect(progress.completed_steps).to eq([])
    end

    it "clears current_step" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "current_step" => "03_TEST_ANALYSIS"
      })

      progress = described_class.new(project_dir, skip_persistence: true)
      progress.reset
      expect(progress.current_step).to be_nil
    end

    it "clears started_at" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "started_at" => "2025-01-15T10:30:00Z"
      })

      progress = described_class.new(project_dir, skip_persistence: true)
      progress.reset
      expect(progress.started_at).to be_nil
    end

    it "saves progress when persistence enabled" do
      progress = described_class.new(project_dir)

      expect(FileUtils).to receive(:mkdir_p).with(File.dirname(progress_file))
      expect(File).to receive(:write).with(progress_file, anything)

      progress.reset
    end

    it "does not save when skip_persistence is true" do
      progress = described_class.new(project_dir, skip_persistence: true)

      expect(File).not_to receive(:write)

      progress.reset
    end
  end

  describe "#next_step" do
    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    it "returns first step when no steps completed" do
      progress = described_class.new(project_dir, skip_persistence: true)
      expect(progress.next_step).to eq("01_REPOSITORY_ANALYSIS")
    end

    it "returns second step when first is completed" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "completed_steps" => ["01_REPOSITORY_ANALYSIS"]
      })

      progress = described_class.new(project_dir)
      expect(progress.next_step).to eq("02_ARCHITECTURE_ANALYSIS")
    end

    it "returns nil when all steps completed" do
      all_steps = Aidp::Analyze::Steps::SPEC.keys
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "completed_steps" => all_steps
      })

      progress = described_class.new(project_dir)
      expect(progress.next_step).to be_nil
    end

    it "skips completed steps in middle of sequence" do
      allow(File).to receive(:exist?).with(progress_file).and_return(true)
      allow(YAML).to receive(:safe_load_file).and_return({
        "completed_steps" => ["01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS", "03_TEST_ANALYSIS"]
      })

      progress = described_class.new(project_dir)
      expect(progress.next_step).to eq("04_FUNCTIONALITY_ANALYSIS")
    end
  end
end
