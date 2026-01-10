# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::PromptFeedbackRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_prompt_feedback_repo_test") }
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db") }
  let(:repository) { described_class.new(project_dir: temp_dir) }

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#record" do
    let(:feedback_data) do
      {
        template_id: "decision_engine/condition_detection",
        outcome: :success,
        iterations: 3,
        user_reaction: :positive,
        suggestions: ["Add more examples"],
        context: {task: "test"}
      }
    end

    it "creates a new feedback record" do
      result = repository.record(feedback_data)

      expect(result[:success]).to be true
      expect(result[:id]).to be_a(Integer)
    end

    it "handles failure outcome" do
      result = repository.record(feedback_data.merge(outcome: :failure))

      expect(result[:success]).to be true
    end

    it "handles nil optional fields" do
      result = repository.record(
        template_id: "test/template",
        outcome: :success
      )

      expect(result[:success]).to be true
    end
  end

  describe "#summary" do
    let(:template_id) { "test/template" }

    context "with no feedback" do
      it "returns empty summary" do
        summary = repository.summary(template_id: template_id)

        expect(summary[:total_uses]).to eq(0)
        expect(summary[:success_rate]).to eq(0)
        expect(summary[:success_count]).to eq(0)
        expect(summary[:failure_count]).to eq(0)
      end
    end

    context "with feedback entries" do
      before do
        # Add 3 success and 2 failure
        3.times { repository.record(template_id: template_id, outcome: :success, iterations: 2) }
        2.times { repository.record(template_id: template_id, outcome: :failure, iterations: 4) }
      end

      it "calculates total uses" do
        summary = repository.summary(template_id: template_id)

        expect(summary[:total_uses]).to eq(5)
      end

      it "calculates success rate" do
        summary = repository.summary(template_id: template_id)

        expect(summary[:success_rate]).to eq(60.0)
      end

      it "counts success and failures" do
        summary = repository.summary(template_id: template_id)

        expect(summary[:success_count]).to eq(3)
        expect(summary[:failure_count]).to eq(2)
      end

      it "calculates average iterations" do
        summary = repository.summary(template_id: template_id)

        # (3*2 + 2*4) / 5 = 14/5 = 2.8
        expect(summary[:avg_iterations]).to eq(2.8)
      end
    end

    context "with user reactions" do
      before do
        repository.record(template_id: template_id, outcome: :success, user_reaction: :positive)
        repository.record(template_id: template_id, outcome: :success, user_reaction: :positive)
        repository.record(template_id: template_id, outcome: :failure, user_reaction: :negative)
      end

      it "counts reactions" do
        summary = repository.summary(template_id: template_id)

        expect(summary[:positive_reactions]).to eq(2)
        expect(summary[:negative_reactions]).to eq(1)
      end
    end

    context "with suggestions" do
      before do
        repository.record(template_id: template_id, outcome: :success, suggestions: ["suggestion 1"])
        repository.record(template_id: template_id, outcome: :success, suggestions: ["suggestion 2", "suggestion 1"])
      end

      it "collects unique suggestions" do
        summary = repository.summary(template_id: template_id)

        expect(summary[:common_suggestions]).to include("suggestion 1")
        expect(summary[:common_suggestions]).to include("suggestion 2")
      end
    end
  end

  describe "#list" do
    before do
      repository.record(template_id: "template_a", outcome: :success)
      repository.record(template_id: "template_b", outcome: :failure)
      repository.record(template_id: "template_a", outcome: :failure)
    end

    it "lists all entries" do
      entries = repository.list

      expect(entries.size).to eq(3)
    end

    it "filters by template_id" do
      entries = repository.list(template_id: "template_a")

      expect(entries.size).to eq(2)
      expect(entries.all? { |e| e[:template_id] == "template_a" }).to be true
    end

    it "filters by outcome" do
      entries = repository.list(outcome: :success)

      expect(entries.size).to eq(1)
      expect(entries.first[:outcome]).to eq("success")
    end

    it "respects limit" do
      entries = repository.list(limit: 2)

      expect(entries.size).to eq(2)
    end

    it "returns most recent first" do
      entries = repository.list(template_id: "template_a")

      # Most recently inserted should be first (failure)
      expect(entries.first[:outcome]).to eq("failure")
    end
  end

  describe "#templates_needing_improvement" do
    before do
      # Template with 80% success (above threshold)
      4.times { repository.record(template_id: "good_template", outcome: :success) }
      1.times { repository.record(template_id: "good_template", outcome: :failure) }

      # Template with 40% success (below threshold)
      2.times { repository.record(template_id: "bad_template", outcome: :success) }
      3.times { repository.record(template_id: "bad_template", outcome: :failure) }

      # Template with too few uses
      repository.record(template_id: "new_template", outcome: :failure)
    end

    it "returns templates below success threshold" do
      templates = repository.templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)

      expect(templates.size).to eq(1)
      expect(templates.first[:template_id]).to eq("bad_template")
    end

    it "excludes templates with too few uses" do
      templates = repository.templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)

      template_ids = templates.map { |t| t[:template_id] }
      expect(template_ids).not_to include("new_template")
    end

    it "sorts by success rate ascending" do
      # Add another bad template with worse rate
      5.times { repository.record(template_id: "worst_template", outcome: :failure) }

      templates = repository.templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)

      expect(templates.first[:template_id]).to eq("worst_template")
    end
  end

  describe "#clear" do
    before do
      repository.record(template_id: "test", outcome: :success)
      repository.record(template_id: "test", outcome: :failure)
    end

    it "removes all feedback" do
      result = repository.clear

      expect(result[:success]).to be true
      expect(result[:count]).to eq(2)
    end

    it "leaves repository empty" do
      repository.clear

      expect(repository.list).to be_empty
    end
  end

  describe "#any?" do
    it "returns false when empty" do
      expect(repository.any?).to be false
    end

    it "returns true when has feedback" do
      repository.record(template_id: "test", outcome: :success)

      expect(repository.any?).to be true
    end
  end
end
