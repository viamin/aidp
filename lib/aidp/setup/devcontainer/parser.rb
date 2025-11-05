# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Setup
    module Devcontainer
      # Parses existing devcontainer.json files and extracts configuration
      # for pre-filling wizard defaults.
      class Parser
        class DevcontainerNotFoundError < StandardError; end
        class InvalidDevcontainerError < StandardError; end

        STANDARD_LOCATIONS = [
          ".devcontainer/devcontainer.json",
          ".devcontainer.json",
          "devcontainer.json"
        ].freeze

        attr_reader :project_dir, :devcontainer_path, :config

        def initialize(project_dir = Dir.pwd)
          @project_dir = project_dir
          @devcontainer_path = nil
          @config = nil
        end

        # Detect devcontainer.json in standard locations
        # @return [String, nil] Path to devcontainer.json or nil if not found
        def detect
          STANDARD_LOCATIONS.each do |location|
            path = File.join(project_dir, location)
            if File.exist?(path)
              @devcontainer_path = path
              Aidp.log_debug("devcontainer_parser", "detected devcontainer", path: path)
              return path
            end
          end

          Aidp.log_debug("devcontainer_parser", "no devcontainer found")
          nil
        end

        # Check if devcontainer exists
        # @return [Boolean]
        def devcontainer_exists?
          !detect.nil?
        end

        # Parse devcontainer.json and extract configuration
        # @return [Hash] Parsed configuration
        # @raise [DevcontainerNotFoundError] If devcontainer doesn't exist
        # @raise [InvalidDevcontainerError] If JSON is malformed
        def parse
          detect unless @devcontainer_path

          unless @devcontainer_path
            raise DevcontainerNotFoundError, "No devcontainer.json found in #{project_dir}"
          end

          begin
            content = File.read(@devcontainer_path)
            @config = JSON.parse(content)
            Aidp.log_debug("devcontainer_parser", "parsed devcontainer",
              features_count: extract_features.size,
              ports_count: extract_ports.size)
            @config
          rescue JSON::ParserError => e
            Aidp.log_error("devcontainer_parser", "invalid JSON", error: e.message, path: @devcontainer_path)
            raise InvalidDevcontainerError, "Invalid JSON in #{@devcontainer_path}: #{e.message}"
          rescue => e
            Aidp.log_error("devcontainer_parser", "failed to read devcontainer", error: e.message)
            raise InvalidDevcontainerError, "Failed to read #{@devcontainer_path}: #{e.message}"
          end
        end

        # Extract port forwarding configuration
        # @return [Array<Hash>] Array of port configurations
        def extract_ports
          ensure_parsed

          ports = []

          # Extract from forwardPorts array
          forward_ports = @config["forwardPorts"] || []
          forward_ports = [forward_ports] unless forward_ports.is_a?(Array)

          # Get port attributes for labels
          port_attrs = @config["portsAttributes"] || {}

          forward_ports.each do |port|
            port_num = port.to_i
            next if port_num <= 0

            attrs = port_attrs[port.to_s] || port_attrs[port_num.to_s] || {}

            ports << {
              number: port_num,
              label: attrs["label"],
              protocol: attrs["protocol"] || "http",
              on_auto_forward: attrs["onAutoForward"] || "notify"
            }
          end

          Aidp.log_debug("devcontainer_parser", "extracted ports", count: ports.size)
          ports
        end

        # Extract devcontainer features
        # @return [Array<String>] Array of feature identifiers
        def extract_features
          ensure_parsed

          features = @config["features"] || {}

          # Handle both object and array format
          feature_list = case features
          when Hash
            features.keys
          when Array
            features
          else
            []
          end

          Aidp.log_debug("devcontainer_parser", "extracted features", count: feature_list.size)
          feature_list
        end

        # Extract container environment variables
        # @return [Hash] Environment variables (excluding secrets)
        def extract_env
          ensure_parsed

          env = @config["containerEnv"] || @config["remoteEnv"] || {}
          env = {} unless env.is_a?(Hash)

          # Filter out sensitive values
          filtered_env = env.reject { |key, value|
            sensitive_key?(key) || sensitive_value?(value)
          }

          Aidp.log_debug("devcontainer_parser", "extracted env vars",
            total: env.size,
            filtered: filtered_env.size)
          filtered_env
        end

        # Extract post-create and post-start commands
        # @return [Hash] Commands configuration
        def extract_post_commands
          ensure_parsed

          {
            post_create: @config["postCreateCommand"],
            post_start: @config["postStartCommand"],
            post_attach: @config["postAttachCommand"]
          }.compact
        end

        # Extract VS Code customizations
        # @return [Hash] VS Code extensions and settings
        def extract_customizations
          ensure_parsed

          customizations = @config["customizations"] || {}
          vscode = customizations["vscode"] || {}

          {
            extensions: Array(vscode["extensions"]),
            settings: vscode["settings"] || {}
          }
        end

        # Extract remote user setting
        # @return [String, nil] Remote user name
        def extract_remote_user
          ensure_parsed
          @config["remoteUser"]
        end

        # Extract working directory
        # @return [String, nil] Working directory path
        def extract_workspace_folder
          ensure_parsed
          @config["workspaceFolder"]
        end

        # Extract the base image or dockerfile reference
        # @return [Hash] Image configuration
        def extract_image_config
          ensure_parsed

          {
            image: @config["image"],
            dockerfile: @config["dockerFile"] || @config["dockerfile"],
            context: @config["context"],
            build: @config["build"]
          }.compact
        end

        # Get complete parsed configuration as hash
        # @return [Hash] All extracted configuration
        def to_h
          ensure_parsed

          {
            path: @devcontainer_path,
            ports: extract_ports,
            features: extract_features,
            env: extract_env,
            post_commands: extract_post_commands,
            customizations: extract_customizations,
            remote_user: extract_remote_user,
            workspace_folder: extract_workspace_folder,
            image_config: extract_image_config,
            raw: @config
          }
        end

        private

        def ensure_parsed
          parse unless @config
        end

        def sensitive_key?(key)
          key = key.to_s.downcase
          key.include?("token") ||
            key.include?("secret") ||
            key.include?("key") ||
            key.include?("password") ||
            key.include?("api") && key.include?("key")
        end

        def sensitive_value?(value)
          return false unless value.is_a?(String)
          # Don't filter out common non-secret values
          return false if value.empty? || value.length < 8
          # Check for patterns that look like secrets (base64, hex, etc.)
          value.match?(/^[A-Za-z0-9+\/=]{20,}$/) || # base64-ish
            value.match?(/^[a-f0-9]{32,}$/) || # hex-ish
            value.match?(/^sk-[A-Za-z0-9]{32,}$/) # API key pattern
        end
      end
    end
  end
end
