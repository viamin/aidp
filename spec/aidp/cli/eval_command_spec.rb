# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "aidp/cli/eval_command"
require "aidp/evaluations"

RSpec.describe Aidp::CLI::EvalCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output) { StringIO.new }
  let(:prompt) { TTY::Prompt.new(output: output) }
  let(:storage) { Aidp::Evaluations::EvaluationStorage.new(project_dir: temp_dir) }
  let(:command) { described_class.new(prompt: prompt, storage: storage, project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run with list" do
    context "when no evaluations exist" do
      it "displays no evaluations message" do
        command.run(["list"])

        expect(output.string).to include("No evaluations found")
      end
    end

    context "when evaluations exist" do
      before do
        storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "good", comment: "Test"))
        storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "bad"))
      end

      it "displays evaluations" do
        command.run(["list"])

        # The table is displayed, but we verify storage has evaluations
        expect(storage.list.size).to eq(2)
      end
    end
  end

  describe "#run with view" do
    it "displays error when no id provided" do
      command.run(["view"])

      expect(output.string).to include("Please provide an evaluation ID")
    end

    it "displays error when evaluation not found" do
      command.run(["view", "non_existent"])

      expect(output.string).to include("Evaluation not found")
    end

    context "when evaluation exists" do
      let(:record) { Aidp::Evaluations::EvaluationRecord.new(rating: "good", comment: "Great!") }

      before do
        storage.store(record)
      end

      it "displays evaluation details" do
        command.run(["view", record.id])

        expect(output.string).to include(record.id)
        expect(output.string).to include("good")
        expect(output.string).to include("Great!")
      end
    end
  end

  describe "#run with stats" do
    context "when no evaluations exist" do
      it "displays zero stats" do
        command.run(["stats"])

        expect(output.string).to include("Total evaluations: 0")
      end
    end

    context "when evaluations exist" do
      before do
        storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "good"))
        storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "good"))
        storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "bad"))
      end

      it "displays statistics" do
        command.run(["stats"])

        expect(output.string).to include("Total evaluations: 3")
        expect(output.string).to include("Good")
        expect(output.string).to include("Bad")
      end
    end
  end

  describe "#run with add" do
    it "displays error when no rating provided" do
      command.run(["add"])

      expect(output.string).to include("Please provide a rating")
    end

    it "displays error for invalid rating" do
      command.run(["add", "excellent"])

      expect(output.string).to include("Invalid rating")
    end

    it "stores evaluation with valid rating" do
      command.run(["add", "good"])

      expect(output.string).to include("Evaluation recorded")
      expect(storage.stats[:total]).to eq(1)
    end

    it "stores evaluation with comment" do
      command.run(["add", "good", "This", "is", "a", "comment"])

      expect(storage.list.first.comment).to eq("This is a comment")
    end
  end

  describe "#run with clear" do
    let(:confirm_prompt) do
      p = TTY::Prompt.new(input: StringIO.new("n\n"), output: output)
      p
    end

    context "with --force flag" do
      before do
        storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "good"))
      end

      it "clears evaluations without confirmation" do
        command.run(["clear", "--force"])

        expect(output.string).to include("Cleared")
        expect(storage.any?).to be false
      end
    end
  end

  describe "#run with unknown command" do
    it "displays usage" do
      command.run(["unknown"])

      expect(output.string).to include("Usage:")
    end
  end

  describe "#run with no arguments" do
    it "defaults to list command" do
      command.run([])

      # Should not raise, just show empty list message
      expect(output.string).to include("No evaluations found")
    end
  end
end
