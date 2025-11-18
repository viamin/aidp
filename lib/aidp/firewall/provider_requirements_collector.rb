# frozen_string_literal: true

require "yaml"
require_relative "../providers/base"
require_relative "../providers/anthropic"
require_relative "../providers/cursor"
require_relative "../providers/github_copilot"
require_relative "../providers/gemini"
require_relative "../providers/kilocode"
require_relative "../providers/opencode"
require_relative "../providers/codex"

module Aidp
  module Firewall
    # Collects firewall requirements from all provider classes
    # and updates the firewall configuration YAML file
    class ProviderRequirementsCollector
      attr_reader :config_path

      def initialize(config_path: nil)
        @config_path = config_path || default_config_path
      end

      # Collect firewall requirements from all providers
      #
      # @return [Hash] Hash with provider names as keys and requirements as values
      def collect_requirements
        Aidp.log_debug("firewall_collector", "collecting requirements", provider_count: provider_classes.size)

        requirements = {}
        provider_classes.each do |provider_class|
          provider_name = extract_provider_name(provider_class)
          reqs = provider_class.firewall_requirements

          requirements[provider_name] = {
            domains: reqs[:domains] || [],
            ip_ranges: reqs[:ip_ranges] || []
          }

          Aidp.log_debug(
            "firewall_collector",
            "collected requirements",
            provider: provider_name,
            domains: reqs[:domains]&.size || 0,
            ip_ranges: reqs[:ip_ranges]&.size || 0
          )
        end

        requirements
      end

      # Deduplicate and merge provider requirements
      #
      # @param requirements [Hash] Provider requirements hash
      # @return [Hash] Deduplicated requirements with all_domains and all_ip_ranges
      def deduplicate(requirements)
        all_domains = []
        all_ip_ranges = []

        requirements.each_value do |reqs|
          all_domains.concat(reqs[:domains])
          all_ip_ranges.concat(reqs[:ip_ranges])
        end

        {
          all_domains: all_domains.uniq.sort,
          all_ip_ranges: all_ip_ranges.uniq.sort,
          by_provider: requirements
        }
      end

      # Update the YAML configuration file with provider requirements
      #
      # @param dry_run [Boolean] If true, only log what would be updated
      # @return [Boolean] True if update was successful
      def update_yaml_config(dry_run: false)
        Aidp.log_info("firewall_collector", "updating config", path: @config_path, dry_run: dry_run)

        unless File.exist?(@config_path)
          Aidp.log_error("firewall_collector", "config file not found", path: @config_path)
          return false
        end

        # Load existing config
        config = YAML.load_file(@config_path)

        # Collect and deduplicate requirements
        requirements = collect_requirements
        deduplicated = deduplicate(requirements)

        # Update provider_domains section
        config["provider_domains"] = requirements.transform_values { |reqs| reqs[:domains] }

        if dry_run
          Aidp.log_info("firewall_collector", "dry run - would update", domains: deduplicated[:all_domains].size)
          puts "Would update #{deduplicated[:all_domains].size} unique domains from #{requirements.size} providers"
          return true
        end

        # Write updated config
        File.write(@config_path, YAML.dump(config))
        Aidp.log_info(
          "firewall_collector",
          "config updated",
          path: @config_path,
          providers: requirements.size,
          domains: deduplicated[:all_domains].size
        )

        true
      rescue => e
        Aidp.log_error("firewall_collector", "update failed", error: e.message)
        false
      end

      # Generate a summary report of provider requirements
      #
      # @return [String] Formatted summary report
      def generate_report
        requirements = collect_requirements
        deduplicated = deduplicate(requirements)

        report = []
        report << "Firewall Provider Requirements Summary"
        report << "=" * 50
        report << ""
        report << "Total Providers: #{requirements.size}"
        report << "Total Unique Domains: #{deduplicated[:all_domains].size}"
        report << "Total Unique IP Ranges: #{deduplicated[:all_ip_ranges].size}"
        report << ""
        report << "By Provider:"
        report << "-" * 50

        requirements.each do |provider, reqs|
          report << ""
          report << "#{provider.capitalize}:"
          report << "  Domains (#{reqs[:domains].size}):"
          reqs[:domains].each { |d| report << "    - #{d}" }
          if reqs[:ip_ranges].any?
            report << "  IP Ranges (#{reqs[:ip_ranges].size}):"
            reqs[:ip_ranges].each { |ip| report << "    - #{ip}" }
          end
        end

        report.join("\n")
      end

      private

      # Get list of all provider classes
      def provider_classes
        [
          Aidp::Providers::Anthropic,
          Aidp::Providers::Cursor,
          Aidp::Providers::GithubCopilot,
          Aidp::Providers::Gemini,
          Aidp::Providers::Kilocode,
          Aidp::Providers::Opencode,
          Aidp::Providers::Codex
        ]
      end

      # Extract provider name from class name
      def extract_provider_name(provider_class)
        # Convert Aidp::Providers::GithubCopilot to "github_copilot"
        provider_class.name.split("::").last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      # Default path to firewall config file
      def default_config_path
        File.join(Dir.pwd, ".aidp", "firewall-allowlist.yml")
      end
    end
  end
end
