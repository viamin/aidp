# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../message_display"

module Aidp
  module Init
    # Generates .devcontainer configuration for projects
    # Provides sandboxed development environment with network security
    class DevcontainerGenerator
      include Aidp::MessageDisplay

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @devcontainer_dir = File.join(@project_dir, ".devcontainer")
      end

      # Generate devcontainer configuration based on project analysis
      #
      # @param analysis [Hash] Project analysis from ProjectAnalyzer
      # @param preferences [Hash] User preferences for devcontainer setup
      # @return [Array<String>] List of generated files
      def generate(analysis:, preferences: {})
        ensure_directory_exists

        files = []
        files << generate_dockerfile(analysis, preferences)
        files << generate_devcontainer_json(analysis, preferences)
        files << generate_firewall_script(analysis, preferences)
        files << generate_readme(analysis, preferences)

        files.compact
      end

      # Check if devcontainer already exists
      #
      # @return [Boolean] true if .devcontainer directory exists
      def exists?
        Dir.exist?(@devcontainer_dir)
      end

      private

      def ensure_directory_exists
        FileUtils.mkdir_p(@devcontainer_dir) unless Dir.exist?(@devcontainer_dir)
      end

      def generate_dockerfile(analysis, preferences)
        language = detect_primary_language(analysis)
        ruby_version = detect_ruby_version(analysis) || "3.4.5"
        node_version = detect_node_version(analysis) || "20"

        # Use template from .devcontainer/Dockerfile in AIDP repo
        template_path = File.join(File.dirname(__FILE__), "..", "..", "..", ".devcontainer", "Dockerfile")

        if File.exist?(template_path)
          content = File.read(template_path)

          # Customize based on project language
          if language == "ruby"
            content.gsub!(/ARG RUBY_VERSION=[\d.]+/, "ARG RUBY_VERSION=#{ruby_version}")
          elsif language == "javascript" || language == "typescript"
            # Switch to Node base image
            content = generate_node_dockerfile(node_version, analysis)
          end
        else
          # Fallback to generating from scratch
          content = case language
          when "ruby"
            generate_ruby_dockerfile(ruby_version, analysis)
          when "javascript", "typescript"
            generate_node_dockerfile(node_version, analysis)
          else
            generate_generic_dockerfile(analysis)
          end
        end

        file_path = File.join(@devcontainer_dir, "Dockerfile")
        File.write(file_path, content)
        file_path
      end

      def generate_devcontainer_json(analysis, preferences)
        detect_primary_language(analysis)

        config = {
          name: "#{File.basename(@project_dir)} Development Container",
          build: {
            dockerfile: "Dockerfile",
            args: {
              TZ: preferences[:timezone] || "UTC"
            }
          },
          capAdd: ["NET_ADMIN", "NET_RAW"],
          mounts: [
            "source=#{File.basename(@project_dir)}-bashhistory,target=/home/aidp/.bash_history,type=volume",
            "source=#{File.basename(@project_dir)}-aidp,target=/home/aidp/.aidp,type=volume"
          ],
          postStartCommand: "sudo /usr/local/bin/init-firewall.sh",
          remoteUser: "aidp",
          customizations: {
            vscode: {
              extensions: detect_vscode_extensions(analysis),
              settings: detect_vscode_settings(analysis, preferences)
            }
          }
        }

        file_path = File.join(@devcontainer_dir, "devcontainer.json")
        File.write(file_path, JSON.pretty_generate(config))
        file_path
      end

      def generate_firewall_script(_analysis, _preferences)
        # Copy template from AIDP repo
        template_path = File.join(File.dirname(__FILE__), "..", "..", "..", ".devcontainer", "init-firewall.sh")
        file_path = File.join(@devcontainer_dir, "init-firewall.sh")

        if File.exist?(template_path)
          FileUtils.cp(template_path, file_path)
        else
          # Generate basic firewall script
          content = generate_basic_firewall_script
          File.write(file_path, content)
        end

        # Make executable
        FileUtils.chmod(0o755, file_path)
        file_path
      end

      def generate_readme(_analysis, _preferences)
        # Copy template from AIDP repo
        template_path = File.join(File.dirname(__FILE__), "..", "..", "..", ".devcontainer", "README.md")
        file_path = File.join(@devcontainer_dir, "README.md")

        if File.exist?(template_path)
          content = File.read(template_path)
          # Customize project name
          content.gsub!("AIDP Development Container", "#{File.basename(@project_dir)} Development Container")
          content.gsub!("AIDP", File.basename(@project_dir))
        else
          # Generate basic README
          content = generate_basic_readme
        end
        File.write(file_path, content)

        file_path
      end

      # Helper methods for detection

      def detect_primary_language(analysis)
        return "unknown" unless analysis[:languages]&.any?

        # Find language with most code
        analysis[:languages].max_by { |_lang, size| size }&.first&.downcase || "unknown"
      end

      def detect_ruby_version(analysis)
        # Look for .ruby-version file
        ruby_version_file = File.join(@project_dir, ".ruby-version")
        return File.read(ruby_version_file).strip if File.exist?(ruby_version_file)

        # Look in Gemfile
        gemfile = File.join(@project_dir, "Gemfile")
        if File.exist?(gemfile)
          content = File.read(gemfile)
          if content =~ /ruby\s+['"]([^'"]+)['"]/
            return Regexp.last_match(1)
          end
        end

        nil
      end

      def detect_node_version(analysis)
        # Look for .nvmrc file
        nvmrc_file = File.join(@project_dir, ".nvmrc")
        return File.read(nvmrc_file).strip if File.exist?(nvmrc_file)

        # Look in package.json
        package_json = File.join(@project_dir, "package.json")
        if File.exist?(package_json)
          require "json"
          content = JSON.parse(File.read(package_json))
          if content["engines"] && content["engines"]["node"]
            version = content["engines"]["node"]
            # Extract version number (handle ^, ~, >=, etc.)
            return version.gsub(/[^0-9.]/, "").split(".").first
          end
        end

        nil
      rescue
        nil
      end

      def detect_vscode_extensions(analysis)
        extensions = []
        language = detect_primary_language(analysis)

        case language
        when "ruby"
          extensions += [
            "Shopify.ruby-lsp",
            "testdouble.vscode-standard-ruby"
          ]
        when "javascript", "typescript"
          extensions += [
            "dbaeumer.vscode-eslint",
            "esbenp.prettier-vscode"
          ]
        when "python"
          extensions += [
            "ms-python.python",
            "ms-python.vscode-pylance"
          ]
        end

        # Common extensions
        extensions += [
          "eamodio.gitlens",
          "mhutchie.git-graph",
          "redhat.vscode-yaml",
          "streetsidesoftware.code-spell-checker",
          "editorconfig.editorconfig"
        ]

        extensions
      end

      def detect_vscode_settings(analysis, preferences)
        settings = {}
        language = detect_primary_language(analysis)

        case language
        when "ruby"
          settings["ruby.lsp"] = {
            "enableExperimentalFeatures" => true
          }
          settings["standardRuby.enable"] = true
        when "javascript", "typescript"
          settings["editor.formatOnSave"] = true
          settings["editor.defaultFormatter"] = "esbenp.prettier-vscode"
        when "python"
          settings["python.linting.enabled"] = true
          settings["python.formatting.provider"] = "black"
        end

        settings
      end

      # Dockerfile generation methods

      def generate_ruby_dockerfile(ruby_version, analysis)
        <<~DOCKERFILE
          ARG RUBY_VERSION=#{ruby_version}
          FROM ruby:${RUBY_VERSION}

          # Install system dependencies
          RUN apt-get update && apt-get install -y \\
              git \\
              vim \\
              nano \\
              curl \\
              wget \\
              build-essential \\
              iptables \\
              ipset \\
              && rm -rf /var/lib/apt/lists/*

          # Create non-root user
          ARG USERNAME=aidp
          ARG USER_UID=1000
          ARG USER_GID=$USER_UID

          RUN groupadd --gid $USER_GID $USERNAME \\
              && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \\
              && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \\
              && chmod 0440 /etc/sudoers.d/$USERNAME

          # Set up workspace
          RUN mkdir -p /workspace && chown -R $USERNAME:$USERNAME /workspace
          RUN mkdir -p /home/$USERNAME/.aidp && chown -R $USERNAME:$USERNAME /home/$USERNAME/.aidp

          WORKDIR /workspace

          USER $USERNAME

          # Install bundler
          RUN gem install bundler

          ENV PATH="/home/aidp/.local/bin:${PATH}"
        DOCKERFILE
      end

      def generate_node_dockerfile(node_version, analysis)
        <<~DOCKERFILE
          FROM node:#{node_version}

          # Install system dependencies
          RUN apt-get update && apt-get install -y \\
              git \\
              vim \\
              nano \\
              curl \\
              wget \\
              iptables \\
              ipset \\
              && rm -rf /var/lib/apt/lists/*

          # Create non-root user
          ARG USERNAME=aidp
          ARG USER_UID=1000
          ARG USER_GID=$USER_UID

          RUN groupadd --gid $USER_GID $USERNAME \\
              && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \\
              && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \\
              && chmod 0440 /etc/sudoers.d/$USERNAME

          # Set up workspace
          RUN mkdir -p /workspace && chown -R $USERNAME:$USERNAME /workspace
          RUN mkdir -p /home/$USERNAME/.aidp && chown -R $USERNAME:$USERNAME /home/$USERNAME/.aidp

          WORKDIR /workspace

          USER $USERNAME

          ENV PATH="/home/aidp/.local/bin:${PATH}"
        DOCKERFILE
      end

      def generate_generic_dockerfile(analysis)
        <<~DOCKERFILE
          FROM ubuntu:22.04

          # Install system dependencies
          RUN apt-get update && apt-get install -y \\
              git \\
              vim \\
              nano \\
              curl \\
              wget \\
              build-essential \\
              iptables \\
              ipset \\
              && rm -rf /var/lib/apt/lists/*

          # Create non-root user
          ARG USERNAME=aidp
          ARG USER_UID=1000
          ARG USER_GID=$USER_UID

          RUN groupadd --gid $USER_GID $USERNAME \\
              && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \\
              && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \\
              && chmod 0440 /etc/sudoers.d/$USERNAME

          # Set up workspace
          RUN mkdir -p /workspace && chown -R $USERNAME:$USERNAME /workspace
          RUN mkdir -p /home/$USERNAME/.aidp && chown -R $USERNAME:$USERNAME /home/$USERNAME/.aidp

          WORKDIR /workspace

          USER $USERNAME

          ENV PATH="/home/aidp/.local/bin:${PATH}"
        DOCKERFILE
      end

      def generate_basic_firewall_script
        <<~BASH
          #!/bin/bash
          # Basic firewall configuration for devcontainer
          # Allows only essential services

          set -e

          echo "Initializing firewall..."

          # Create ipset for allowed domains
          ipset create allowed-domains hash:net -exist

          # DNS lookupand add common domains
          add_domain() {
              local domain=$1
              local ips=$(dig +short "$domain" A)
              for ip in $ips; do
                  if [[ $ip =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
                      ipset add allowed-domains "$ip" -exist
                  fi
              done
          }

          # Allow essential services
          add_domain "github.com"
          add_domain "api.github.com"

          # Set default policies
          iptables -P INPUT DROP
          iptables -P FORWARD DROP
          iptables -P OUTPUT DROP

          # Allow loopback
          iptables -A INPUT -i lo -j ACCEPT
          iptables -A OUTPUT -o lo -j ACCEPT

          # Allow established connections
          iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
          iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

          # Allow DNS
          iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
          iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

          # Allow SSH
          iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

          # Allow HTTPS to allowed domains
          iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-domains dst -j ACCEPT

          echo "Firewall initialized successfully"
        BASH
      end

      def generate_basic_readme
        <<~README
          # #{File.basename(@project_dir)} Development Container

          This directory contains the development container configuration for this project.

          ## Prerequisites

          - [VS Code](https://code.visualstudio.com/)
          - [Docker Desktop](https://www.docker.com/products/docker-desktop/)
          - [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

          ## Usage

          1. Open this project in VS Code
          2. Press `F1` and select "Dev Containers: Reopen in Container"
          3. Wait for the container to build

          ## Features

          - Sandboxed development environment
          - Network security with firewall
          - All development tools pre-installed
          - Persistent volumes for history and configuration

          ## Customization

          Edit the files in `.devcontainer/` to customize the environment:

          - `Dockerfile` - Base image and system packages
          - `devcontainer.json` - VS Code settings and extensions
          - `init-firewall.sh` - Network security rules
        README
      end
    end
  end
end
