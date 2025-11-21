# frozen_string_literal: true

require "open3"
require "tempfile"
require "json"

module Aidp
  module Watch
    # Intelligently extracts relevant failure information from CI logs
    # to reduce token usage when analyzing failures with AI.
    #
    # Instead of feeding full CI output to AI, this creates a tailored
    # extraction script for each failure type, runs it, and provides
    # only the relevant excerpts.
    class CiLogExtractor
      # Maximum size for extracted log content (in characters)
      MAX_EXTRACTED_SIZE = 10_000

      def initialize(provider_manager:)
        @provider_manager = provider_manager
      end

      # Extract relevant failure information from a CI check
      #
      # @param check [Hash] Failed check information
      # @param check_run_url [String] URL to the GitHub Actions run (optional)
      # @return [Hash] Extracted failure info with :summary, :details, :script_used
      def extract_failure_info(check:, check_run_url: nil)
        Aidp.log_debug("ci_log_extractor", "extract_start",
          check_name: check[:name],
          has_output: !check[:output].nil?)

        # If we have structured output from the check, use it
        if check[:output] && check[:output]["summary"]
          return extract_from_structured_output(check)
        end

        # If we have a check run URL, fetch the logs
        if check_run_url
          raw_logs = fetch_check_logs(check_run_url)
          return extract_from_raw_logs(check: check, raw_logs: raw_logs) if raw_logs
        end

        # Fallback: minimal information
        {
          summary: "Check '#{check[:name]}' failed",
          details: check[:output]&.dig("text") || "No additional details available",
          extraction_method: "fallback"
        }
      end

      private

      def extract_from_structured_output(check)
        summary = check[:output]["summary"] || ""
        text = check[:output]["text"] || ""

        # If the output is already concise, return it directly
        full_output = "#{summary}\n\n#{text}".strip
        if full_output.length <= MAX_EXTRACTED_SIZE
          return {
            summary: summary,
            details: text,
            extraction_method: "structured"
          }
        end

        # Output is too large, create extraction script
        extraction_result = create_and_run_extraction_script(
          check_name: check[:name],
          raw_content: full_output
        )

        {
          summary: summary,
          details: extraction_result[:extracted_content],
          extraction_method: "ai_script",
          script_used: extraction_result[:script]
        }
      end

      def extract_from_raw_logs(check:, raw_logs:)
        # If logs are already concise, return them
        if raw_logs.length <= MAX_EXTRACTED_SIZE
          return {
            summary: "Check '#{check[:name]}' failed",
            details: raw_logs,
            extraction_method: "raw"
          }
        end

        # Logs are too large, create extraction script
        extraction_result = create_and_run_extraction_script(
          check_name: check[:name],
          raw_content: raw_logs
        )

        {
          summary: "Check '#{check[:name]}' failed",
          details: extraction_result[:extracted_content],
          extraction_method: "ai_script",
          script_used: extraction_result[:script]
        }
      end

      def create_and_run_extraction_script(check_name:, raw_content:)
        Aidp.log_debug("ci_log_extractor", "creating_script",
          check_name: check_name,
          content_size: raw_content.length)

        # Ask AI to create an extraction script
        script = generate_extraction_script(
          check_name: check_name,
          sample_content: truncate_sample(raw_content)
        )

        # Run the script
        extracted = run_extraction_script(script: script, input: raw_content)

        {
          extracted_content: extracted,
          script: script
        }
      rescue => e
        Aidp.log_warn("ci_log_extractor", "script_execution_failed",
          error: e.message,
          check_name: check_name)

        # Fallback: simple head/tail extraction
        {
          extracted_content: simple_extract(raw_content),
          script: nil
        }
      end

      def generate_extraction_script(check_name:, sample_content:)
        prompt = <<~PROMPT
          Create a shell script that extracts relevant failure information from CI logs.

          The script should:
          1. Read from STDIN
          2. Extract ONLY the relevant error messages, failed tests, and stack traces
          3. Omit verbose output, successful tests, and build information
          4. Keep the extracted output under #{MAX_EXTRACTED_SIZE} characters
          5. Output the extracted content to STDOUT

          Check type: #{check_name}

          Sample of the log content (first ~2000 chars):
          ```
          #{sample_content}
          ```

          Requirements:
          - Use standard Unix tools (grep, awk, sed, head, tail)
          - Handle multi-line error messages
          - Focus on actionable error information
          - If it's a test failure, extract test names and failure messages
          - If it's a linting error, extract file names, line numbers, and violations

          Respond ONLY with the shell script code, no explanation.
          The script must be a valid bash script that reads STDIN.

          Example format:
          #!/bin/bash
          grep -A 5 "FAILED" | head -n 100
        PROMPT

        response = @provider_manager.send_message(prompt: prompt)
        extract_script_from_response(response.to_s)
      end

      def extract_script_from_response(response)
        # Remove markdown code fences if present
        script = response.strip
        script = script.gsub(/^```(?:bash|sh)?\n/, "")
        script = script.gsub(/\n```$/, "")

        # Ensure it starts with shebang
        unless script.start_with?("#!/")
          script = "#!/bin/bash\n#{script}"
        end

        script
      end

      def run_extraction_script(script:, input:)
        Tempfile.create(["ci_extract", ".sh"]) do |script_file|
          script_file.write(script)
          script_file.flush
          script_file.chmod(0o755)

          stdout, stderr, status = Open3.capture3(
            "bash", script_file.path,
            stdin_data: input,
            chdir: Dir.tmpdir
          )

          unless status.success?
            Aidp.log_warn("ci_log_extractor", "script_failed",
              exit_code: status.exitstatus,
              stderr: stderr[0, 500])
            return simple_extract(input)
          end

          # Ensure output is within size limit
          truncate_to_size(stdout)
        end
      end

      def fetch_check_logs(check_run_url)
        # TODO: Implement fetching logs from GitHub Actions
        # This would require parsing the check run URL and using gh CLI or API
        # For now, return nil to use structured output
        nil
      end

      def truncate_sample(content, size: 2000)
        return content if content.length <= size
        "#{content[0, size]}\n... [truncated]"
      end

      def simple_extract(content)
        # Simple fallback: extract lines containing error keywords
        lines = content.lines
        error_lines = lines.select do |line|
          line.match?(/error|fail|exception|assert/i)
        end

        # If we found error lines, return them with context
        if error_lines.any?
          # Get line numbers of errors and include surrounding context
          result = []
          lines.each_with_index do |line, i|
            if line.match?(/error|fail|exception|assert/i)
              # Include 2 lines before and 3 lines after
              start_idx = [0, i - 2].max
              end_idx = [lines.length - 1, i + 3].min
              result.concat(lines[start_idx..end_idx])
            end
          end

          truncate_to_size(result.uniq.join)
        else
          # No clear errors, return head and tail
          head = lines.first(50).join
          tail = lines.last(50).join
          truncate_to_size("=== First 50 lines ===\n#{head}\n\n=== Last 50 lines ===\n#{tail}")
        end
      end

      def truncate_to_size(content, size: MAX_EXTRACTED_SIZE)
        return content if content.length <= size
        "#{content[0, size - 20]}\n... [truncated]"
      end
    end
  end
end
