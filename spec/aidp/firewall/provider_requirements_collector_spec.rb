# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/aidp/firewall/provider_requirements_collector"

RSpec.describe Aidp::Firewall::ProviderRequirementsCollector do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_path) { File.join(temp_dir, ".aidp", "firewall-allowlist.yml") }
  let(:collector) { described_class.new(config_path: config_path) }

  after do
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#initialize" do
    context "when config_path is provided" do
      it "sets the config_path" do
        expect(collector.config_path).to eq(config_path)
      end
    end

    context "when config_path is not provided" do
      let(:default_collector) { described_class.new }

      it "uses default config path" do
        expected_path = File.join(Dir.pwd, ".aidp", "firewall-allowlist.yml")
        expect(default_collector.config_path).to eq(expected_path)
      end
    end
  end

  describe "#collect_requirements" do
    it "collects requirements from all providers" do
      allow(Aidp).to receive(:log_debug)

      requirements = collector.collect_requirements

      expect(requirements).to be_a(Hash)
      expect(requirements).not_to be_empty

      # Verify structure for each provider
      requirements.each do |provider_name, reqs|
        expect(provider_name).to be_a(String)
        expect(reqs).to have_key(:domains)
        expect(reqs).to have_key(:ip_ranges)
        expect(reqs[:domains]).to be_an(Array)
        expect(reqs[:ip_ranges]).to be_an(Array)
      end
    end

    it "extracts correct provider names" do
      allow(Aidp).to receive(:log_debug)

      requirements = collector.collect_requirements

      # Check that provider names are in snake_case format
      requirements.keys.each do |provider_name|
        expect(provider_name).to match(/^[a-z_]+$/)
      end

      # Should include common providers
      expect(requirements.keys).to include("anthropic")
      expect(requirements.keys).to include("cursor")
      expect(requirements.keys).to include("github_copilot")
      expect(requirements.keys).to include("aider")
    end

    it "logs debug information during collection" do
      expect(Aidp).to receive(:log_debug).with(
        "firewall_collector",
        "collecting requirements",
        hash_including(provider_count: be_a(Integer))
      )

      # Should log for each provider
      expect(Aidp).to receive(:log_debug).at_least(:once).with(
        "firewall_collector",
        "collected requirements",
        hash_including(:provider, :domains, :ip_ranges)
      )

      collector.collect_requirements
    end
  end

  describe "#deduplicate" do
    let(:sample_requirements) do
      {
        "provider_a" => {
          domains: ["example.com", "test.com", "common.com"],
          ip_ranges: ["1.1.1.1/32", "2.2.2.2/32"]
        },
        "provider_b" => {
          domains: ["test.com", "common.com", "another.com"],
          ip_ranges: ["2.2.2.2/32", "3.3.3.3/32"]
        }
      }
    end

    it "deduplicates and merges requirements" do
      result = collector.deduplicate(sample_requirements)

      expect(result).to have_key(:all_domains)
      expect(result).to have_key(:all_ip_ranges)
      expect(result).to have_key(:by_provider)

      # Check deduplication and sorting
      expected_domains = ["another.com", "common.com", "example.com", "test.com"]
      expected_ips = ["1.1.1.1/32", "2.2.2.2/32", "3.3.3.3/32"]

      expect(result[:all_domains]).to match_array(expected_domains)
      expect(result[:all_ip_ranges]).to match_array(expected_ips)

      # Check sorting
      expect(result[:all_domains]).to eq(result[:all_domains].sort)
      expect(result[:all_ip_ranges]).to eq(result[:all_ip_ranges].sort)

      # Original data should be preserved
      expect(result[:by_provider]).to eq(sample_requirements)
    end

    it "handles empty requirements" do
      result = collector.deduplicate({})

      expect(result[:all_domains]).to be_empty
      expect(result[:all_ip_ranges]).to be_empty
      expect(result[:by_provider]).to be_empty
    end
  end

  describe "#generate_yaml_config" do
    before do
      allow(Aidp).to receive(:log_info)
      allow(Aidp).to receive(:log_debug)
    end

    context "with dry_run: true" do
      it "logs what would be generated without creating files" do
        expect(Aidp).to receive(:log_info).with(
          "firewall_collector",
          "generating config",
          hash_including(path: config_path, dry_run: true)
        )

        expect(Aidp).to receive(:log_info).with(
          "firewall_collector",
          "dry run - would generate",
          hash_including(:domains)
        )

        expect { collector.generate_yaml_config(dry_run: true) }
          .to output(/Would generate YAML with:/).to_stdout

        expect(File.exist?(config_path)).to be false
      end

      it "returns true for successful dry run" do
        allow($stdout).to receive(:puts)
        result = collector.generate_yaml_config(dry_run: true)
        expect(result).to be true
      end
    end

    context "with dry_run: false" do
      it "creates the config file with correct structure" do
        result = collector.generate_yaml_config(dry_run: false)

        expect(result).to be true
        expect(File.exist?(config_path)).to be true

        config = YAML.load_file(config_path)

        # Check that the config has all expected top-level keys
        expected_keys = [
          "version",
          "static_ip_ranges",
          "azure_ip_ranges",
          "core_domains",
          "provider_domains",
          "dynamic_sources"
        ]

        expected_keys.each do |key|
          expect(config).to have_key(key)
        end

        expect(config["version"]).to eq(1)
      end

      it "includes all expected core domains" do
        collector.generate_yaml_config(dry_run: false)
        config = YAML.load_file(config_path)

        core_domains = config["core_domains"]
        expect(core_domains).to have_key("ruby")
        expect(core_domains).to have_key("javascript")
        expect(core_domains).to have_key("github")
        expect(core_domains).to have_key("cdn")
        expect(core_domains).to have_key("vscode")
        expect(core_domains).to have_key("telemetry")

        expect(core_domains["ruby"]).to include("rubygems.org")
        expect(core_domains["github"]).to include("github.com")
      end

      it "includes static IP ranges" do
        collector.generate_yaml_config(dry_run: false)
        config = YAML.load_file(config_path)

        static_ranges = config["static_ip_ranges"]
        expect(static_ranges).to be_an(Array)
        expect(static_ranges).not_to be_empty

        # Should include localhost and GitHub ranges
        localhost_range = static_ranges.find { |r| r["cidr"] == "127.0.0.0/8" }
        expect(localhost_range).not_to be_nil
        expect(localhost_range["comment"]).to include("Localhost")
      end

      it "includes Azure IP ranges" do
        collector.generate_yaml_config(dry_run: false)
        config = YAML.load_file(config_path)

        azure_ranges = config["azure_ip_ranges"]
        expect(azure_ranges).to be_an(Array)
        expect(azure_ranges).not_to be_empty

        # Should include various Azure regions
        azure_ranges.each do |range|
          expect(range).to have_key("cidr")
          expect(range).to have_key("comment")
          expect(range["comment"]).to include("Azure")
        end
      end

      it "includes dynamic sources configuration" do
        collector.generate_yaml_config(dry_run: false)
        config = YAML.load_file(config_path)

        dynamic_sources = config["dynamic_sources"]
        expect(dynamic_sources).to have_key("github_meta_api")

        github_meta = dynamic_sources["github_meta_api"]
        expect(github_meta).to include(
          "url" => "https://api.github.com/meta",
          "fields" => ["git"],
          "comment" => "GitHub Git protocol IP ranges (dynamically fetched)"
        )
      end

      it "creates directory if it doesn't exist" do
        expect(File.exist?(File.dirname(config_path))).to be false

        collector.generate_yaml_config(dry_run: false)

        expect(File.exist?(File.dirname(config_path))).to be true
        expect(File.exist?(config_path)).to be true
      end

      it "logs success information" do
        expect(Aidp).to receive(:log_info).with(
          "firewall_collector",
          "config generated",
          hash_including(:path, :providers, :total_domains)
        )

        collector.generate_yaml_config(dry_run: false)
      end
    end

    context "when file creation fails" do
      before do
        allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError.new("Permission denied"))
        allow(Aidp).to receive(:log_error)
      end

      it "handles errors gracefully" do
        result = collector.generate_yaml_config(dry_run: false)

        expect(result).to be false
        expect(Aidp).to have_received(:log_error).with(
          "firewall_collector",
          "generation failed",
          hash_including(:error)
        )
      end
    end
  end

  describe "#update_yaml_config" do
    it "is an alias for generate_yaml_config" do
      expect(collector.method(:update_yaml_config)).to eq(collector.method(:generate_yaml_config))
    end
  end

  describe "#generate_report" do
    before do
      allow(Aidp).to receive(:log_debug)
    end

    it "generates a formatted summary report" do
      report = collector.generate_report

      expect(report).to include("Firewall Provider Requirements Summary")
      expect(report).to include("Total Providers:")
      expect(report).to include("Total Unique Domains:")
      expect(report).to include("By Provider:")
    end

    it "includes provider-specific information" do
      report = collector.generate_report

      # Should include some common providers
      expect(report).to match(/anthropic:/i)
      expect(report).to match(/cursor:/i)

      # Should include domain listings
      expect(report).to include("Domains (")
      expect(report).to include("    - ")
    end
  end

  describe "constants" do
    describe "CORE_DOMAINS" do
      it "includes essential development domains" do
        expect(described_class::CORE_DOMAINS).to have_key(:ruby)
        expect(described_class::CORE_DOMAINS).to have_key(:javascript)
        expect(described_class::CORE_DOMAINS).to have_key(:github)
        expect(described_class::CORE_DOMAINS).to have_key(:vscode)

        expect(described_class::CORE_DOMAINS[:ruby]).to include("rubygems.org")
        expect(described_class::CORE_DOMAINS[:javascript]).to include("registry.npmjs.org")
        expect(described_class::CORE_DOMAINS[:github]).to include("github.com", "api.github.com")
      end

      it "is frozen" do
        expect(described_class::CORE_DOMAINS).to be_frozen
      end
    end

    describe "STATIC_IP_RANGES" do
      it "includes localhost and GitHub ranges" do
        expect(described_class::STATIC_IP_RANGES).to be_an(Array)
        expect(described_class::STATIC_IP_RANGES).not_to be_empty

        localhost_range = described_class::STATIC_IP_RANGES.find { |r| r["cidr"] == "127.0.0.0/8" }
        expect(localhost_range).not_to be_nil
      end

      it "is frozen" do
        expect(described_class::STATIC_IP_RANGES).to be_frozen
      end
    end

    describe "AZURE_IP_RANGES" do
      it "includes Azure CIDR ranges" do
        expect(described_class::AZURE_IP_RANGES).to be_an(Array)
        expect(described_class::AZURE_IP_RANGES).not_to be_empty

        described_class::AZURE_IP_RANGES.each do |range|
          expect(range).to have_key("cidr")
          expect(range).to have_key("comment")
          expect(range["cidr"]).to match(%r{^\d+\.\d+\.\d+\.\d+/\d+$})
        end
      end

      it "is frozen" do
        expect(described_class::AZURE_IP_RANGES).to be_frozen
      end
    end

    describe "DYNAMIC_SOURCES" do
      it "includes GitHub meta API configuration" do
        expect(described_class::DYNAMIC_SOURCES).to have_key(:github_meta_api)

        github_meta = described_class::DYNAMIC_SOURCES[:github_meta_api]
        expect(github_meta).to include(
          url: "https://api.github.com/meta",
          fields: ["git"],
          comment: "GitHub Git protocol IP ranges (dynamically fetched)"
        )
      end

      it "is frozen" do
        expect(described_class::DYNAMIC_SOURCES).to be_frozen
      end
    end
  end

  describe "private methods" do
    describe "#provider_classes" do
      let(:provider_classes) { collector.send(:provider_classes) }

      it "returns array of provider classes" do
        expect(provider_classes).to be_an(Array)
        expect(provider_classes).not_to be_empty

        provider_classes.each do |klass|
          expect(klass).to be < Aidp::Providers::Base
        end
      end

      it "includes all expected providers" do
        class_names = provider_classes.map { |klass| klass.name.split("::").last }

        expect(class_names).to include("Anthropic")
        expect(class_names).to include("Cursor")
        expect(class_names).to include("GithubCopilot")
        expect(class_names).to include("Gemini")
        expect(class_names).to include("Aider")
      end
    end

    describe "#extract_provider_name" do
      it "converts class names to snake_case" do
        expect(collector.send(:extract_provider_name, Aidp::Providers::Anthropic)).to eq("anthropic")
        expect(collector.send(:extract_provider_name, Aidp::Providers::GithubCopilot)).to eq("github_copilot")
        expect(collector.send(:extract_provider_name, Aidp::Providers::Cursor)).to eq("cursor")
      end
    end

    describe "#default_config_path" do
      it "returns path in current directory" do
        default_path = collector.send(:default_config_path)
        expected_path = File.join(Dir.pwd, ".aidp", "firewall-allowlist.yml")
        expect(default_path).to eq(expected_path)
      end
    end
  end
end
