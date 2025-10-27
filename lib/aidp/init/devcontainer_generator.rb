# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../message_display"

module Aidp
  module Init
    # Generates .devcontainer configuration for projects
    # Provides sandboxed development environment with network security
    #
    # Design Philosophy:
    # - Use project analysis data (already collected by ProjectAnalyzer)
    # - Avoid hardcoded framework/tool assumptions
    # - Prefer templates over code generation
    # - Let the data drive decisions, not hardcoded logic
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

      def generate_dockerfile(analysis, _preferences)
        # Use AIDP's template as the default (Ruby-based)
        # Projects can customize after generation
        template_path = File.join(File.dirname(__FILE__), "..", "..", "..", ".devcontainer", "Dockerfile")

        content = if File.exist?(template_path)
          File.read(template_path)
        else
          # Fallback to basic Dockerfile if template not found
          generate_basic_dockerfile
        end

        file_path = File.join(@devcontainer_dir, "Dockerfile")
        File.write(file_path, content)
        file_path
      end

      def generate_devcontainer_json(_analysis, preferences)
        # Use minimal, universal configuration
        # Users can customize extensions/settings based on their project needs
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
              # Include only universal, language-agnostic extensions
              # Project-specific extensions should be added by the user
              extensions: [
                "editorconfig.editorconfig", # Respect .editorconfig
                "eamodio.gitlens"            # Git integration
              ]
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

      # Generate basic Dockerfile as fallback when template not found
      # Uses Ubuntu base with minimal tooling - users customize for their needs
      def generate_basic_dockerfile
        <<~DOCKERFILE
          FROM ubuntu:22.04

          # Install essential system dependencies
          RUN apt-get update && apt-get install -y \\
              git \\
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

          # Users should customize this Dockerfile for their language/framework needs
          # See https://containers.dev for examples
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
