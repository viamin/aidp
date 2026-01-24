# frozen_string_literal: true

module Aidp
  module Interfaces
    # BinaryCheckerInterface defines the contract for checking CLI binary availability.
    # This interface allows for dependency injection of different binary checking
    # implementations, facilitating extraction of provider code into standalone gems.
    #
    # @example Implementing the interface
    #   class MyBinaryChecker
    #     include Aidp::Interfaces::BinaryCheckerInterface
    #
    #     def available?(binary_name)
    #       system("which", binary_name, out: File::NULL, err: File::NULL)
    #     end
    #
    #     def path_for(binary_name)
    #       `which #{binary_name}`.chomp
    #     end
    #   end
    #
    # @example Using an injected checker
    #   class Provider
    #     def initialize(binary_checker: PathBinaryChecker.new)
    #       @binary_checker = binary_checker
    #     end
    #
    #     def available?
    #       @binary_checker.available?("claude")
    #     end
    #   end
    #
    module BinaryCheckerInterface
      # Check if a binary is available in the system PATH.
      #
      # @param binary_name [String] the name of the binary to check (e.g., "claude", "cursor-agent")
      # @return [Boolean] true if the binary is executable and in PATH
      def available?(binary_name)
        raise NotImplementedError, "#{self.class} must implement #available?"
      end

      # Get the full path to a binary.
      #
      # @param binary_name [String] the name of the binary to find
      # @return [String, nil] the full path to the binary, or nil if not found
      def path_for(binary_name)
        raise NotImplementedError, "#{self.class} must implement #path_for"
      end
    end

    # NullBinaryChecker always returns false/nil.
    # Useful for testing when no binaries should be considered available.
    #
    # @example Using in tests
    #   provider = Provider.new(binary_checker: NullBinaryChecker.new)
    #   provider.available? # => false
    #
    class NullBinaryChecker
      include BinaryCheckerInterface

      def available?(binary_name)
        false
      end

      def path_for(binary_name)
        nil
      end
    end

    # StubBinaryChecker returns configurable responses.
    # Useful for testing specific scenarios.
    #
    # @example Stubbing availability
    #   checker = StubBinaryChecker.new(available: {"claude" => true, "cursor-agent" => false})
    #   checker.available?("claude")       # => true
    #   checker.available?("cursor-agent") # => false
    #   checker.available?("unknown")      # => false
    #
    class StubBinaryChecker
      include BinaryCheckerInterface

      # @param available [Hash<String, Boolean>] map of binary names to availability
      # @param paths [Hash<String, String>] map of binary names to paths
      def initialize(available: {}, paths: {})
        @available = available
        @paths = paths
      end

      def available?(binary_name)
        @available.fetch(binary_name.to_s, false)
      end

      def path_for(binary_name)
        @paths[binary_name.to_s]
      end
    end

    # PathBinaryChecker checks the system PATH for binaries.
    # This is the standard implementation used by AIDP.
    #
    # @example Creating a checker
    #   checker = PathBinaryChecker.new
    #   checker.available?("ruby") # => true
    #   checker.path_for("ruby")   # => "/usr/bin/ruby"
    #
    class PathBinaryChecker
      include BinaryCheckerInterface

      # Check if a binary is available in the system PATH.
      #
      # @param binary_name [String] the name of the binary to check
      # @return [Boolean] true if the binary is executable and in PATH
      def available?(binary_name)
        !path_for(binary_name).nil?
      end

      # Get the full path to a binary.
      # Searches the PATH environment variable for the binary.
      #
      # @param binary_name [String] the name of the binary to find
      # @return [String, nil] the full path to the binary, or nil if not found
      def path_for(binary_name)
        return nil if binary_name.nil? || binary_name.empty?

        # Get extensions to check (Windows support)
        extensions = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]

        # Search each PATH directory
        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
          extensions.each do |ext|
            path = File.join(dir, "#{binary_name}#{ext}")
            return path if File.executable?(path) && !File.directory?(path)
          end
        end

        nil
      end
    end

    # CachingBinaryChecker wraps another checker with TTL-based caching.
    # Reduces filesystem checks for frequently-queried binaries.
    #
    # @example Creating a caching checker
    #   inner_checker = PathBinaryChecker.new
    #   checker = CachingBinaryChecker.new(inner_checker, ttl: 60)
    #   checker.available?("ruby") # filesystem check
    #   checker.available?("ruby") # cached result
    #
    class CachingBinaryChecker
      include BinaryCheckerInterface

      # Default cache TTL in seconds (5 minutes)
      DEFAULT_TTL = 300

      # @param checker [BinaryCheckerInterface] the underlying checker to cache
      # @param ttl [Integer] cache time-to-live in seconds
      def initialize(checker, ttl: DEFAULT_TTL)
        @checker = checker
        @ttl = ttl
        @cache = {}
        @path_cache = {}
      end

      def available?(binary_name)
        key = binary_name.to_s
        cached = @cache[key]

        if cached && !expired?(cached[:timestamp])
          return cached[:value]
        end

        result = @checker.available?(binary_name)
        @cache[key] = {value: result, timestamp: Time.now}
        result
      end

      def path_for(binary_name)
        key = binary_name.to_s
        cached = @path_cache[key]

        if cached && !expired?(cached[:timestamp])
          return cached[:value]
        end

        result = @checker.path_for(binary_name)
        @path_cache[key] = {value: result, timestamp: Time.now}
        result
      end

      # Clear all cached results.
      # @return [void]
      def clear_cache!
        @cache.clear
        @path_cache.clear
      end

      # Clear cached result for a specific binary.
      # @param binary_name [String] the binary name to clear
      # @return [void]
      def clear!(binary_name)
        key = binary_name.to_s
        @cache.delete(key)
        @path_cache.delete(key)
      end

      private

      def expired?(timestamp)
        Time.now - timestamp > @ttl
      end
    end

    # AidpBinaryChecker wraps Aidp::Util.which for compatibility.
    # This adapter bridges the BinaryCheckerInterface to AIDP's existing utility.
    #
    # @example Creating an adapter
    #   checker = AidpBinaryChecker.new
    #   provider = SomeProvider.new(binary_checker: checker)
    #
    class AidpBinaryChecker
      include BinaryCheckerInterface

      def available?(binary_name)
        !Aidp::Util.which(binary_name).nil?
      end

      def path_for(binary_name)
        Aidp::Util.which(binary_name)
      end
    end
  end
end
