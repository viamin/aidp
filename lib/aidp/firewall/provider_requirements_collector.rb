# frozen_string_literal: true

require "yaml"
require "fileutils"
require "agent_harness"

module Aidp
  module Firewall
    # Collects firewall requirements from all provider classes
    # and generates the firewall configuration YAML file
    class ProviderRequirementsCollector
      attr_reader :config_path

      # Core infrastructure domains not tied to specific providers
      CORE_DOMAINS = {
        ruby: [
          "rubygems.org",
          "api.rubygems.org",
          "index.rubygems.org"
        ],
        javascript: [
          "registry.npmjs.org",
          "registry.yarnpkg.com"
        ],
        github: [
          "github.com",
          "api.github.com",
          "raw.githubusercontent.com",
          "objects.githubusercontent.com",
          "gist.githubusercontent.com",
          "cloud.githubusercontent.com"
        ],
        cdn: [
          "cdn.jsdelivr.net"
        ],
        vscode: [
          "update.code.visualstudio.com",
          "marketplace.visualstudio.com",
          "vscode.blob.core.windows.net",
          "vscode.download.prss.microsoft.com",
          "az764295.vo.msecnd.net",
          "gallerycdn.vsassets.io",
          "vscode.gallerycdn.vsassets.io",
          "gallery.vsassets.io",
          "vscode-sync.trafficmanager.net",
          "vscode.dev",
          "go.microsoft.com",
          "download.visualstudio.microsoft.com"
        ],
        telemetry: [
          "dc.services.visualstudio.com",
          "vortex.data.microsoft.com"
        ]
      }.freeze

      # Static IP ranges (CIDR notation)
      STATIC_IP_RANGES = [
        {"cidr" => "140.82.112.0/20", "comment" => "GitHub main infrastructure (covers 140.82.112.0 - 140.82.127.255)"},
        {"cidr" => "127.0.0.0/8", "comment" => "Localhost loopback"}
      ].freeze

      # Azure IP ranges for GitHub Copilot and VS Code services
      # These use broader /16 ranges to handle dynamic IP allocation across Azure regions
      AZURE_IP_RANGES = [
        {"cidr" => "20.189.0.0/16", "comment" => "Azure WestUS2 (GitHub Copilot - broad range due to dynamic IP allocation)"},
        {"cidr" => "104.208.0.0/16", "comment" => "Azure EastUS (GitHub Copilot - broad range due to dynamic IP allocation)"},
        {"cidr" => "52.168.0.0/16", "comment" => "Azure EastUS2 (GitHub Copilot - covers .112 and .117, broad range)"},
        {"cidr" => "40.79.0.0/16", "comment" => "Azure WestUS (GitHub Copilot - broad range due to dynamic IP allocation)"},
        {"cidr" => "13.89.0.0/16", "comment" => "Azure EastUS (GitHub Copilot - broad range due to dynamic IP allocation)"},
        {"cidr" => "13.69.0.0/16", "comment" => "Azure (covers .239, broad range due to dynamic IP allocation)"},
        {"cidr" => "13.66.0.0/16", "comment" => "Azure WestUS2 (VS Code sync service - broad range)"},
        {"cidr" => "20.42.0.0/16", "comment" => "Azure WestEurope (covers .65 and .73, broad range)"},
        {"cidr" => "20.50.0.0/16", "comment" => "Azure (covers .80, broad range due to dynamic IP allocation)"}
      ].freeze

      # Dynamic IP sources configuration
      DYNAMIC_SOURCES = {
        github_meta_api: {
          url: "https://api.github.com/meta",
          fields: ["git"],
          comment: "GitHub Git protocol IP ranges (dynamically fetched)"
        }
      }.freeze

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

      # Generate the complete YAML configuration file
      #
      # Creates a new YAML file with core infrastructure and provider requirements
      #
      # @param dry_run [Boolean] If true, only log what would be generated
      # @return [Boolean] True if generation was successful
      def generate_yaml_config(dry_run: false)
        Aidp.log_info("firewall_collector", "generating config", path: @config_path, dry_run: dry_run)

        # Collect provider requirements
        provider_requirements = collect_requirements
        deduplicated = deduplicate(provider_requirements)

        # Build complete configuration
        config = {
          "version" => 1,
          "static_ip_ranges" => STATIC_IP_RANGES,
          "azure_ip_ranges" => AZURE_IP_RANGES,
          "core_domains" => CORE_DOMAINS.transform_keys(&:to_s),
          "provider_domains" => provider_requirements.transform_values { |reqs| reqs[:domains] },
          "dynamic_sources" => DYNAMIC_SOURCES.transform_keys(&:to_s).transform_values do |v|
            v.transform_keys(&:to_s)
          end
        }

        if dry_run
          Aidp.log_info("firewall_collector", "dry run - would generate", domains: deduplicated[:all_domains].size)
          puts "Would generate YAML with:"
          puts "  - #{STATIC_IP_RANGES.size} static IP ranges"
          puts "  - #{AZURE_IP_RANGES.size} Azure IP ranges"
          puts "  - #{CORE_DOMAINS.values.flatten.size} core domains"
          puts "  - #{deduplicated[:all_domains].size} provider domains from #{provider_requirements.size} providers"
          return true
        end

        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(@config_path))

        # Write configuration
        File.write(@config_path, YAML.dump(config))
        Aidp.log_info(
          "firewall_collector",
          "config generated",
          path: @config_path,
          providers: provider_requirements.size,
          total_domains: CORE_DOMAINS.values.flatten.size + deduplicated[:all_domains].size
        )

        true
      rescue => e
        Aidp.log_error("firewall_collector", "generation failed", error: e.message)
        false
      end

      # Alias for backward compatibility
      alias_method :update_yaml_config, :generate_yaml_config

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

      # Get list of all provider classes from AgentHarness registry
      def provider_classes
        registry = AgentHarness::Providers::Registry.instance
        registry.all.map { |name| registry.get(name) }
      end

      # Extract provider name from provider class
      def extract_provider_name(provider_class)
        # AgentHarness providers have provider_name class method
        provider_class.provider_name.to_s
      end

      # Default path to firewall config file
      def default_config_path
        File.join(Dir.pwd, ".aidp", "firewall-allowlist.yml")
      end
    end
  end
end
