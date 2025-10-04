# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Claude Stream JSON Parsing" do
  # Test the stream parsing logic independently
  def parse_stream_json_output(output)
    return output if output.nil? || output.empty?

    lines = output.strip.split("\n")
    content_parts = []

    lines.each do |line|
      next if line.strip.empty?

      begin
        json_obj = JSON.parse(line)

        if json_obj["type"] == "content_block_delta" && json_obj["delta"] && json_obj["delta"]["text"]
          content_parts << json_obj["delta"]["text"]
        elsif json_obj["content"]&.is_a?(Array)
          json_obj["content"].each do |content_item|
            content_parts << content_item["text"] if content_item["text"]
          end
        elsif json_obj["message"] && json_obj["message"]["content"]
          if json_obj["message"]["content"].is_a?(Array)
            json_obj["message"]["content"].each do |content_item|
              content_parts << content_item["text"] if content_item["text"]
            end
          elsif json_obj["message"]["content"].is_a?(String)
            content_parts << json_obj["message"]["content"]
          end
        end
      rescue JSON::ParserError
        content_parts << line
      end
    end

    result = content_parts.join
    result.empty? ? output : result
  rescue
    output
  end

  describe "#parse_stream_json_output" do
    context "with valid stream-json output" do
      it "extracts content from content_block_delta" do
        output = '{"type":"content_block_delta","delta":{"text":"Hello"}}' + "\n" \
          '{"type":"content_block_delta","delta":{"text":" world"}}'

        result = parse_stream_json_output(output)
        expect(result).to eq("Hello world")
      end

      it "extracts content from message structure" do
        output = '{"message":{"content":[{"text":"Hello world"}]}}'

        result = parse_stream_json_output(output)
        expect(result).to eq("Hello world")
      end

      it "extracts content from array content structure" do
        output = '{"content":[{"text":"Hello"},{"text":" world"}]}'

        result = parse_stream_json_output(output)
        expect(result).to eq("Hello world")
      end

      it "handles string content in message" do
        output = '{"message":{"content":"Hello world"}}'

        result = parse_stream_json_output(output)
        expect(result).to eq("Hello world")
      end
    end

    context "with invalid JSON" do
      it "treats invalid JSON lines as plain text" do
        output = "Invalid JSON line\n" + '{"type":"content_block_delta","delta":{"text":"Valid"}}'

        result = parse_stream_json_output(output)
        expect(result).to eq("Invalid JSON lineValid")
      end

      it "handles completely invalid JSON gracefully" do
        output = "Not JSON at all"

        result = parse_stream_json_output(output)
        expect(result).to eq("Not JSON at all")
      end
    end

    context "with empty or nil input" do
      it "handles nil input" do
        result = parse_stream_json_output(nil)
        expect(result).to be_nil
      end

      it "handles empty input" do
        result = parse_stream_json_output("")
        expect(result).to eq("")
      end
    end

    context "with mixed content" do
      it "combines multiple content blocks" do
        output = '{"type":"content_block_delta","delta":{"text":"First"}}' + "\n" \
          '{"type":"content_block_delta","delta":{"text":" second"}}' + "\n" \
          '{"message":{"content":"Third"}}'

        result = parse_stream_json_output(output)
        expect(result).to eq("First secondThird")
      end
    end

    context "with real Claude stream-json examples" do
      it "handles typical Claude streaming response" do
        output = <<~JSON.strip
          {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","content":[],"model":"claude-3-5-sonnet-20241022","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":1}}}
          {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
          {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
          {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there!"}}
          {"type":"content_block_stop","index":0}
          {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":4}}
          {"type":"message_stop"}
        JSON

        result = parse_stream_json_output(output)
        expect(result).to eq("Hello there!")
      end
    end
  end
end
