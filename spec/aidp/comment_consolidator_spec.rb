# frozen_string_literal: true

require "spec_helper"
require "aidp/comment_consolidator"

RSpec.describe Aidp::CommentConsolidator do
  let(:repository_client) { double("RepositoryClient") }
  let(:number) { 123 }
  let(:consolidator) { described_class.new(repository_client: repository_client, number: number) }

  describe "#find_category_comment" do
    let(:progress_header) { "## 🔄 Progress Report" }

    context "when comment with category header exists" do
      let(:existing_comment) { {body: "#{progress_header}\n\nSome progress content", id: 456} }

      it "finds the comment" do
        expect(repository_client).to receive(:find_comment)
          .with(number, progress_header)
          .and_return(existing_comment)

        result = consolidator.find_category_comment(:progress)
        expect(result).to eq(existing_comment)
      end
    end

    context "when no matching comment exists" do
      it "returns nil" do
        expect(repository_client).to receive(:find_comment)
          .with(number, progress_header)
          .and_return(nil)

        result = consolidator.find_category_comment(:progress)
        expect(result).to be_nil
      end
    end

    context "with an invalid category" do
      it "raises an ArgumentError" do
        expect { consolidator.find_category_comment(:invalid) }
          .to raise_error(ArgumentError, "Invalid category: invalid")
      end
    end
  end

  describe "#consolidate_comment" do
    context "when no existing comment" do
      it "creates a new comment with the category header" do
        expect(repository_client).to receive(:find_comment)
          .with(number, "## 🔄 Progress Report")
          .and_return(nil)

        expect(repository_client).to receive(:post_comment)
          .with(number, satisfy { |body|
            body.include?("## 🔄 Progress Report") &&
            body.include?("New progress update")
          })
          .and_return("new_comment_id")

        result = consolidator.consolidate_comment(
          category: :progress,
          new_content: "New progress update"
        )

        expect(result).to eq("new_comment_id")
      end
    end

    context "when existing comment exists" do
      let(:existing_comment) { {body: "## 🔄 Progress Report\n\nExisting content", id: 789} }

      it "updates the existing comment by appending" do
        expect(repository_client).to receive(:find_comment)
          .with(number, "## 🔄 Progress Report")
          .and_return(existing_comment)

        expect(repository_client).to receive(:update_comment)
          .with(789, satisfy { |body|
            body.include?("## 🔄 Progress Report") &&
            body.include?("Existing content") &&
            body.include?("New progress update")
          })
          .and_return("updated_comment_id")

        result = consolidator.consolidate_comment(
          category: :progress,
          new_content: "New progress update"
        )

        expect(result).to eq("updated_comment_id")
      end

      it "replaces the existing comment when append is false" do
        expect(repository_client).to receive(:find_comment)
          .with(number, "## 🔄 Progress Report")
          .and_return(existing_comment)

        expect(repository_client).to receive(:update_comment)
          .with(789, satisfy { |body|
            body.include?("## 🔄 Progress Report") &&
            body.include?("New progress update") &&
            !body.include?("Existing content")
          })
          .and_return("updated_comment_id")

        result = consolidator.consolidate_comment(
          category: :progress,
          new_content: "New progress update",
          append: false
        )

        expect(result).to eq("updated_comment_id")
      end
    end

    context "with an invalid category" do
      it "raises an ArgumentError" do
        expect {
          consolidator.consolidate_comment(category: :invalid, new_content: "Test")
        }.to raise_error(ArgumentError, "Invalid category: invalid")
      end
    end
  end
end
