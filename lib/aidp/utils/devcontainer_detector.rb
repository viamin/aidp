# frozen_string_literal: true

module Aidp
  module Utils
    # Detects if AIDP is running inside a devcontainer
    #
    # Uses multiple heuristics to determine container environment:
    # - Environment variables (REMOTE_CONTAINERS, CODESPACES)
    # - Filesystem markers (/.dockerenv, /run/.containerenv)
    # - Hostname patterns
    # - cgroup information
    #
    # @example
    #   if DevcontainerDetector.in_devcontainer?
    #     puts "Running in devcontainer with elevated permissions"
    #   end
    class DevcontainerDetector
      class << self
        # Check if running inside a devcontainer
        #
        # @return [Boolean] true if inside a devcontainer
        def in_devcontainer?
          @in_devcontainer ||= detect_devcontainer
        end

        # Check if running inside any container (Docker, Podman, etc.)
        #
        # @return [Boolean] true if inside any container
        def in_container?
          @in_container ||= detect_container
        end

        # Check if running in GitHub Codespaces
        #
        # @return [Boolean] true if in Codespaces
        def in_codespaces?
          ENV["CODESPACES"] == "true"
        end

        # Check if running in VS Code Remote Containers
        #
        # @return [Boolean] true if in VS Code Remote Containers
        def in_vscode_remote?
          ENV["REMOTE_CONTAINERS"] == "true" || ENV["VSCODE_REMOTE_CONTAINERS"] == "true"
        end

        # Get container type (docker, podman, codespaces, vscode, unknown)
        #
        # @return [Symbol] container type
        def container_type
          return :codespaces if in_codespaces?
          return :vscode if in_vscode_remote?
          return :docker if docker_container?
          return :podman if podman_container?
          return :unknown if in_container?
          :none
        end

        # Get detailed container information
        #
        # @return [Hash] container information
        def container_info
          {
            in_devcontainer: in_devcontainer?,
            in_container: in_container?,
            container_type: container_type,
            hostname: hostname,
            docker_env: File.exist?("/.dockerenv"),
            container_env: File.exist?("/run/.containerenv"),
            cgroup_docker: cgroup_contains?("docker"),
            cgroup_containerd: cgroup_contains?("containerd"),
            remote_containers_env: ENV["REMOTE_CONTAINERS"],
            codespaces_env: ENV["CODESPACES"]
          }
        end

        # Reset cached detection (useful for testing)
        def reset!
          @in_devcontainer = nil
          @in_container = nil
        end

        private

        def detect_devcontainer
          # Check for VS Code Remote Containers or Codespaces
          return true if in_vscode_remote?
          return true if in_codespaces?

          # Check for devcontainer-specific environment markers
          return true if ENV["AIDP_ENV"] == "development" && in_container?

          # Generic container detection with additional heuristics
          in_container? && likely_dev_environment?
        end

        def detect_container
          # Check environment variable
          return true if ENV["container"]

          # Check for Docker environment file
          return true if File.exist?("/.dockerenv")

          # Check for Podman/containers environment file
          return true if File.exist?("/run/.containerenv")

          # Check cgroup for container indicators
          return true if cgroup_indicates_container?

          # Check hostname patterns (containers often have short hex hostnames)
          return true if hostname_indicates_container?

          false
        end

        def docker_container?
          File.exist?("/.dockerenv") || cgroup_contains?("docker")
        end

        def podman_container?
          File.exist?("/run/.containerenv") || cgroup_contains?("podman")
        end

        def cgroup_indicates_container?
          return false unless File.exist?("/proc/1/cgroup")

          File.readlines("/proc/1/cgroup").any? do |line|
            line.include?("docker") ||
              line.include?("lxc") ||
              line.include?("containerd") ||
              line.include?("podman")
          end
        rescue
          false
        end

        def cgroup_contains?(pattern)
          return false unless File.exist?("/proc/1/cgroup")

          File.readlines("/proc/1/cgroup").any? { |line| line.include?(pattern) }
        rescue
          false
        end

        def hostname
          ENV["HOSTNAME"] || `hostname`.strip
        rescue
          "unknown"
        end

        def hostname_indicates_container?
          host = hostname
          # Containers often have short hex hostnames (12 chars) or specific patterns
          host.length == 12 && host.match?(/^[0-9a-f]+$/)
        end

        def likely_dev_environment?
          # Check for common development tools and patterns
          File.exist?("/workspace") ||
            ENV["TERM_PROGRAM"] == "vscode" ||
            ENV["EDITOR"]&.include?("code")
        end
      end
    end
  end
end
