# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::CiLogExtractor do
  let(:mock_provider) do
    double("ProviderManager").tap do |provider|
      allow(provider).to receive(:send_message).and_return(mock_extraction_script)
    end
  end

  let(:mock_extraction_script) do
    <<~SCRIPT
      #!/bin/bash
      grep -i "error\\|fail" | head -n 20
    SCRIPT
  end

  subject(:extractor) { described_class.new(provider_manager: mock_provider) }

  describe "#extract_failure_info" do
    context "with structured output from check" do
      let(:check) do
        {
          name: "test / rspec",
          conclusion: "failure",
          output: {
            "summary" => "3 tests failed",
            "text" => "Failure details here"
          }
        }
      end

      it "uses structured output directly when small enough" do
        result = extractor.extract_failure_info(check: check)

        expect(result[:summary]).to eq("3 tests failed")
        expect(result[:details]).to eq("Failure details here")
        expect(result[:extraction_method]).to eq("structured")
      end

      it "applies extraction script when output is too large" do
        large_text = "x" * 15_000
        check[:output]["text"] = large_text

        result = extractor.extract_failure_info(check: check)

        expect(["ai_script", "structured"]).to include(result[:extraction_method])
        expect(result[:details].length).to be <= described_class::MAX_EXTRACTED_SIZE
      end
    end

    context "without structured output" do
      let(:check) do
        {
          name: "lint / standardrb",
          conclusion: "failure",
          output: nil,
          details_url: "https://github.com/test/repo/actions/runs/123"
        }
      end

      it "falls back to minimal information" do
        result = extractor.extract_failure_info(check: check)

        expect(result[:summary]).to include("lint / standardrb")
        expect(result[:extraction_method]).to eq("fallback")
      end
    end

    context "with raw logs" do
      let(:raw_logs) do
        <<~LOGS
          Running tests...
          Test 1: PASSED
          Test 2: PASSED
          Test 3: FAILED
          Error: Expected true, got false
          Stack trace:
            at test.rb:42
            at runner.rb:100
          Test 4: PASSED
        LOGS
      end

      it "extracts relevant failure lines" do
        allow(extractor).to receive(:fetch_check_logs).and_return(raw_logs)

        check = {
          name: "test / unit",
          conclusion: "failure",
          details_url: "https://github.com/test/repo/actions/runs/456"
        }

        result = extractor.extract_failure_info(check: check, check_run_url: check[:details_url])

        expect(result[:details]).to include("FAILED")
        expect(result[:details]).to include("Error")
      end
    end
  end

  describe "simple extraction fallback" do
    it "extracts error lines with context" do
      content = <<~CONTENT
        Line 1
        Line 2
        Line 3
        ERROR: Something went wrong
        Line 5
        Line 6
        Line 7
        FAILURE: Another issue
        Line 9
      CONTENT

      result = extractor.send(:simple_extract, content)

      expect(result).to include("ERROR")
      expect(result).to include("FAILURE")
      # Should include context lines
      expect(result).to include("Line 2") # Context before error
      expect(result).to include("Line 7") # Context after first error
    end

    it "provides head and tail when no clear errors" do
      lines = (1..200).map { |i| "Line #{i}" }
      content = lines.join("\n")

      result = extractor.send(:simple_extract, content)

      expect(result).to include("First 50 lines")
      expect(result).to include("Last 50 lines")
      expect(result).to include("Line 1")
      expect(result).to include("Line 200")
    end
  end

  describe "truncation" do
    it "truncates content exceeding max size" do
      large_content = "x" * (described_class::MAX_EXTRACTED_SIZE + 1000)

      result = extractor.send(:truncate_to_size, large_content)

      expect(result.length).to be <= described_class::MAX_EXTRACTED_SIZE
      expect(result).to include("[truncated]")
    end

    it "does not truncate content within size limit" do
      small_content = "Small content"

      result = extractor.send(:truncate_to_size, small_content)

      expect(result).to eq(small_content)
      expect(result).not_to include("[truncated]")
    end
  end

  describe "script extraction from AI response" do
    it "extracts script from markdown code fence" do
      response = <<~RESPONSE
        Here's the extraction script:
        ```bash
        #!/bin/bash
        grep ERROR | head -n 50
        ```
      RESPONSE

      result = extractor.send(:extract_script_from_response, response)

      expect(result).to include("#!/bin/bash")
      expect(result).to include("grep ERROR")
      expect(result).not_to include("```")
    end

    it "adds shebang if missing" do
      response = "grep ERROR | head -n 50"

      result = extractor.send(:extract_script_from_response, response)

      expect(result).to start_with("#!/")
    end
  end
end
