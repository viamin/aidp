# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../errors"
require_relative "scanner"
require_relative "compiler"

module Aidp
  module Metadata
    # Manages cached tool directory with automatic invalidation
    #
    # Loads compiled tool directory from cache, checks for file changes,
    # and regenerates cache when needed.
    #
    # @example Loading from cache
    #   cache = Cache.new(
    #     cache_path: ".aidp/cache/tool_directory.json",
    #     directories: [".aidp/skills", ".aidp/templates"]
    #   )
    #   directory = cache.load
    class Cache
      # Default cache TTL (24 hours)
      DEFAULT_TTL = 86400

      # Initialize cache
      #
      # @param cache_path [String] Path to cache file
      # @param directories [Array<String>] Directories to monitor
      # @param ttl [Integer] Cache TTL in seconds (default: 24 hours)
      # @param strict [Boolean] Whether to fail on validation errors
      def initialize(cache_path:, directories: [], ttl: DEFAULT_TTL, strict: false)
        @cache_path = cache_path
        @directories = Array(directories)
        @ttl = ttl
        @strict = strict
        @file_hashes_path = "#{cache_path}.hashes"
      end

      # Load tool directory from cache or regenerate
      #
      # @return [Hash] Tool directory structure
      def load
        Aidp.log_debug("metadata", "Loading cache", path: @cache_path)

        if cache_valid?
          Aidp.log_debug("metadata", "Using cached directory")
          load_from_cache
        else
          Aidp.log_info("metadata", "Cache invalid, regenerating")
          regenerate
        end
      end

      # Regenerate cache from source files
      #
      # @return [Hash] Tool directory structure
      def regenerate
        Aidp.log_info("metadata", "Regenerating tool directory", directories: @directories)

        # Compile directory
        compiler = Compiler.new(directories: @directories, strict: @strict)
        directory = compiler.compile(output_path: @cache_path)

        # Save file hashes for change detection
        save_file_hashes

        directory
      end

      # Force reload cache
      #
      # @return [Hash] Tool directory structure
      def reload
        Aidp.log_info("metadata", "Force reloading cache")
        regenerate
      end

      # Check if cache is valid
      #
      # @return [Boolean] True if cache exists and is not stale
      def cache_valid?
        return false unless File.exist?(@cache_path)
        return false if cache_expired?
        return false if files_changed?

        true
      end

      # Check if cache has expired based on TTL
      #
      # @return [Boolean] True if cache is expired
      def cache_expired?
        return true unless File.exist?(@cache_path)

        cache_age = Time.now - File.mtime(@cache_path)
        expired = cache_age > @ttl

        if expired
          Aidp.log_debug(
            "metadata",
            "Cache expired",
            age_seconds: cache_age.to_i,
            ttl: @ttl
          )
        end

        expired
      end

      # Check if source files have changed
      #
      # @return [Boolean] True if any source files have changed
      def files_changed?
        previous_hashes = load_file_hashes
        current_hashes = compute_current_hashes

        changed = previous_hashes != current_hashes

        if changed
          Aidp.log_debug(
            "metadata",
            "Source files changed",
            previous_count: previous_hashes.size,
            current_count: current_hashes.size
          )
        end

        changed
      end

      # Load directory from cache file
      #
      # @return [Hash] Cached directory structure
      # @raise [Aidp::Errors::ConfigurationError] if cache is invalid
      def load_from_cache
        content = File.read(@cache_path, encoding: "UTF-8")
        directory = JSON.parse(content)

        Aidp.log_debug(
          "metadata",
          "Loaded from cache",
          tools: directory["statistics"]["total_tools"],
          compiled_at: directory["compiled_at"]
        )

        directory
      rescue JSON::ParserError => e
        Aidp.log_error("metadata", "Invalid cache JSON", error: e.message)
        raise Aidp::Errors::ConfigurationError, "Invalid tool directory cache: #{e.message}"
      end

      # Compute current file hashes for all source files
      #
      # @return [Hash<String, String>] Map of file_path => file_hash
      def compute_current_hashes
        hashes = {}

        @directories.each do |dir|
          next unless Dir.exist?(dir)

          scanner = Scanner.new([dir])
          md_files = scanner.find_markdown_files(dir)

          md_files.each do |file_path|
            content = File.read(file_path, encoding: "UTF-8")
            hashes[file_path] = Parser.compute_file_hash(content)
          end
        end

        hashes
      end

      # Load saved file hashes
      #
      # @return [Hash<String, String>] Saved file hashes
      def load_file_hashes
        return {} unless File.exist?(@file_hashes_path)

        content = File.read(@file_hashes_path, encoding: "UTF-8")
        JSON.parse(content)
      rescue JSON::ParserError
        Aidp.log_warn("metadata", "Invalid file hashes cache, regenerating")
        {}
      end

      # Save current file hashes
      def save_file_hashes
        hashes = compute_current_hashes

        # Ensure directory exists
        dir = File.dirname(@file_hashes_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

        File.write(@file_hashes_path, JSON.pretty_generate(hashes))

        Aidp.log_debug("metadata", "Saved file hashes", count: hashes.size, path: @file_hashes_path)
      end
    end
  end
end
