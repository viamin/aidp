# frozen_string_literal: true

require "spec_helper"
require "aidp/prompts/feedback_collector"
require "aidp/database"

RSpec.describe Aidp::Prompts::FeedbackCollector do
  let(:temp_dir) { Dir.mktmpdir }
  let(:collector) { described_class.new(project_dir: temp_dir) }
  let(:template_id) { "decision_engine/condition_detection" }

  before do
    # Initialize database and run migrations for the temp project
    Aidp::Database.connection(temp_dir)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    # Close database connection
    Aidp::Database.close(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#record" do
    it "records feedback entry" do
      result = collector.record(
        template_id: template_id,
        outcome: :success,
        iterations: 5
      )

      expect(result[:success]).to be true

      entries = collector.entries(template_id: template_id)
      expect(entries.size).to eq(1)
      expect(entries.first[:outcome]).to eq("success")
      expect(entries.first[:iterations]).to eq(5)
    end

    it "records feedback with user reaction" do
      collector.record(
        template_id: template_id,
        outcome: :failure,
        iterations: 10,
        user_reaction: :negative,
        suggestions: ["Be more specific about completion criteria"]
      )

      entries = collector.entries(template_id: template_id)
      expect(entries.first[:user_reaction]).to eq("negative")
      expect(entries.first[:suggestions]).to include("Be more specific about completion criteria")
    end

    it "records feedback with context" do
      collector.record(
        template_id: template_id,
        outcome: :success,
        context: {task_type: "error_handling", error_type: "rate_limit"}
      )

      entries = collector.entries(template_id: template_id)
      expect(entries.first[:context][:task_type]).to eq("error_handling")
    end
  end

  describe "#summary" do
    context "with no feedback" do
      it "returns empty summary" do
        summary = collector.summary(template_id: template_id)

        expect(summary[:total_uses]).to eq(0)
        expect(summary[:success_rate]).to eq(0)
      end
    end

    context "with feedback entries" do
      before do
        # Record 7 successes
        7.times do |i|
          collector.record(
            template_id: template_id,
            outcome: :success,
            iterations: 3 + i,
            user_reaction: :positive
          )
        end

        # Record 3 failures
        3.times do
          collector.record(
            template_id: template_id,
            outcome: :failure,
            iterations: 15,
            user_reaction: :negative,
            suggestions: ["Add more context"]
          )
        end
      end

      it "calculates success rate" do
        summary = collector.summary(template_id: template_id)

        expect(summary[:total_uses]).to eq(10)
        expect(summary[:success_rate]).to eq(70.0)
        expect(summary[:success_count]).to eq(7)
        expect(summary[:failure_count]).to eq(3)
      end

      it "calculates average iterations" do
        summary = collector.summary(template_id: template_id)

        # Success iterations: 3,4,5,6,7,8,9 = 42
        # Failure iterations: 15,15,15 = 45
        # Total: 87 / 10 = 8.7
        expect(summary[:avg_iterations]).to be_within(0.1).of(8.7)
      end

      it "counts user reactions" do
        summary = collector.summary(template_id: template_id)

        expect(summary[:positive_reactions]).to eq(7)
        expect(summary[:negative_reactions]).to eq(3)
      end

      it "collects common suggestions" do
        summary = collector.summary(template_id: template_id)

        expect(summary[:common_suggestions]).to include("Add more context")
      end
    end
  end

  describe "#entries" do
    before do
      collector.record(template_id: "template_a", outcome: :success)
      collector.record(template_id: "template_b", outcome: :failure)
      collector.record(template_id: "template_a", outcome: :failure)
    end

    it "filters by template_id" do
      entries = collector.entries(template_id: "template_a")

      expect(entries.size).to eq(2)
      expect(entries.all? { |e| e[:template_id] == "template_a" }).to be true
    end

    it "filters by outcome" do
      entries = collector.entries(outcome: :success)

      expect(entries.size).to eq(1)
      expect(entries.first[:outcome]).to eq("success")
    end

    it "returns most recent first" do
      entries = collector.entries(template_id: "template_a")

      # Most recent entry should be the failure
      expect(entries.first[:outcome]).to eq("failure")
    end

    it "respects limit" do
      10.times { collector.record(template_id: "many", outcome: :success) }

      entries = collector.entries(template_id: "many", limit: 5)

      expect(entries.size).to eq(5)
    end
  end

  describe "#templates_needing_improvement" do
    before do
      # Template A: 90% success rate (9/10)
      9.times { collector.record(template_id: "template_a", outcome: :success) }
      collector.record(template_id: "template_a", outcome: :failure)

      # Template B: 50% success rate (5/10)
      5.times { collector.record(template_id: "template_b", outcome: :success) }
      5.times { collector.record(template_id: "template_b", outcome: :failure) }

      # Template C: 30% success rate (3/10)
      3.times { collector.record(template_id: "template_c", outcome: :success) }
      7.times { collector.record(template_id: "template_c", outcome: :failure) }

      # Template D: Only 2 uses (below threshold)
      collector.record(template_id: "template_d", outcome: :failure)
      collector.record(template_id: "template_d", outcome: :failure)
    end

    it "returns templates below success threshold" do
      templates = collector.templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)

      ids = templates.map { |t| t[:template_id] }
      expect(ids).to include("template_b")
      expect(ids).to include("template_c")
      expect(ids).not_to include("template_a")  # Above threshold
      expect(ids).not_to include("template_d")  # Below min uses
    end

    it "sorts by success rate ascending" do
      templates = collector.templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)

      expect(templates.first[:template_id]).to eq("template_c")  # 30%
      expect(templates.last[:template_id]).to eq("template_b")   # 50%
    end
  end

  describe "#clear" do
    before do
      collector.record(template_id: template_id, outcome: :success)
    end

    it "removes all feedback data" do
      result = collector.clear

      expect(result[:success]).to be true
      expect(collector.any?).to be false
    end
  end

  describe "#any?" do
    it "returns false when no feedback exists" do
      expect(collector.any?).to be false
    end

    it "returns true when feedback exists" do
      collector.record(template_id: template_id, outcome: :success)
      expect(collector.any?).to be true
    end
  end
end
