# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/aidp/setup/devcontainer/generator"

RSpec.describe Aidp::Setup::Devcontainer::Generator do
  let(:project_dir) { Dir.mktmpdir }
  let(:generator) { described_class.new(project_dir) }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#generate" do
    it "generates basic devcontainer from wizard config" do
      wizard_config = {
        project_name: "Test Project",
        language: "ruby",
        providers: ["anthropic"]
      }

      result = generator.generate(wizard_config)

      expect(result["name"]).to eq("Test Project")
      expect(result["image"]).to include("ruby")
      expect(result["_aidp"]["managed"]).to be true
    end

    it "includes AIDP metadata" do
      wizard_config = {project_name: "Test"}

      result = generator.generate(wizard_config)

      expect(result["_aidp"]["managed"]).to be true
      expect(result["_aidp"]["version"]).to eq(Aidp::VERSION)
      expect(result["_aidp"]["generated_at"]).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it "merges with existing configuration" do
      wizard_config = {project_name: "Test"}
      existing = {
        "name" => "Old Name",
        "remoteUser" => "vscode",
        "customField" => "preserved"
      }

      result = generator.generate(wizard_config, existing)

      expect(result["name"]).to eq("Old Name") # Preserved from existing
      expect(result["remoteUser"]).to eq("vscode") # Preserved
      expect(result["customField"]).to eq("preserved") # Preserved
      expect(result["_aidp"]["managed"]).to be true # Added
    end
  end

  describe "#build_features_list" do
    it "adds GitHub CLI for provider selections" do
      wizard_config = {providers: ["anthropic", "openai"]}

      features = generator.build_features_list(wizard_config)

      expect(features).to have_key("ghcr.io/devcontainers/features/github-cli:1")
    end

    it "adds Ruby feature for RSpec" do
      wizard_config = {test_framework: "rspec"}

      features = generator.build_features_list(wizard_config)

      expect(features).to have_key("ghcr.io/devcontainers/features/ruby:1")
      expect(features["ghcr.io/devcontainers/features/ruby:1"]["version"]).to eq("3.2")
    end

    it "adds Ruby feature with custom version" do
      wizard_config = {
        test_framework: "rspec",
        ruby_version: "3.3"
      }

      features = generator.build_features_list(wizard_config)

      expect(features["ghcr.io/devcontainers/features/ruby:1"]["version"]).to eq("3.3")
    end

    it "adds Node feature for Jest" do
      wizard_config = {test_framework: "jest"}

      features = generator.build_features_list(wizard_config)

      expect(features).to have_key("ghcr.io/devcontainers/features/node:1")
      expect(features["ghcr.io/devcontainers/features/node:1"]["version"]).to eq("lts")
    end

    it "adds Playwright feature" do
      wizard_config = {interactive_tools: ["playwright"]}

      features = generator.build_features_list(wizard_config)

      expect(features).to have_key("ghcr.io/devcontainers-contrib/features/playwright:2")
    end

    it "adds Docker-in-Docker when requested" do
      wizard_config = {features: ["docker"]}

      features = generator.build_features_list(wizard_config)

      expect(features).to have_key("ghcr.io/devcontainers/features/docker-in-docker:2")
    end

    it "adds custom features" do
      wizard_config = {
        additional_features: [
          "ghcr.io/devcontainers/features/aws-cli:1",
          "ghcr.io/devcontainers/features/terraform:1"
        ]
      }

      features = generator.build_features_list(wizard_config)

      expect(features).to have_key("ghcr.io/devcontainers/features/aws-cli:1")
      expect(features).to have_key("ghcr.io/devcontainers/features/terraform:1")
    end

    it "combines multiple features" do
      wizard_config = {
        providers: ["anthropic"],
        test_framework: "rspec",
        interactive_tools: ["playwright"]
      }

      features = generator.build_features_list(wizard_config)

      expect(features.size).to eq(3)
      expect(features).to have_key("ghcr.io/devcontainers/features/github-cli:1")
      expect(features).to have_key("ghcr.io/devcontainers/features/ruby:1")
      expect(features).to have_key("ghcr.io/devcontainers-contrib/features/playwright:2")
    end
  end

  describe "#build_post_commands" do
    it "adds bundle install for Ruby projects" do
      wizard_config = {language: "ruby"}

      commands = generator.build_post_commands(wizard_config)

      expect(commands).to include("bundle install")
    end

    it "adds npm install for Node projects" do
      wizard_config = {language: "javascript"}

      commands = generator.build_post_commands(wizard_config)

      expect(commands).to include("npm install")
    end

    it "combines Ruby and Node commands" do
      wizard_config = {
        test_framework: "rspec",
        linters: ["eslint"]
      }

      commands = generator.build_post_commands(wizard_config)

      expect(commands).to include("bundle install")
      expect(commands).to include("npm install")
      expect(commands).to include("&&")
    end

    it "includes custom post-create commands" do
      wizard_config = {
        post_create_commands: ["rake db:setup", "rails db:seed"]
      }

      commands = generator.build_post_commands(wizard_config)

      expect(commands).to include("rake db:setup")
      expect(commands).to include("rails db:seed")
    end

    it "returns nil when no commands needed" do
      wizard_config = {}

      commands = generator.build_post_commands(wizard_config)

      expect(commands).to be_nil
    end
  end

  describe "#merge_with_existing" do
    it "merges features from both configs" do
      new_config = {
        "features" => {
          "ghcr.io/devcontainers/features/github-cli:1" => {}
        }
      }
      existing = {
        "features" => {
          "ghcr.io/devcontainers/features/docker-in-docker:2" => {}
        }
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["features"].size).to eq(2)
      expect(result["features"]).to have_key("ghcr.io/devcontainers/features/github-cli:1")
      expect(result["features"]).to have_key("ghcr.io/devcontainers/features/docker-in-docker:2")
    end

    it "merges features when existing is array format" do
      new_config = {
        "features" => {
          "ghcr.io/devcontainers/features/github-cli:1" => {}
        }
      }
      existing = {
        "features" => [
          "ghcr.io/devcontainers/features/docker-in-docker:2"
        ]
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["features"]).to have_key("ghcr.io/devcontainers/features/github-cli:1")
      expect(result["features"]).to have_key("ghcr.io/devcontainers/features/docker-in-docker:2")
    end

    it "merges and deduplicates ports" do
      new_config = {
        "forwardPorts" => [3000, 8080]
      }
      existing = {
        "forwardPorts" => [3000, 5432]
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["forwardPorts"]).to eq([3000, 5432, 8080])
    end

    it "merges port attributes" do
      new_config = {
        "portsAttributes" => {
          "3000" => {"label" => "Application"}
        }
      }
      existing = {
        "portsAttributes" => {
          "5432" => {"label" => "PostgreSQL"}
        }
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["portsAttributes"]["3000"]["label"]).to eq("Application")
      expect(result["portsAttributes"]["5432"]["label"]).to eq("PostgreSQL")
    end

    it "merges environment variables" do
      new_config = {
        "containerEnv" => {
          "AIDP_LOG_LEVEL" => "debug"
        }
      }
      existing = {
        "containerEnv" => {
          "DATABASE_URL" => "postgres://..."
        }
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["containerEnv"]["AIDP_LOG_LEVEL"]).to eq("debug")
      expect(result["containerEnv"]["DATABASE_URL"]).to eq("postgres://...")
    end

    it "merges VS Code extensions" do
      new_config = {
        "customizations" => {
          "vscode" => {
            "extensions" => ["shopify.ruby-lsp"]
          }
        }
      }
      existing = {
        "customizations" => {
          "vscode" => {
            "extensions" => ["eamodio.gitlens"]
          }
        }
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["customizations"]["vscode"]["extensions"]).to include("shopify.ruby-lsp")
      expect(result["customizations"]["vscode"]["extensions"]).to include("eamodio.gitlens")
    end

    it "preserves user-managed fields" do
      new_config = {
        "name" => "New Name"
      }
      existing = {
        "name" => "Existing Name",
        "remoteUser" => "vscode",
        "workspaceFolder" => "/workspace",
        "mounts" => ["source=...,target=..."],
        "runArgs" => ["--privileged"]
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["remoteUser"]).to eq("vscode")
      expect(result["workspaceFolder"]).to eq("/workspace")
      expect(result["mounts"]).to eq(["source=...,target=..."])
      expect(result["runArgs"]).to eq(["--privileged"])
    end

    it "updates AIDP metadata on merge" do
      new_config = {
        "_aidp" => {
          "managed" => true,
          "version" => "0.21.0",
          "generated_at" => "2025-01-04T00:00:00Z"
        }
      }
      existing = {
        "_aidp" => {
          "managed" => true,
          "version" => "0.20.0",
          "generated_at" => "2025-01-03T00:00:00Z"
        }
      }

      result = generator.merge_with_existing(new_config, existing)

      expect(result["_aidp"]["version"]).to eq("0.21.0")
      expect(result["_aidp"]["generated_at"]).to eq("2025-01-04T00:00:00Z")
    end
  end

  describe "port detection" do
    it "detects web application port" do
      wizard_config = {
        project_name: "Test",
        app_type: "rails_web"
      }

      result = generator.generate(wizard_config)

      expect(result["forwardPorts"]).to include(3000)
      expect(result["portsAttributes"]["3000"]["label"]).to eq("Application")
      expect(result["portsAttributes"]["3000"]["onAutoForward"]).to eq("notify")
    end

    it "uses custom app port" do
      wizard_config = {
        app_type: "web",
        app_port: 8080
      }

      result = generator.generate(wizard_config)

      expect(result["forwardPorts"]).to include(8080)
      expect(result["portsAttributes"]["8080"]["label"]).to eq("Application")
    end

    it "adds remote terminal port for watch mode" do
      wizard_config = {
        watch_mode: true
      }

      result = generator.generate(wizard_config)

      expect(result["forwardPorts"]).to include(7681)
      expect(result["portsAttributes"]["7681"]["label"]).to eq("Remote Terminal")
      expect(result["portsAttributes"]["7681"]["onAutoForward"]).to eq("silent")
    end

    it "adds Playwright debug port" do
      wizard_config = {
        interactive_tools: ["playwright"]
      }

      result = generator.generate(wizard_config)

      expect(result["forwardPorts"]).to include(9222)
      expect(result["portsAttributes"]["9222"]["label"]).to eq("Playwright Debug")
    end

    it "adds custom ports" do
      wizard_config = {
        custom_ports: [
          {number: 5432, label: "PostgreSQL"},
          {number: 6379, label: "Redis"}
        ]
      }

      result = generator.generate(wizard_config)

      expect(result["forwardPorts"]).to include(5432, 6379)
      expect(result["portsAttributes"]["5432"]["label"]).to eq("PostgreSQL")
      expect(result["portsAttributes"]["6379"]["label"]).to eq("Redis")
    end

    it "handles custom ports as simple numbers" do
      wizard_config = {
        custom_ports: [5432, 6379]
      }

      result = generator.generate(wizard_config)

      expect(result["forwardPorts"]).to include(5432, 6379)
    end
  end

  describe "environment variable configuration" do
    it "sets AIDP environment variables" do
      wizard_config = {
        log_level: "debug"
      }

      result = generator.generate(wizard_config)

      expect(result["containerEnv"]["AIDP_LOG_LEVEL"]).to eq("debug")
      expect(result["containerEnv"]["AIDP_ENV"]).to eq("development")
    end

    it "defaults log level to info" do
      wizard_config = {}

      result = generator.generate(wizard_config)

      expect(result["containerEnv"]["AIDP_LOG_LEVEL"]).to eq("info")
    end

    it "includes custom environment variables" do
      wizard_config = {
        env_vars: {
          "NODE_ENV" => "development",
          "DEBUG" => "true"
        }
      }

      result = generator.generate(wizard_config)

      expect(result["containerEnv"]["NODE_ENV"]).to eq("development")
      expect(result["containerEnv"]["DEBUG"]).to eq("true")
    end

    it "filters out sensitive environment variables" do
      wizard_config = {
        env_vars: {
          "SAFE_VAR" => "safe",
          "API_KEY" => "sk-1234567890abcdef",
          "SECRET_TOKEN" => "secret123",
          "PASSWORD" => "pass123"
        }
      }

      result = generator.generate(wizard_config)

      expect(result["containerEnv"]).to have_key("SAFE_VAR")
      expect(result["containerEnv"]).not_to have_key("API_KEY")
      expect(result["containerEnv"]).not_to have_key("SECRET_TOKEN")
      expect(result["containerEnv"]).not_to have_key("PASSWORD")
    end
  end

  describe "VS Code customizations" do
    it "recommends Ruby LSP for Ruby projects" do
      wizard_config = {
        language: "ruby"
      }

      result = generator.generate(wizard_config)

      extensions = result.dig("customizations", "vscode", "extensions")
      expect(extensions).to include("shopify.ruby-lsp")
    end

    it "recommends ESLint for projects with ESLint" do
      wizard_config = {
        language: "javascript",
        linters: ["eslint"]
      }

      result = generator.generate(wizard_config)

      extensions = result.dig("customizations", "vscode", "extensions")
      expect(extensions).to include("dbaeumer.vscode-eslint")
    end

    it "includes GitHub Copilot when requested" do
      wizard_config = {
        enable_copilot: true
      }

      result = generator.generate(wizard_config)

      extensions = result.dig("customizations", "vscode", "extensions")
      expect(extensions).to include("GitHub.copilot")
    end

    it "skips customizations when no extensions needed" do
      wizard_config = {}

      result = generator.generate(wizard_config)

      expect(result).not_to have_key("customizations")
    end
  end

  describe "base image selection" do
    it "uses explicit base image when provided" do
      wizard_config = {
        base_image: "mcr.microsoft.com/devcontainers/python:3.11"
      }

      result = generator.generate(wizard_config)

      expect(result["image"]).to eq("mcr.microsoft.com/devcontainers/python:3.11")
    end

    it "selects Ruby image for Ruby projects" do
      wizard_config = {
        language: "ruby"
      }

      result = generator.generate(wizard_config)

      expect(result["image"]).to include("ruby")
    end

    it "selects Node image for JavaScript projects" do
      wizard_config = {
        language: "javascript"
      }

      result = generator.generate(wizard_config)

      expect(result["image"]).to include("javascript-node")
    end

    it "defaults to base Ubuntu image" do
      wizard_config = {}

      result = generator.generate(wizard_config)

      expect(result["image"]).to include("base:ubuntu")
    end
  end

  describe "post-create commands" do
    it "includes bundle install for Ruby" do
      wizard_config = {
        language: "ruby"
      }

      result = generator.generate(wizard_config)

      expect(result["postCreateCommand"]).to include("bundle install")
    end

    it "includes npm install for Node" do
      wizard_config = {
        language: "javascript"
      }

      result = generator.generate(wizard_config)

      expect(result["postCreateCommand"]).to include("npm install")
    end

    it "chains multiple commands with &&" do
      wizard_config = {
        test_framework: "rspec",
        linters: ["eslint"]
      }

      result = generator.generate(wizard_config)

      expect(result["postCreateCommand"]).to include("bundle install && npm install")
    end

    it "omits postCreateCommand when not needed" do
      wizard_config = {}

      result = generator.generate(wizard_config)

      expect(result).not_to have_key("postCreateCommand")
    end
  end
end
