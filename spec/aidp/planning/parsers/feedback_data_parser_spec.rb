# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/parsers/feedback_data_parser"
require "tempfile"
require "csv"
require "json"

RSpec.describe Aidp::Planning::Parsers::FeedbackDataParser do
  describe "#parse" do
    context "with CSV format" do
      it "parses valid CSV feedback data" do
        csv_content = <<~CSV
          id,timestamp,rating,feedback,feature
          user1,2025-01-15,5,Great product!,dashboard
          user2,2025-01-16,3,Needs work,search
        CSV

        Tempfile.create(["feedback", ".csv"]) do |file|
          file.write(csv_content)
          file.rewind

          parser = described_class.new(file_path: file.path)
          result = parser.parse

          expect(result[:format]).to eq(:csv)
          expect(result[:response_count]).to eq(2)
          expect(result[:responses]).to be_an(Array)
          expect(result[:responses].first[:respondent_id]).to eq("user1")
          expect(result[:responses].first[:rating]).to eq(5)
          expect(result[:responses].first[:feedback_text]).to eq("Great product!")
        end
      end

      it "raises error for missing file" do
        parser = described_class.new(file_path: "/nonexistent/file.csv")

        expect {
          parser.parse
        }.to raise_error(Aidp::Planning::Parsers::FeedbackDataParser::FeedbackParseError, /File not found/)
      end
    end

    context "with JSON format" do
      it "parses valid JSON array format" do
        json_content = [
          {
            "id" => "user1",
            "timestamp" => "2025-01-15",
            "rating" => 4,
            "feedback" => "Good experience"
          }
        ].to_json

        Tempfile.create(["feedback", ".json"]) do |file|
          file.write(json_content)
          file.rewind

          parser = described_class.new(file_path: file.path)
          result = parser.parse

          expect(result[:format]).to eq(:json)
          expect(result[:response_count]).to eq(1)
          expect(result[:responses].first[:respondent_id]).to eq("user1")
          expect(result[:responses].first[:rating]).to eq(4)
        end
      end

      it "parses valid JSON object with responses key" do
        json_content = {
          "survey_name" => "MVP Feedback",
          "responses" => [
            {"id" => "user1", "rating" => 5, "feedback" => "Excellent"}
          ]
        }.to_json

        Tempfile.create(["feedback", ".json"]) do |file|
          file.write(json_content)
          file.rewind

          parser = described_class.new(file_path: file.path)
          result = parser.parse

          expect(result[:format]).to eq(:json)
          expect(result[:response_count]).to eq(1)
          expect(result[:metadata][:survey_name]).to eq("MVP Feedback")
        end
      end
    end

    context "with markdown format" do
      it "parses valid markdown feedback" do
        md_content = <<~MD
          ## Response 1
          **ID:** user1
          **Rating:** 5
          **Feedback:** Great product!

          ## Response 2
          **ID:** user2
          **Rating:** 3
          More feedback here.
        MD

        Tempfile.create(["feedback", ".md"]) do |file|
          file.write(md_content)
          file.rewind

          parser = described_class.new(file_path: file.path)
          result = parser.parse

          expect(result[:format]).to eq(:markdown)
          expect(result[:response_count]).to eq(2)
        end
      end
    end

    context "with unsupported format" do
      it "raises error for unknown file extension" do
        Tempfile.create(["feedback", ".txt"]) do |file|
          expect {
            described_class.new(file_path: file.path)
          }.to raise_error(Aidp::Planning::Parsers::FeedbackDataParser::FeedbackParseError, /Unknown file extension/)
        end
      end
    end
  end

  describe "private methods" do
    describe "#parse_rating" do
      it "handles numeric ratings" do
        parser = described_class.new(file_path: "dummy.csv")

        expect(parser.send(:parse_rating, "5")).to eq(5)
        expect(parser.send(:parse_rating, "3/5")).to eq(3)
        expect(parser.send(:parse_rating, "4 stars")).to eq(4)
        expect(parser.send(:parse_rating, nil)).to be_nil
        expect(parser.send(:parse_rating, "")).to be_nil
      end
    end

    describe "#parse_tags" do
      it "handles tag parsing" do
        parser = described_class.new(file_path: "dummy.csv")

        expect(parser.send(:parse_tags, "tag1,tag2,tag3")).to eq(["tag1", "tag2", "tag3"])
        expect(parser.send(:parse_tags, ["tag1", "tag2"])).to eq(["tag1", "tag2"])
        expect(parser.send(:parse_tags, nil)).to eq([])
        expect(parser.send(:parse_tags, "")).to eq([])
      end
    end
  end
end
