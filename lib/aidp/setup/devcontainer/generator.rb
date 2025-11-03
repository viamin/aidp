# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Setup
    module Devcontainer
      # Generates or updates devcontainer.json based on wizard configuration
      class Generator
        class GenerationError < StandardError; end

        def initialize(project_dir, aidp_config = {})
          @project_dir = project_dir
          @aidp_config = aidp_config
        end

        # Generate complete devcontainer configuration
        # @param wizard_config [Hash] Configuration from wizard
        # @param existing [Hash, nil] Existing devcontainer config to merge with
        # @return [Hash] Complete devcontainer configuration
        def generate(wizard_config, existing = nil)
          Aidp.log_debug("devcontainer_generator", "generating configuration",
            has_existing: !existing.nil?,
            wizard_keys: wizard_config.keys)

          base_config = build_base_config(wizard_config)
          feature_config = build_features_config(wizard_config)
          port_config = build_ports_config(wizard_config)
          env_config = build_env_config(wizard_config)
          command_config = build_commands_config(wizard_config)
          customization_config = build_customizations_config(wizard_config)

          config = base_config
            .merge(feature_config)
            .merge(port_config)
            .merge(env_config)
            .merge(command_config)
            .merge(customization_config)

          if existing
            merge_with_existing(config, existing)
          else
            config
          end
        end

        # Merge new configuration with existing, preserving user customizations
        # @param new_config [Hash] New configuration from wizard
        # @param existing [Hash] Existing devcontainer configuration
        # @return [Hash] Merged configuration
        def merge_with_existing(new_config, existing)
          Aidp.log_debug("devcontainer_generator", "merging configurations",
            new_keys: new_config.keys,
            existing_keys: existing.keys)

          merged = existing.dup

          # Merge features (combine arrays/hashes)
          merged["features"] = merge_features(
            new_config["features"],
            existing["features"]
          )

          # Merge ports (combine arrays, deduplicate)
          merged["forwardPorts"] = merge_ports(
            new_config["forwardPorts"],
            existing["forwardPorts"]
          )

          # Merge port attributes
          merged["portsAttributes"] = (existing["portsAttributes"] || {})
            .merge(new_config["portsAttributes"] || {})

          # Merge environment variables
          merged["containerEnv"] = (existing["containerEnv"] || {})
            .merge(new_config["containerEnv"] || {})

          # Merge customizations
          merged["customizations"] = merge_customizations(
            new_config["customizations"],
            existing["customizations"]
          )

          # Update AIDP metadata
          merged["_aidp"] = new_config["_aidp"]

          # Preserve user-managed fields
          preserve_user_fields(merged, existing)

          merged
        end

        # Build list of devcontainer features from wizard selections
        # @param wizard_config [Hash] Configuration from wizard
        # @return [Hash] Features configuration
        def build_features_list(wizard_config)
          features = {}

          # GitHub CLI (for all provider selections)
          if wizard_config[:providers]&.any?
            features["ghcr.io/devcontainers/features/github-cli:1"] = {}
          end

          # Ruby (for RSpec, StandardRB)
          if needs_ruby?(wizard_config)
            features["ghcr.io/devcontainers/features/ruby:1"] = {
              "version" => wizard_config[:ruby_version] || "3.2"
            }
          end

          # Node.js (for Jest, Playwright, ESLint)
          if needs_node?(wizard_config)
            features["ghcr.io/devcontainers/features/node:1"] = {
              "version" => wizard_config[:node_version] || "lts"
            }
          end

          # Playwright (for browser automation)
          if wizard_config[:interactive_tools]&.include?("playwright")
            features["ghcr.io/devcontainers-contrib/features/playwright:2"] = {}
          end

          # Docker-in-Docker (if requested)
          if wizard_config[:features]&.include?("docker")
            features["ghcr.io/devcontainers/features/docker-in-docker:2"] = {}
          end

          # Additional custom features
          wizard_config[:additional_features]&.each do |feature|
            features[feature] = {}
          end

          features
        end

        # Build post-create/start commands
        # @param wizard_config [Hash] Configuration from wizard
        # @return [String, nil] Combined post-create command
        def build_post_commands(wizard_config)
          commands = []

          # Ruby dependencies
          if needs_ruby?(wizard_config)
            commands << "bundle install"
          end

          # Node dependencies
          if needs_node?(wizard_config)
            commands << "npm install"
          end

          # Custom post-create commands
          if wizard_config[:post_create_commands]&.any?
            commands.concat(wizard_config[:post_create_commands])
          end

          commands.empty? ? nil : commands.join(" && ")
        end

        private

        def build_base_config(wizard_config)
          {
            "name" => wizard_config[:project_name] || "AIDP Development",
            "image" => select_base_image(wizard_config),
            "_aidp" => {
              "managed" => true,
              "version" => Aidp::VERSION,
              "generated_at" => Time.now.utc.iso8601
            }
          }
        end

        def build_features_config(wizard_config)
          features = build_features_list(wizard_config)
          features.empty? ? {} : {"features" => features}
        end

        def build_ports_config(wizard_config)
          ports = detect_required_ports(wizard_config)
          return {} if ports.empty?

          forward_ports = ports.map { |p| p[:number] }
          port_attrs = ports.each_with_object({}) do |port, attrs|
            attrs[port[:number].to_s] = {
              "label" => port[:label],
              "onAutoForward" => port[:auto_open] ? "notify" : "silent"
            }
          end

          {
            "forwardPorts" => forward_ports,
            "portsAttributes" => port_attrs
          }
        end

        def build_env_config(wizard_config)
          env = {}

          # AIDP environment variables
          env["AIDP_LOG_LEVEL"] = wizard_config[:log_level] || "info"
          env["AIDP_ENV"] = "development"

          # Provider-specific env vars (non-sensitive only)
          if wizard_config[:env_vars]
            env.merge!(wizard_config[:env_vars].reject { |k, _| sensitive_key?(k) })
          end

          env.empty? ? {} : {"containerEnv" => env}
        end

        def build_commands_config(wizard_config)
          post_create = build_post_commands(wizard_config)
          post_create ? {"postCreateCommand" => post_create} : {}
        end

        def build_customizations_config(wizard_config)
          extensions = detect_recommended_extensions(wizard_config)
          return {} if extensions.empty?

          {
            "customizations" => {
              "vscode" => {
                "extensions" => extensions
              }
            }
          }
        end

        def select_base_image(wizard_config)
          # Prefer explicit image if provided
          return wizard_config[:base_image] if wizard_config[:base_image]

          # Otherwise, select based on primary language
          if needs_ruby?(wizard_config)
            "mcr.microsoft.com/devcontainers/ruby:3.2"
          elsif needs_node?(wizard_config)
            "mcr.microsoft.com/devcontainers/javascript-node:lts"
          else
            "mcr.microsoft.com/devcontainers/base:ubuntu"
          end
        end

        def detect_required_ports(wizard_config)
          ports = []

          # Web application preview
          if wizard_config[:app_type]&.match?(/web|rails|sinatra/)
            ports << {
              number: wizard_config[:app_port] || 3000,
              label: "Application",
              auto_open: true
            }
          end

          # Remote terminal (if watch mode enabled)
          if wizard_config[:watch_mode]
            ports << {
              number: 7681,
              label: "Remote Terminal",
              auto_open: false
            }
          end

          # Playwright debug port
          if wizard_config[:interactive_tools]&.include?("playwright")
            ports << {
              number: 9222,
              label: "Playwright Debug",
              auto_open: false
            }
          end

          # Custom ports
          if wizard_config[:custom_ports]
            wizard_config[:custom_ports].each do |port|
              ports << {
                number: port.is_a?(Hash) ? port[:number] : port,
                label: port.is_a?(Hash) ? port[:label] : "Custom",
                auto_open: false
              }
            end
          end

          ports
        end

        def detect_recommended_extensions(wizard_config)
          extensions = []

          # Ruby extensions
          if needs_ruby?(wizard_config)
            extensions << "shopify.ruby-lsp"
            extensions << "kaiwood.endwise" if wizard_config[:editor_helpers]
          end

          # Node/JavaScript extensions
          if needs_node?(wizard_config)
            extensions << "dbaeumer.vscode-eslint" if wizard_config[:linters]&.include?("eslint")
          end

          # GitHub Copilot (if requested)
          extensions << "GitHub.copilot" if wizard_config[:enable_copilot]

          extensions
        end

        def merge_features(new_features, existing_features)
          return new_features if existing_features.nil?
          return existing_features if new_features.nil?

          # Both can be Hash or Array format
          new_hash = normalize_features(new_features)
          existing_hash = normalize_features(existing_features)

          existing_hash.merge(new_hash)
        end

        def normalize_features(features)
          case features
          when Hash
            features
          when Array
            features.each_with_object({}) { |f, h| h[f] = {} }
          else
            {}
          end
        end

        def merge_ports(new_ports, existing_ports)
          new_array = Array(new_ports).compact
          existing_array = Array(existing_ports).compact
          (existing_array + new_array).uniq.sort
        end

        def merge_customizations(new_custom, existing_custom)
          return new_custom if existing_custom.nil?
          return existing_custom if new_custom.nil?

          merged = existing_custom.dup

          if new_custom.dig("vscode", "extensions")
            existing_exts = existing_custom.dig("vscode", "extensions") || []
            new_exts = new_custom.dig("vscode", "extensions") || []
            merged["vscode"] ||= {}
            merged["vscode"]["extensions"] = (existing_exts + new_exts).uniq
          end

          if new_custom.dig("vscode", "settings")
            merged["vscode"] ||= {}
            merged["vscode"]["settings"] = (merged.dig("vscode", "settings") || {})
              .merge(new_custom.dig("vscode", "settings") || {})
          end

          merged
        end

        def preserve_user_fields(merged, existing)
          # Preserve these fields if they exist in original
          user_fields = %w[
            remoteUser
            workspaceFolder
            workspaceMount
            mounts
            runArgs
            shutdownAction
            overrideCommand
            userEnvProbe
          ]

          user_fields.each do |field|
            merged[field] = existing[field] if existing.key?(field)
          end
        end

        def needs_ruby?(wizard_config)
          wizard_config[:test_framework]&.match?(/rspec|minitest/) ||
            wizard_config[:linters]&.include?("standardrb") ||
            wizard_config[:language] == "ruby"
        end

        def needs_node?(wizard_config)
          wizard_config[:test_framework]&.match?(/jest|playwright|mocha/) ||
            wizard_config[:linters]&.include?("eslint") ||
            wizard_config[:language]&.match?(/javascript|typescript|node/)
        end

        def sensitive_key?(key)
          key_str = key.to_s.downcase
          key_str.include?("token") ||
            key_str.include?("secret") ||
            key_str.include?("key") ||
            key_str.include?("password")
        end
      end
    end
  end
end
