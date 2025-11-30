# frozen_string_literal: true

require "spec_helper"
require "json"
require "time"

RSpec.describe Aidp::Watch::RepositoryClient do
  let(:owner) { "testowner" }
  let(:repo) { "testrepo" }
  let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

  describe "#consolidate_category_comment" do
    before do
      allow(client).to receive(:find_comment).and_return(nil)
      allow(client).to receive(:post_comment).and_return(true)
      allow(client).to receive(:update_comment).and_return(true)
      allow(Aidp).to receive(:log_debug)
      allow(Aidp).to receive(:log_error)
      allow(Time).to receive(:now).and_return(Time.parse("2023-11-27T12:00:00Z"))
    end

    let(:issue_number) { 42 }
    let(:category_header) { "## 🤖 AIDP Test Header" }
    let(:initial_content) { "Initial test content" }
    let(:update_content) { "Updated test content" }

    context "when creating a new comment" do
      it "creates a comment with the specified header and content" do
        client.consolidate_category_comment(issue_number, category_header, initial_content)
        expect(client).to have_received(:post_comment).with(issue_number, "#{category_header}\n\n#{initial_content}")
      end
    end

    context "when updating an existing comment without append" do
      let(:existing_comment) { {id: 100, body: "#{category_header}\n\nOld content"} }

      before do
        allow(client).to receive(:find_comment).and_return(existing_comment)
      end

      it "replaces existing content and archives previous content" do
        client.consolidate_category_comment(issue_number, category_header, update_content)

        expect(client).to have_received(:update_comment).with(
          100,
          a_string_including(category_header) &&
          a_string_including(update_content) &&
          a_string_including("<!-- ARCHIVED_PLAN_START 2023-11-27T12:00:00Z ARCHIVED_PLAN_END -->") &&
          a_string_including("Old content")
        )
      end
    end

    context "when updating an existing comment with append" do
      let(:existing_comment) { {id: 100, body: "#{category_header}\n\nOld content"} }

      before do
        allow(client).to receive(:find_comment).and_return(existing_comment)
      end

      it "appends new content to existing content" do
        client.consolidate_category_comment(issue_number, category_header, update_content, append: true)

        expect(client).to have_received(:update_comment).with(
          100,
          a_string_including(category_header) &&
          a_string_including("Old content") &&
          a_string_including(update_content)
        )
      end
    end

    context "when an error occurs" do
      it "logs the error and raises a RuntimeError" do
        allow(client).to receive(:find_comment).and_raise(StandardError.new("Test error"))

        expect(Aidp).to receive(:log_error)

        expect do
          client.consolidate_category_comment(issue_number, category_header, initial_content)
        end.to raise_error(RuntimeError, /GitHub error/)
      end
    end
  end
end
