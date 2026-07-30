# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tmpdir"
require "fileutils"
require "pathname"

module Aidp
  module StrategyExecution
    module CliProtocol
      class ProtocolError < StandardError; end

      class Runner
        PROTOCOL_VERSION = "1.0"

        def initialize(project_dir: Dir.pwd)
          @project_dir = project_dir
        end

        def execute(command:, role:, request:)
          artifact_dir = create_artifact_dir(role)
          payload = request.merge(
            protocol_version: PROTOCOL_VERSION,
            role: role,
            artifact_dir: artifact_dir
          )

          Aidp.log_debug("cli_protocol", "executing",
            role: role,
            command: command.is_a?(Array) ? command.first : Shellwords.split(command.to_s).first,
            task_id: request[:task]&.dig(:id),
            artifact_dir: artifact_dir)

          stdout, stderr, status = Open3.capture3(*command_parts(command), stdin_data: JSON.generate(payload), chdir: @project_dir)
          unless status.success?
            Aidp.log_error("cli_protocol", "execution_failed",
              role: role,
              command: command.is_a?(Array) ? command.first : Shellwords.split(command.to_s).first,
              exit_status: status.exitstatus,
              stderr: stderr.to_s.strip)
            raise ProtocolError, stderr.strip
          end

          response = JSON.parse(stdout, symbolize_names: true)
          validate_response!(response, role)

          response.merge(
            artifacts: normalize_artifacts(response[:artifacts], artifact_dir),
            artifact_dir: artifact_dir,
            stderr: stderr
          )
        rescue JSON::ParserError => e
          Aidp.log_error("cli_protocol", "invalid_response",
            role: role,
            error: e.message)
          raise ProtocolError, "Invalid JSON response: #{e.message}"
        rescue ProtocolError
          raise
        rescue Errno::ENOENT, Errno::EACCES => e
          Aidp.log_error("cli_protocol", "execution_failed",
            role: role,
            command: command.is_a?(Array) ? command.first : Shellwords.split(command.to_s).first,
            error: e.message,
            error_class: e.class.name)
          raise ProtocolError, "Command failed: #{e.message}"
        end

        private

        def command_parts(command)
          case command
          when Array then command
          else Shellwords.split(command.to_s)
          end
        end

        def create_artifact_dir(role)
          base_dir = File.join(@project_dir, ".aidp")
          FileUtils.mkdir_p(base_dir)
          dir = Dir.mktmpdir("aidp-#{role}-", base_dir)
          FileUtils.mkdir_p(dir)
          dir
        end

        def normalize_artifacts(artifacts, artifact_dir)
          expanded_artifact_dir = File.expand_path(artifact_dir)

          Array(artifacts).map do |artifact|
            next artifact unless artifact.is_a?(String)

            expanded_path = File.expand_path(artifact, expanded_artifact_dir)
            validate_artifact_path!(artifact, expanded_path, expanded_artifact_dir)
            expanded_path
          end
        end

        def validate_artifact_path!(artifact, expanded_path, artifact_dir)
          return if expanded_path == artifact_dir
          return if expanded_path.start_with?("#{artifact_dir}#{File::SEPARATOR}")

          raise ProtocolError, "artifact path escapes artifact directory: #{artifact}"
        end

        def validate_response!(response, role)
          raise ProtocolError, "response must include success" unless response.key?(:success)
          return unless role == "evaluator"
          return if response.key?(:score) || response.key?(:passed)

          raise ProtocolError, "evaluator response must include score or passed"
        end
      end
    end
  end
end
