# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/planning/parsers/document_parser"

RSpec.describe Aidp::Planning::Parsers::DocumentParser do
  let(:parser) { described_class.new }
  let(:mock_ai_engine) { double("AIDecisionEngine") }
  let(:parser_with_ai) { described_class.new(ai_decision_engine: mock_ai_engine) }

  describe "#parse_file" do
    context "with valid markdown file" do
      let(:temp_file) do
        file = Tempfile.new(["test", ".md"])
        file.write("# Test Document\n\n## Problem Statement\n\nSome problem\n\n## Goals\n\nSome goals")
        file.rewind
        file
      end

      after { temp_file.close; temp_file.unlink }

      it "parses file and returns structured data" do
        result = parser.parse_file(temp_file.path)

        expect(result).to be_a(Hash)
        expect(result[:path]).to eq(temp_file.path)
        expect(result[:type]).to be_a(Symbol)
        expect(result[:sections]).to be_a(Hash)
        expect(result[:raw_content]).to be_a(String)
      end

      it "extracts sections correctly" do
        result = parser.parse_file(temp_file.path)

        expect(result[:sections]).to have_key("problem_statement")
        expect(result[:sections]).to have_key("goals")
        expect(result[:sections]["problem_statement"]).to include("Some problem")
      end
    end

    context "with non-existent file" do
      it "raises ArgumentError" do
        expect {
          parser.parse_file("/nonexistent/file.md")
        }.to raise_error(ArgumentError, /File not found/)
      end
    end

    context "with AI decision engine" do
      let(:temp_file) do
        file = Tempfile.new(["prd", ".md"])
        file.write("# Product Requirements\n\n## User Stories\n\nAs a user...")
        file.rewind
        file
      end

      after { temp_file.close; temp_file.unlink }

      it "uses AI engine for document classification" do
        allow(mock_ai_engine).to receive(:decide).and_return("prd")

        result = parser_with_ai.parse_file(temp_file.path)

        expect(result[:type]).to eq(:prd)
        expect(mock_ai_engine).to have_received(:decide).with(
          hash_including(context: "document classification")
        )
      end
    end
  end

  describe "#parse_directory" do
    let(:temp_dir) { Dir.mktmpdir }

    before do
      File.write(File.join(temp_dir, "prd.md"), "# PRD\n\n## Problem\n\nTest")
      File.write(File.join(temp_dir, "design.md"), "# Design\n\n## Architecture\n\nTest")
      Dir.mkdir(File.join(temp_dir, "subdir"))
      File.write(File.join(temp_dir, "subdir", "adr.md"), "# ADR\n\n## Status\n\nAccepted")
    end

    after { FileUtils.rm_rf(temp_dir) }

    it "parses all markdown files in directory" do
      results = parser.parse_directory(temp_dir)

      expect(results).to be_an(Array)
      expect(results.size).to eq(3)
      expect(results.all? { |r| r.is_a?(Hash) }).to be true
    end

    it "includes nested files" do
      results = parser.parse_directory(temp_dir)

      paths = results.map { |r| r[:path] }
      expect(paths).to include(File.join(temp_dir, "subdir", "adr.md"))
    end

    context "with non-existent directory" do
      it "raises ArgumentError" do
        expect {
          parser.parse_directory("/nonexistent/directory")
        }.to raise_error(ArgumentError, /Directory not found/)
      end
    end
  end

  describe "document type detection" do
    let(:prd_content) { "# Product Requirements\n\n## User Stories\n\nAs a user, I want..." }
    let(:design_content) { "# Technical Design\n\n## System Architecture\n\nThe system..." }
    let(:adr_content) { "# ADR 001\n\n## Status\n\nAccepted\n\n## Context\n\nWe need..." }
    let(:task_content) { "# Tasks\n\n- [ ] Task 1\n- [x] Task 2" }

    it "detects PRD documents" do
      file = Tempfile.new(["prd", ".md"])
      file.write(prd_content)
      file.rewind

      result = parser.parse_file(file.path)
      expect(result[:type]).to eq(:prd)

      file.close
      file.unlink
    end

    it "detects design documents" do
      file = Tempfile.new(["design", ".md"])
      file.write(design_content)
      file.rewind

      result = parser.parse_file(file.path)
      expect(result[:type]).to eq(:design)

      file.close
      file.unlink
    end

    it "detects ADR documents" do
      file = Tempfile.new(["adr", ".md"])
      file.write(adr_content)
      file.rewind

      result = parser.parse_file(file.path)
      expect(result[:type]).to eq(:adr)

      file.close
      file.unlink
    end

    it "detects task list documents" do
      file = Tempfile.new(["tasks", ".md"])
      file.write(task_content)
      file.rewind

      result = parser.parse_file(file.path)
      expect(result[:type]).to eq(:task_list)

      file.close
      file.unlink
    end
  end
end
