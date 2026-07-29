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

          stdout, stderr, status = Open3.capture3(*command_parts(command), stdin_data: JSON.generate(payload), chdir: @project_dir)
          raise ProtocolError, stderr.strip unless status.success?

          response = JSON.parse(stdout, symbolize_names: true)
          validate_response!(response, role)

          response.merge(
            artifacts: normalize_artifacts(response[:artifacts], artifact_dir),
            artifact_dir: artifact_dir,
            stderr: stderr
          )
        rescue JSON::ParserError => e
          raise ProtocolError, "Invalid JSON response: #{e.message}"
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
          Array(artifacts).map do |artifact|
            next artifact unless artifact.is_a?(String) && !Pathname.new(artifact).absolute?

            File.expand_path(artifact, artifact_dir)
          end
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
