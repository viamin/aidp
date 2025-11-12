# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Aidp
  module AutoUpdate
    # Adapter for querying gem versions via RubyGems API (fallback)
    class RubyGemsAPIAdapter
      RUBYGEMS_API_BASE = "https://rubygems.org/api/v1"
      TIMEOUT_SECONDS = 5

      # Get the latest version of a gem from RubyGems API
      # @param gem_name [String] Name of the gem
      # @param allow_prerelease [Boolean] Whether to allow prerelease versions
      # @return [Gem::Version, nil] Latest version or nil if unavailable
      def latest_version_for(gem_name, allow_prerelease: false)
        Aidp.log_debug("rubygems_api", "checking_gem_version",
          gem: gem_name,
          allow_prerelease: allow_prerelease)

        uri = URI.parse("#{RUBYGEMS_API_BASE}/gems/#{gem_name}.json")
        response = fetch_with_timeout(uri)

        return nil unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        version_string = data["version"]

        if version_string
          version = Gem::Version.new(version_string)

          # Filter out prerelease if not allowed
          if !allow_prerelease && version.prerelease?
            Aidp.log_debug("rubygems_api", "skipping_prerelease",
              gem: gem_name,
              version: version_string)
            return nil
          end

          Aidp.log_debug("rubygems_api", "found_version",
            gem: gem_name,
            version: version_string)
          version
        else
          Aidp.log_debug("rubygems_api", "no_version_in_response",
            gem: gem_name)
          nil
        end
      rescue JSON::ParserError => e
        Aidp.log_error("rubygems_api", "json_parse_failed",
          gem: gem_name,
          error: e.message)
        nil
      rescue ArgumentError => e
        Aidp.log_error("rubygems_api", "invalid_version",
          gem: gem_name,
          error: e.message)
        nil
      rescue => e
        Aidp.log_error("rubygems_api", "api_request_failed",
          gem: gem_name,
          error: e.message)
        nil
      end

      private

      def fetch_with_timeout(uri)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: TIMEOUT_SECONDS,
          read_timeout: TIMEOUT_SECONDS
        ) do |http|
          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = "Aidp/#{Aidp::VERSION}"
          http.request(request)
        end
      rescue Timeout::Error, Errno::ETIMEDOUT
        Aidp.log_warn("rubygems_api", "request_timeout",
          uri: uri.to_s,
          timeout: TIMEOUT_SECONDS)
        nil
      rescue SocketError, Errno::ECONNREFUSED => e
        Aidp.log_warn("rubygems_api", "connection_failed",
          uri: uri.to_s,
          error: e.message)
        nil
      end
    end
  end
end
