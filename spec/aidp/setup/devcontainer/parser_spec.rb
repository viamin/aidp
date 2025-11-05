# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/aidp/setup/devcontainer/parser"

RSpec.describe Aidp::Setup::Devcontainer::Parser do
  let(:project_dir) { Dir.mktmpdir }
  let(:parser) { described_class.new(project_dir) }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#detect" do
    it "finds devcontainer.json in .devcontainer directory" do
      devcontainer_path = File.join(project_dir, ".devcontainer")
      FileUtils.mkdir_p(devcontainer_path)
      File.write(File.join(devcontainer_path, "devcontainer.json"), "{}")

      detected = parser.detect
      expect(detected).to eq(File.join(devcontainer_path, "devcontainer.json"))
    end

    it "finds .devcontainer.json in root" do
      devcontainer_file = File.join(project_dir, ".devcontainer.json")
      File.write(devcontainer_file, "{}")

      detected = parser.detect
      expect(detected).to eq(devcontainer_file)
    end

    it "finds devcontainer.json in root" do
      devcontainer_file = File.join(project_dir, "devcontainer.json")
      File.write(devcontainer_file, "{}")

      detected = parser.detect
      expect(detected).to eq(devcontainer_file)
    end

    it "returns nil when no devcontainer exists" do
      detected = parser.detect
      expect(detected).to be_nil
    end

    it "prefers .devcontainer/devcontainer.json over other locations" do
      FileUtils.mkdir_p(File.join(project_dir, ".devcontainer"))
      File.write(File.join(project_dir, ".devcontainer", "devcontainer.json"), "{}")
      File.write(File.join(project_dir, ".devcontainer.json"), "{}")

      detected = parser.detect
      expect(detected).to eq(File.join(project_dir, ".devcontainer", "devcontainer.json"))
    end
  end

  describe "#devcontainer_exists?" do
    it "returns true when devcontainer exists" do
      FileUtils.mkdir_p(File.join(project_dir, ".devcontainer"))
      File.write(File.join(project_dir, ".devcontainer", "devcontainer.json"), "{}")

      expect(parser.devcontainer_exists?).to be true
    end

    it "returns false when devcontainer doesn't exist" do
      expect(parser.devcontainer_exists?).to be false
    end
  end

  describe "#parse" do
    it "parses valid devcontainer.json" do
      devcontainer_path = File.join(project_dir, ".devcontainer")
      FileUtils.mkdir_p(devcontainer_path)
      config = {
        "name" => "Test Container",
        "image" => "mcr.microsoft.com/devcontainers/ruby:3.2"
      }
      File.write(File.join(devcontainer_path, "devcontainer.json"), JSON.generate(config))

      result = parser.parse
      expect(result["name"]).to eq("Test Container")
      expect(result["image"]).to eq("mcr.microsoft.com/devcontainers/ruby:3.2")
    end

    it "raises error when devcontainer doesn't exist" do
      expect {
        parser.parse
      }.to raise_error(Aidp::Setup::Devcontainer::Parser::DevcontainerNotFoundError)
    end

    it "raises error for invalid JSON" do
      devcontainer_path = File.join(project_dir, ".devcontainer")
      FileUtils.mkdir_p(devcontainer_path)
      File.write(File.join(devcontainer_path, "devcontainer.json"), "{ invalid json")

      expect {
        parser.parse
      }.to raise_error(Aidp::Setup::Devcontainer::Parser::InvalidDevcontainerError, /Invalid JSON/)
    end
  end

  describe "#extract_ports" do
    it "extracts ports from forwardPorts array" do
      create_devcontainer({
        "forwardPorts" => [3000, 8080, 5432]
      })

      ports = parser.extract_ports
      expect(ports.size).to eq(3)
      expect(ports.map { |p| p[:number] }).to eq([3000, 8080, 5432])
    end

    it "extracts port labels from portsAttributes" do
      create_devcontainer({
        "forwardPorts" => [3000, 8080],
        "portsAttributes" => {
          "3000" => {
            "label" => "Web Preview",
            "protocol" => "https"
          },
          "8080" => {
            "label" => "API Server"
          }
        }
      })

      ports = parser.extract_ports
      expect(ports[0][:label]).to eq("Web Preview")
      expect(ports[0][:protocol]).to eq("https")
      expect(ports[1][:label]).to eq("API Server")
      expect(ports[1][:protocol]).to eq("http") # default
    end

    it "handles missing forwardPorts" do
      create_devcontainer({})

      ports = parser.extract_ports
      expect(ports).to be_empty
    end

    it "handles single port as non-array" do
      create_devcontainer({
        "forwardPorts" => 3000
      })

      ports = parser.extract_ports
      expect(ports.size).to eq(1)
      expect(ports[0][:number]).to eq(3000)
    end

    it "filters out invalid ports" do
      create_devcontainer({
        "forwardPorts" => [3000, 0, -1, "invalid"]
      })

      ports = parser.extract_ports
      expect(ports.size).to eq(1)
      expect(ports[0][:number]).to eq(3000)
    end
  end

  describe "#extract_features" do
    it "extracts features from object format" do
      create_devcontainer({
        "features" => {
          "ghcr.io/devcontainers/features/github-cli:1" => {},
          "ghcr.io/devcontainers/features/node:1" => {
            "version" => "lts"
          }
        }
      })

      features = parser.extract_features
      expect(features).to include("ghcr.io/devcontainers/features/github-cli:1")
      expect(features).to include("ghcr.io/devcontainers/features/node:1")
    end

    it "extracts features from array format" do
      create_devcontainer({
        "features" => [
          "ghcr.io/devcontainers/features/github-cli:1",
          "ghcr.io/devcontainers/features/node:1"
        ]
      })

      features = parser.extract_features
      expect(features).to include("ghcr.io/devcontainers/features/github-cli:1")
      expect(features).to include("ghcr.io/devcontainers/features/node:1")
    end

    it "handles missing features" do
      create_devcontainer({})

      features = parser.extract_features
      expect(features).to be_empty
    end
  end

  describe "#extract_env" do
    it "extracts environment variables from containerEnv" do
      create_devcontainer({
        "containerEnv" => {
          "NODE_ENV" => "development",
          "DEBUG" => "true"
        }
      })

      env = parser.extract_env
      expect(env["NODE_ENV"]).to eq("development")
      expect(env["DEBUG"]).to eq("true")
    end

    it "extracts environment variables from remoteEnv" do
      create_devcontainer({
        "remoteEnv" => {
          "PATH" => "/usr/local/bin:${PATH}"
        }
      })

      env = parser.extract_env
      expect(env["PATH"]).to eq("/usr/local/bin:${PATH}")
    end

    it "filters out sensitive keys" do
      create_devcontainer({
        "containerEnv" => {
          "SAFE_VAR" => "safe",
          "API_KEY" => "sk-1234567890abcdef",
          "SECRET_TOKEN" => "secret123",
          "PASSWORD" => "pass123"
        }
      })

      env = parser.extract_env
      expect(env).to have_key("SAFE_VAR")
      expect(env).not_to have_key("API_KEY")
      expect(env).not_to have_key("SECRET_TOKEN")
      expect(env).not_to have_key("PASSWORD")
    end

    it "filters out values that look like secrets" do
      create_devcontainer({
        "containerEnv" => {
          "NORMAL_VAR" => "value",
          "BASE64_SECRET" => "dGhpc2lzYXNlY3JldHRoYXRpc2xvbmdlbm91Z2g=",
          "HEX_SECRET" => "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
        }
      })

      env = parser.extract_env
      expect(env).to have_key("NORMAL_VAR")
      expect(env).not_to have_key("BASE64_SECRET")
      expect(env).not_to have_key("HEX_SECRET")
    end

    it "handles missing env" do
      create_devcontainer({})

      env = parser.extract_env
      expect(env).to be_empty
    end
  end

  describe "#extract_post_commands" do
    it "extracts post-create command" do
      create_devcontainer({
        "postCreateCommand" => "bundle install"
      })

      commands = parser.extract_post_commands
      expect(commands[:post_create]).to eq("bundle install")
    end

    it "extracts multiple post commands" do
      create_devcontainer({
        "postCreateCommand" => "bundle install",
        "postStartCommand" => "rails server",
        "postAttachCommand" => "echo 'attached'"
      })

      commands = parser.extract_post_commands
      expect(commands[:post_create]).to eq("bundle install")
      expect(commands[:post_start]).to eq("rails server")
      expect(commands[:post_attach]).to eq("echo 'attached'")
    end

    it "handles missing post commands" do
      create_devcontainer({})

      commands = parser.extract_post_commands
      expect(commands).to be_empty
    end
  end

  describe "#extract_customizations" do
    it "extracts VS Code extensions" do
      create_devcontainer({
        "customizations" => {
          "vscode" => {
            "extensions" => [
              "shopify.ruby-lsp",
              "GitHub.copilot"
            ]
          }
        }
      })

      customizations = parser.extract_customizations
      expect(customizations[:extensions]).to include("shopify.ruby-lsp")
      expect(customizations[:extensions]).to include("GitHub.copilot")
    end

    it "extracts VS Code settings" do
      create_devcontainer({
        "customizations" => {
          "vscode" => {
            "settings" => {
              "editor.formatOnSave" => true
            }
          }
        }
      })

      customizations = parser.extract_customizations
      expect(customizations[:settings]["editor.formatOnSave"]).to be true
    end

    it "handles missing customizations" do
      create_devcontainer({})

      customizations = parser.extract_customizations
      expect(customizations[:extensions]).to be_empty
      expect(customizations[:settings]).to be_empty
    end
  end

  describe "#extract_remote_user" do
    it "extracts remote user" do
      create_devcontainer({
        "remoteUser" => "vscode"
      })

      user = parser.extract_remote_user
      expect(user).to eq("vscode")
    end

    it "returns nil when no remote user" do
      create_devcontainer({})

      user = parser.extract_remote_user
      expect(user).to be_nil
    end
  end

  describe "#extract_workspace_folder" do
    it "extracts workspace folder" do
      create_devcontainer({
        "workspaceFolder" => "/workspace/app"
      })

      folder = parser.extract_workspace_folder
      expect(folder).to eq("/workspace/app")
    end
  end

  describe "#extract_image_config" do
    it "extracts image reference" do
      create_devcontainer({
        "image" => "mcr.microsoft.com/devcontainers/ruby:3.2"
      })

      config = parser.extract_image_config
      expect(config[:image]).to eq("mcr.microsoft.com/devcontainers/ruby:3.2")
    end

    it "extracts dockerfile reference" do
      create_devcontainer({
        "dockerFile" => "Dockerfile",
        "context" => ".."
      })

      config = parser.extract_image_config
      expect(config[:dockerfile]).to eq("Dockerfile")
      expect(config[:context]).to eq("..")
    end

    it "handles dockerfile with lowercase key" do
      create_devcontainer({
        "dockerfile" => "Dockerfile"
      })

      config = parser.extract_image_config
      expect(config[:dockerfile]).to eq("Dockerfile")
    end
  end

  describe "#to_h" do
    it "returns complete configuration hash" do
      create_devcontainer({
        "name" => "Test",
        "forwardPorts" => [3000],
        "features" => {
          "ghcr.io/devcontainers/features/github-cli:1" => {}
        },
        "containerEnv" => {
          "DEBUG" => "true"
        }
      })

      result = parser.to_h
      expect(result[:path]).to include("devcontainer.json")
      expect(result[:ports]).not_to be_empty
      expect(result[:features]).not_to be_empty
      expect(result[:env]).to have_key("DEBUG")
      expect(result[:raw]["name"]).to eq("Test")
    end
  end

  private

  def create_devcontainer(config)
    devcontainer_path = File.join(project_dir, ".devcontainer")
    FileUtils.mkdir_p(devcontainer_path)
    File.write(File.join(devcontainer_path, "devcontainer.json"), JSON.generate(config))
    parser.parse
  end
end
