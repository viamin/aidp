# frozen_string_literal: true

require "spec_helper"
require "aidp/utils/devcontainer_detector"

RSpec.describe Aidp::Utils::DevcontainerDetector do
  # Reset cached detection before each test
  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe ".in_devcontainer?" do
    context "when REMOTE_CONTAINERS env var is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return("true")
      end

      it "returns true" do
        expect(described_class.in_devcontainer?).to be true
      end
    end

    context "when CODESPACES env var is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CODESPACES").and_return("true")
      end

      it "returns true" do
        expect(described_class.in_devcontainer?).to be true
      end
    end

    context "when in Docker container with development markers" do
      before do
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
        allow(File).to receive(:exist?).with("/workspace").and_return(true)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("AIDP_ENV").and_return("development")
      end

      it "returns true" do
        expect(described_class.in_devcontainer?).to be true
      end
    end

    context "when not in a container" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
        allow(File).to receive(:exist?).with("/run/.containerenv").and_return(false)
        allow(File).to receive(:exist?).with("/proc/1/cgroup").and_return(true)
        allow(File).to receive(:readlines).with("/proc/1/cgroup").and_return(["0::/\n"])
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return(nil)
        allow(ENV).to receive(:[]).with("VSCODE_REMOTE_CONTAINERS").and_return(nil)
        allow(ENV).to receive(:[]).with("CODESPACES").and_return(nil)
        allow(ENV).to receive(:[]).with("container").and_return(nil)
        allow(ENV).to receive(:[]).with("HOSTNAME").and_return("my-computer")
      end

      it "returns false" do
        expect(described_class.in_devcontainer?).to be false
      end
    end
  end

  describe ".in_container?" do
    context "when /.dockerenv exists" do
      before do
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
      end

      it "returns true" do
        expect(described_class.in_container?).to be true
      end
    end

    context "when /run/.containerenv exists" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
        allow(File).to receive(:exist?).with("/run/.containerenv").and_return(true)
      end

      it "returns true" do
        expect(described_class.in_container?).to be true
      end
    end

    context "when container env var is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("container").and_return("docker")
      end

      it "returns true" do
        expect(described_class.in_container?).to be true
      end
    end

    context "when not in a container" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
        allow(File).to receive(:exist?).with("/run/.containerenv").and_return(false)
        allow(File).to receive(:exist?).with("/proc/1/cgroup").and_return(true)
        allow(File).to receive(:readlines).with("/proc/1/cgroup").and_return(["0::/\n"])
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("container").and_return(nil)
        allow(ENV).to receive(:[]).with("HOSTNAME").and_return("my-computer")
      end

      it "returns false" do
        expect(described_class.in_container?).to be false
      end
    end
  end

  describe ".in_codespaces?" do
    context "when CODESPACES is true" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CODESPACES").and_return("true")
      end

      it "returns true" do
        expect(described_class.in_codespaces?).to be true
      end
    end

    context "when CODESPACES is not set" do
      it "returns false" do
        expect(described_class.in_codespaces?).to be false
      end
    end
  end

  describe ".in_vscode_remote?" do
    context "when REMOTE_CONTAINERS is true" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return("true")
      end

      it "returns true" do
        expect(described_class.in_vscode_remote?).to be true
      end
    end

    context "when VSCODE_REMOTE_CONTAINERS is true" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("VSCODE_REMOTE_CONTAINERS").and_return("true")
      end

      it "returns true" do
        expect(described_class.in_vscode_remote?).to be true
      end
    end

    context "when neither env var is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return(nil)
        allow(ENV).to receive(:[]).with("VSCODE_REMOTE_CONTAINERS").and_return(nil)
      end

      it "returns false" do
        expect(described_class.in_vscode_remote?).to be false
      end
    end
  end

  describe ".container_type" do
    context "when in Codespaces" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CODESPACES").and_return("true")
      end

      it "returns :codespaces" do
        expect(described_class.container_type).to eq(:codespaces)
      end
    end

    context "when in VS Code Remote" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return("true")
      end

      it "returns :vscode" do
        expect(described_class.container_type).to eq(:vscode)
      end
    end

    context "when in Docker" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CODESPACES").and_return(nil)
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return(nil)
        allow(ENV).to receive(:[]).with("VSCODE_REMOTE_CONTAINERS").and_return(nil)
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
      end

      it "returns :docker" do
        expect(described_class.container_type).to eq(:docker)
      end
    end

    context "when in Podman" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CODESPACES").and_return(nil)
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return(nil)
        allow(ENV).to receive(:[]).with("VSCODE_REMOTE_CONTAINERS").and_return(nil)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
        allow(File).to receive(:exist?).with("/run/.containerenv").and_return(true)
      end

      it "returns :podman" do
        expect(described_class.container_type).to eq(:podman)
      end
    end

    context "when not in container" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CODESPACES").and_return(nil)
        allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return(nil)
        allow(ENV).to receive(:[]).with("VSCODE_REMOTE_CONTAINERS").and_return(nil)
        allow(ENV).to receive(:[]).with("container").and_return(nil)
        allow(ENV).to receive(:[]).with("HOSTNAME").and_return("my-computer")
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
        allow(File).to receive(:exist?).with("/run/.containerenv").and_return(false)
        allow(File).to receive(:exist?).with("/proc/1/cgroup").and_return(true)
        allow(File).to receive(:readlines).with("/proc/1/cgroup").and_return(["0::/\n"])
      end

      it "returns :none" do
        expect(described_class.container_type).to eq(:none)
      end
    end
  end

  describe ".container_info" do
    it "returns a hash with container information" do
      info = described_class.container_info

      expect(info).to be_a(Hash)
      expect(info).to have_key(:in_devcontainer)
      expect(info).to have_key(:in_container)
      expect(info).to have_key(:container_type)
      expect(info).to have_key(:hostname)
      expect(info).to have_key(:docker_env)
      expect(info).to have_key(:container_env)
    end

    it "includes boolean values" do
      info = described_class.container_info

      expect([true, false]).to include(info[:in_devcontainer])
      expect([true, false]).to include(info[:in_container])
      expect([true, false]).to include(info[:docker_env])
    end
  end

  describe ".reset!" do
    it "clears cached detection" do
      # Reset before starting
      described_class.reset!

      # Stub initial state - return false
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
      allow(File).to receive(:exist?).with("/run/.containerenv").and_return(false)
      allow(File).to receive(:exist?).with("/proc/1/cgroup").and_return(true)
      allow(File).to receive(:readlines).with("/proc/1/cgroup").and_return(["0::/\n"])
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("REMOTE_CONTAINERS").and_return(nil)
      allow(ENV).to receive(:[]).with("VSCODE_REMOTE_CONTAINERS").and_return(nil)
      allow(ENV).to receive(:[]).with("CODESPACES").and_return(nil)
      allow(ENV).to receive(:[]).with("container").and_return(nil)
      allow(ENV).to receive(:[]).with("HOSTNAME").and_return("my-computer")

      # First call caches the result
      first_result = described_class.in_container?
      expect(first_result).to be false

      # Cached result should be returned even with new stubs
      second_call = described_class.in_container?
      expect(second_call).to be false

      # Reset cache
      described_class.reset!

      # Change stub to return true
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)

      # Now should use new stub value after reset
      third_call = described_class.in_container?
      expect(third_call).to be true
    end
  end
end
