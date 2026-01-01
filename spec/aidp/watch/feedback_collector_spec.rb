# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::FeedbackCollector do
  let(:repository_client) { instance_double("RepositoryClient", full_repo: "owner/repo") }
  let(:state_store) { instance_double("StateStore") }
  let(:evaluation_storage) { instance_double("EvaluationStorage") }
  let(:project_dir) { Dir.mktmpdir }

  before do
    allow(Aidp::Evaluations::EvaluationStorage).to receive(:new).and_return(evaluation_storage)
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_error)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#initialize" do
    it "creates a feedback collector with required dependencies" do
      collector = described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_dir: project_dir
      )

      expect(collector).to be_a(described_class)
    end
  end

  describe "#collect_feedback" do
    subject(:collector) do
      described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_dir: project_dir
      )
    end

    context "when no comments are tracked" do
      before do
        allow(state_store).to receive(:tracked_comments).and_return([])
      end

      it "returns empty array" do
        expect(collector.collect_feedback).to eq([])
      end
    end

    context "when comments are tracked" do
      let(:tracked_comments) do
        [
          {comment_id: 123, processor_type: "plan", number: 1},
          {comment_id: 456, processor_type: "build", number: 2}
        ]
      end

      before do
        allow(state_store).to receive(:tracked_comments).and_return(tracked_comments)
        allow(repository_client).to receive(:fetch_comment_reactions).and_return([])
        allow(state_store).to receive(:processed_reaction_ids).and_return([])
      end

      it "processes each tracked comment" do
        expect(repository_client).to receive(:fetch_comment_reactions).with(123)
        expect(repository_client).to receive(:fetch_comment_reactions).with(456)

        collector.collect_feedback
      end
    end
  end

  describe "#process_comment_reactions" do
    subject(:collector) do
      described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_dir: project_dir
      )
    end

    let(:comment_info) { {comment_id: 123, processor_type: "plan", number: 1} }

    context "when comment has no reactions" do
      before do
        allow(repository_client).to receive(:fetch_comment_reactions).and_return([])
        allow(state_store).to receive(:processed_reaction_ids).and_return([])
      end

      it "returns empty array" do
        expect(collector.process_comment_reactions(comment_info)).to eq([])
      end
    end

    context "when comment has new reactions" do
      let(:reactions) do
        [
          {id: 1, content: "+1", user: "alice", created_at: "2024-01-01T00:00:00Z"},
          {id: 2, content: "-1", user: "bob", created_at: "2024-01-01T00:00:01Z"}
        ]
      end

      let(:evaluation_record) { instance_double("EvaluationRecord", id: "eval_123") }

      before do
        allow(repository_client).to receive(:fetch_comment_reactions).and_return(reactions)
        allow(state_store).to receive(:processed_reaction_ids).and_return([])
        allow(state_store).to receive(:mark_reaction_processed)
        allow(Aidp::Evaluations::EvaluationRecord).to receive(:new).and_return(evaluation_record)
        allow(evaluation_storage).to receive(:store).and_return({success: true})
      end

      it "creates evaluations for each reaction" do
        expect(evaluation_storage).to receive(:store).twice
        collector.process_comment_reactions(comment_info)
      end

      it "marks reactions as processed" do
        expect(state_store).to receive(:mark_reaction_processed).with(123, 1)
        expect(state_store).to receive(:mark_reaction_processed).with(123, 2)

        collector.process_comment_reactions(comment_info)
      end

      it "returns evaluation info for each new reaction" do
        result = collector.process_comment_reactions(comment_info)
        expect(result.size).to eq(2)
        expect(result.first[:rating]).to eq("good")
        expect(result.last[:rating]).to eq("bad")
      end
    end

    context "when reactions are already processed" do
      let(:reactions) do
        [{id: 1, content: "+1", user: "alice", created_at: "2024-01-01T00:00:00Z"}]
      end

      before do
        allow(repository_client).to receive(:fetch_comment_reactions).and_return(reactions)
        allow(state_store).to receive(:processed_reaction_ids).and_return([1])
      end

      it "skips already processed reactions" do
        expect(evaluation_storage).not_to receive(:store)
        result = collector.process_comment_reactions(comment_info)
        expect(result).to eq([])
      end
    end

    context "when reaction is not mappable to rating" do
      let(:reactions) do
        [{id: 1, content: "unknown_emoji", user: "alice", created_at: "2024-01-01T00:00:00Z"}]
      end

      before do
        allow(repository_client).to receive(:fetch_comment_reactions).and_return(reactions)
        allow(state_store).to receive(:processed_reaction_ids).and_return([])
      end

      it "skips unmappable reactions" do
        expect(evaluation_storage).not_to receive(:store)
        result = collector.process_comment_reactions(comment_info)
        expect(result).to eq([])
      end
    end

    context "when evaluation storage fails" do
      let(:reactions) do
        [{id: 1, content: "+1", user: "alice", created_at: "2024-01-01T00:00:00Z"}]
      end

      let(:evaluation_record) { instance_double("EvaluationRecord", id: "eval_123") }

      before do
        allow(repository_client).to receive(:fetch_comment_reactions).and_return(reactions)
        allow(state_store).to receive(:processed_reaction_ids).and_return([])
        allow(Aidp::Evaluations::EvaluationRecord).to receive(:new).and_return(evaluation_record)
        allow(evaluation_storage).to receive(:store).and_return({success: false, error: "Storage error"})
      end

      it "does not mark reaction as processed" do
        expect(state_store).not_to receive(:mark_reaction_processed)
        collector.process_comment_reactions(comment_info)
      end

      it "returns empty array" do
        result = collector.process_comment_reactions(comment_info)
        expect(result).to eq([])
      end
    end
  end

  describe "#reaction_to_rating" do
    subject(:collector) do
      described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_dir: project_dir
      )
    end

    it "maps +1 to good" do
      expect(collector.reaction_to_rating("+1")).to eq("good")
    end

    it "maps -1 to bad" do
      expect(collector.reaction_to_rating("-1")).to eq("bad")
    end

    it "maps confused to neutral" do
      expect(collector.reaction_to_rating("confused")).to eq("neutral")
    end

    it "maps heart to good" do
      expect(collector.reaction_to_rating("heart")).to eq("good")
    end

    it "maps hooray to good" do
      expect(collector.reaction_to_rating("hooray")).to eq("good")
    end

    it "maps rocket to good" do
      expect(collector.reaction_to_rating("rocket")).to eq("good")
    end

    it "maps eyes to neutral" do
      expect(collector.reaction_to_rating("eyes")).to eq("neutral")
    end

    it "returns nil for unknown reactions" do
      expect(collector.reaction_to_rating("unknown")).to be_nil
    end
  end

  describe ".append_feedback_prompt" do
    it "appends feedback prompt to comment body" do
      body = "This is a comment"
      result = described_class.append_feedback_prompt(body)

      expect(result).to include(body)
      expect(result).to include("Rate this output")
      expect(result).to include("React with")
    end

    it "separates prompt with blank lines" do
      body = "Comment"
      result = described_class.append_feedback_prompt(body)

      expect(result).to start_with("Comment\n\n")
    end
  end

  describe "REACTION_RATINGS constant" do
    it "defines expected reaction mappings" do
      expect(described_class::REACTION_RATINGS).to eq({
        "+1" => "good",
        "-1" => "bad",
        "confused" => "neutral",
        "heart" => "good",
        "hooray" => "good",
        "rocket" => "good",
        "eyes" => "neutral"
      })
    end

    it "is frozen" do
      expect(described_class::REACTION_RATINGS).to be_frozen
    end
  end

  describe "FEEDBACK_PROMPT constant" do
    it "includes rating instructions" do
      expect(described_class::FEEDBACK_PROMPT).to include("Rate this output")
    end

    it "mentions emoji reactions" do
      expect(described_class::FEEDBACK_PROMPT).to include("good")
      expect(described_class::FEEDBACK_PROMPT).to include("bad")
      expect(described_class::FEEDBACK_PROMPT).to include("neutral")
    end
  end
end
