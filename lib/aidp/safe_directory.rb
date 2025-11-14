# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Aidp
  # Provides safe directory creation with automatic fallback for permission errors
  # Used across AIDP components to handle CI environments and restricted filesystems
  module SafeDirectory
    # Safely create a directory with fallback to temp/home on permission errors
    #
    # @param path [String] The directory path to create
    # @param component_name [String] Name of the component for logging (default: "AIDP")
    # @param skip_creation [Boolean] If true, skip directory creation entirely (default: false)
    # @return [String] The actual directory path (may differ from input if fallback occurred)
    def safe_mkdir_p(path, component_name: "AIDP", skip_creation: false)
      return path if skip_creation
      return path if Dir.exist?(path)

      begin
        FileUtils.mkdir_p(path)
        path
      rescue SystemCallError => e
        fallback = determine_fallback_path(path)

        # Suppress permission warnings during tests to reduce noise
        unless ENV["RSPEC_RUNNING"] == "true"
          Kernel.warn "[#{component_name}] Cannot create directory #{path}: #{e.class}: #{e.message}"
          Kernel.warn "[#{component_name}] Using fallback directory: #{fallback}"
        end

        # Try to create fallback directory
        begin
          FileUtils.mkdir_p(fallback) unless Dir.exist?(fallback)
        rescue SystemCallError => e2
          # Suppress fallback errors during tests too
          unless ENV["RSPEC_RUNNING"] == "true"
            Kernel.warn "[#{component_name}] Fallback directory creation also failed: #{e2.class}: #{e2.message}"
          end
        end

        fallback
      end
    end

    private

    # Determine a fallback directory path when primary creation fails
    # Tries: $HOME/.aidp -> /tmp/aidp_<basename>
    #
    # @param original_path [String] The original path that failed
    # @return [String] A fallback directory path
    def determine_fallback_path(original_path)
      # Extract meaningful name from path (e.g., ".aidp/jobs" -> "aidp_jobs")
      base_name = extract_base_name(original_path)

      # Try home directory first
      begin
        home = Dir.home
        if home && !home.empty? && File.writable?(home)
          return File.join(home, base_name)
        end
      rescue
        # Ignore home directory errors, fall through to temp
      end

      # Fall back to temp directory
      File.join(Dir.tmpdir, base_name)
    end

    # Extract a meaningful base name from a path for fallback naming
    #
    # @param path [String] The original path
    # @return [String] A sanitized base name
    def extract_base_name(path)
      # Handle paths like "/project/.aidp/jobs" -> "aidp_jobs"
      # or "/.aidp" -> ".aidp"
      parts = path.split(File::SEPARATOR).reject(&:empty?)

      if parts.include?(".aidp")
        # If path contains .aidp, use .aidp and subdirectory
        idx = parts.index(".aidp")
        if idx && parts[idx + 1]
          return "aidp_#{parts[idx + 1]}"
        else
          return ".aidp"
        end
      end

      # Fallback: use last directory name
      parts.last || "aidp_storage"
    end
  end
end
