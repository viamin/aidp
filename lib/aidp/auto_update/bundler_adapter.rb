# frozen_string_literal: true

require "open3"

module Aidp
  module AutoUpdate
    # Adapter for querying gem versions via Bundler
    class BundlerAdapter
      # Get the latest version of a gem according to bundle outdated
      # @param gem_name [String] Name of the gem
      # @return [Gem::Version, nil] Latest version or nil if unavailable
      def latest_version_for(gem_name)
        Aidp.log_debug("bundler_adapter", "checking_gem_version", gem: gem_name)

        # Use mise exec to ensure correct Ruby version
        stdout, stderr, status = Open3.capture3(
          "mise", "exec", "--", "bundle", "outdated", gem_name, "--parseable"
        )

        unless status.success?
          Aidp.log_debug("bundler_adapter", "bundle_outdated_failed",
            gem: gem_name,
            stderr: stderr.strip)
          return nil
        end

        # Parse bundle outdated output
        # Format: "gem_name (newest version, installed version, requested version)"
        # Example: "aidp (0.25.0, 0.24.0, >= 0)"
        parse_bundle_outdated(stdout, gem_name)
      rescue => e
        Aidp.log_error("bundler_adapter", "version_check_failed",
          gem: gem_name,
          error: e.message)
        nil
      end

      private

      def parse_bundle_outdated(output, gem_name)
        # Example output line: "aidp (newest 0.25.0, installed 0.24.0)"
        output.each_line do |line|
          next unless line.start_with?(gem_name)

          # Extract newest version using regex
          if line =~ /newest\s+([0-9.]+[a-z0-9.-]*)/
            version_string = ::Regexp.last_match(1)
            Aidp.log_debug("bundler_adapter", "found_version",
              gem: gem_name,
              version: version_string)
            return Gem::Version.new(version_string)
          end
        end

        Aidp.log_debug("bundler_adapter", "no_newer_version",
          gem: gem_name)
        nil
      rescue ArgumentError => e
        Aidp.log_error("bundler_adapter", "invalid_version",
          gem: gem_name,
          error: e.message)
        nil
      end
    end
  end
end
