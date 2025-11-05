# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/aidp/setup/devcontainer/port_manager"

RSpec.describe Aidp::Setup::Devcontainer::PortManager do
  describe "#detect_required_ports" do
    it "detects web application port" do
      wizard_config = {app_type: "rails_web"}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      web_port = ports.find { |p| p[:number] == 3000 }
      expect(web_port).not_to be_nil
      expect(web_port[:label]).to eq("Application")
      expect(web_port[:protocol]).to eq("http")
      expect(web_port[:auto_open]).to be true
    end

    it "uses custom app port" do
      wizard_config = {
        app_type: "web",
        app_port: 8080
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      web_port = ports.find { |p| p[:number] == 8080 }
      expect(web_port).not_to be_nil
    end

    it "uses custom app label" do
      wizard_config = {
        app_type: "web",
        app_label: "My Cool App"
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      web_port = ports.find { |p| p[:number] == 3000 }
      expect(web_port[:label]).to eq("My Cool App")
    end

    it "detects remote terminal for watch mode" do
      wizard_config = {watch_mode: true}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      terminal_port = ports.find { |p| p[:number] == 7681 }
      expect(terminal_port).not_to be_nil
      expect(terminal_port[:label]).to eq("Remote Terminal (ttyd)")
      expect(terminal_port[:auto_open]).to be false
    end

    it "detects Playwright debug port" do
      wizard_config = {interactive_tools: ["playwright"]}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      playwright_port = ports.find { |p| p[:number] == 9222 }
      expect(playwright_port).not_to be_nil
      expect(playwright_port[:label]).to eq("Playwright Debug")
    end

    it "detects MCP server port" do
      wizard_config = {enable_mcp: true}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      mcp_port = ports.find { |p| p[:number] == 8080 }
      expect(mcp_port).not_to be_nil
      expect(mcp_port[:label]).to eq("MCP Server")
    end

    it "uses custom MCP port" do
      wizard_config = {
        enable_mcp: true,
        mcp_port: 9000
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      mcp_port = ports.find { |p| p[:number] == 9000 }
      expect(mcp_port).not_to be_nil
    end

    it "detects PostgreSQL service port" do
      wizard_config = {services: ["postgres"]}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      postgres_port = ports.find { |p| p[:number] == 5432 }
      expect(postgres_port).not_to be_nil
      expect(postgres_port[:label]).to eq("PostgreSQL")
      expect(postgres_port[:protocol]).to eq("tcp")
    end

    it "detects Redis service port" do
      wizard_config = {services: ["redis"]}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      redis_port = ports.find { |p| p[:number] == 6379 }
      expect(redis_port).not_to be_nil
      expect(redis_port[:label]).to eq("Redis")
    end

    it "detects MySQL service port" do
      wizard_config = {services: ["mysql"]}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      mysql_port = ports.find { |p| p[:number] == 3306 }
      expect(mysql_port).not_to be_nil
      expect(mysql_port[:label]).to eq("MySQL")
    end

    it "detects multiple service ports" do
      wizard_config = {services: ["postgres", "redis"]}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.find { |p| p[:number] == 5432 }).not_to be_nil
      expect(ports.find { |p| p[:number] == 6379 }).not_to be_nil
    end

    it "adds custom ports as hash" do
      wizard_config = {
        custom_ports: [
          {number: 4000, label: "Custom API", protocol: "https", auto_open: true}
        ]
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      custom_port = ports.find { |p| p[:number] == 4000 }
      expect(custom_port).not_to be_nil
      expect(custom_port[:label]).to eq("Custom API")
      expect(custom_port[:protocol]).to eq("https")
      expect(custom_port[:auto_open]).to be true
    end

    it "adds custom ports as simple numbers" do
      wizard_config = {
        custom_ports: [5000, 6000]
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.find { |p| p[:number] == 5000 }).not_to be_nil
      expect(ports.find { |p| p[:number] == 6000 }).not_to be_nil
    end

    it "filters out invalid port numbers" do
      wizard_config = {
        custom_ports: [0, -1, nil, "invalid"]
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports).to be_empty
    end

    it "combines multiple port sources" do
      wizard_config = {
        app_type: "web",
        watch_mode: true,
        interactive_tools: ["playwright"],
        services: ["postgres"],
        custom_ports: [9000]
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.size).to eq(5)
      expect(ports.find { |p| p[:number] == 3000 }).not_to be_nil  # web app
      expect(ports.find { |p| p[:number] == 7681 }).not_to be_nil  # terminal
      expect(ports.find { |p| p[:number] == 9222 }).not_to be_nil  # playwright
      expect(ports.find { |p| p[:number] == 5432 }).not_to be_nil  # postgres
      expect(ports.find { |p| p[:number] == 9000 }).not_to be_nil  # custom
    end

    it "caches detected ports" do
      wizard_config = {app_type: "web"}
      manager = described_class.new(wizard_config)

      first_call = manager.detect_required_ports
      second_call = manager.detect_required_ports

      expect(first_call.object_id).to eq(second_call.object_id)
    end

    it "returns empty array when no ports needed" do
      wizard_config = {}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports).to be_empty
    end
  end

  describe "#generate_forward_ports" do
    it "generates array of port numbers" do
      wizard_config = {
        app_type: "web",
        services: ["postgres"]
      }
      manager = described_class.new(wizard_config)

      forward_ports = manager.generate_forward_ports

      expect(forward_ports).to include(3000, 5432)
      expect(forward_ports).to all(be_a(Integer))
    end

    it "returns empty array when no ports" do
      wizard_config = {}
      manager = described_class.new(wizard_config)

      forward_ports = manager.generate_forward_ports

      expect(forward_ports).to be_empty
    end
  end

  describe "#generate_port_attributes" do
    it "generates attributes hash with labels" do
      wizard_config = {app_type: "web"}
      manager = described_class.new(wizard_config)

      attrs = manager.generate_port_attributes

      expect(attrs["3000"]).to include(
        "label" => "Application",
        "protocol" => "http"
      )
    end

    it "sets onAutoForward based on auto_open" do
      wizard_config = {
        app_type: "web",
        watch_mode: true
      }
      manager = described_class.new(wizard_config)

      attrs = manager.generate_port_attributes

      expect(attrs["3000"]["onAutoForward"]).to eq("notify")  # auto_open: true
      expect(attrs["7681"]["onAutoForward"]).to eq("silent")  # auto_open: false
    end

    it "includes all detected ports" do
      wizard_config = {
        app_type: "web",
        services: ["postgres", "redis"]
      }
      manager = described_class.new(wizard_config)

      attrs = manager.generate_port_attributes

      expect(attrs.keys).to include("3000", "5432", "6379")
    end

    it "returns empty hash when no ports" do
      wizard_config = {}
      manager = described_class.new(wizard_config)

      attrs = manager.generate_port_attributes

      expect(attrs).to be_empty
    end
  end

  describe "#generate_ports_documentation" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:output_path) { File.join(temp_dir, "PORTS.md") }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "generates markdown documentation" do
      wizard_config = {
        app_type: "web",
        watch_mode: true
      }
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      expect(content).to include("# Port Configuration")
      expect(content).to include("Total ports configured:")
      expect(content).to include("## Port Details")
      expect(content).to include("## Security Considerations")
    end

    it "includes port table with all ports" do
      wizard_config = {
        app_type: "web",
        services: ["postgres"]
      }
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      expect(content).to include("3000")
      expect(content).to include("Application")
      expect(content).to include("5432")
      expect(content).to include("PostgreSQL")
    end

    it "includes firewall configuration examples" do
      wizard_config = {app_type: "web"}
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      expect(content).to include("## Firewall Configuration")
      expect(content).to include("ufw allow")
      expect(content).to include("firewall-cmd")
    end

    it "shows correct port count" do
      wizard_config = {
        app_type: "web",
        watch_mode: true,
        services: ["postgres"]
      }
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      expect(content).to include("Total ports configured: **3**")
    end

    it "writes to file when output_path provided" do
      wizard_config = {app_type: "web"}
      manager = described_class.new(wizard_config)

      manager.generate_ports_documentation(output_path)

      expect(File.exist?(output_path)).to be true
      content = File.read(output_path)
      expect(content).to include("# Port Configuration")
    end

    it "returns content even when writing to file" do
      wizard_config = {app_type: "web"}
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation(output_path)

      expect(content).to include("# Port Configuration")
    end

    it "handles empty port list gracefully" do
      wizard_config = {}
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      expect(content).to include("Total ports configured: **0**")
      expect(content).to include("*No ports configured*")
      expect(content).to include("No ports require firewall configuration")
    end

    it "sorts ports by number in table" do
      wizard_config = {
        custom_ports: [9000, 3000, 5000]
      }
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      port_section = content.split("| Port |")[1]
      positions = {
        "3000" => port_section.index("3000"),
        "5000" => port_section.index("5000"),
        "9000" => port_section.index("9000")
      }

      expect(positions["3000"]).to be < positions["5000"]
      expect(positions["5000"]).to be < positions["9000"]
    end

    it "includes AIDP version in footer" do
      wizard_config = {app_type: "web"}
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      expect(content).to include("Generated by AIDP #{Aidp::VERSION}")
    end

    it "includes port descriptions" do
      wizard_config = {
        app_type: "web",
        watch_mode: true
      }
      manager = described_class.new(wizard_config)

      content = manager.generate_ports_documentation

      expect(content).to include("Main application web server")
      expect(content).to include("Terminal access via ttyd")
    end
  end

  describe "web application detection" do
    it "detects Rails apps" do
      wizard_config = {app_type: "rails_web"}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.find { |p| p[:number] == 3000 }).not_to be_nil
    end

    it "detects Sinatra apps" do
      wizard_config = {app_type: "sinatra"}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.find { |p| p[:number] == 3000 }).not_to be_nil
    end

    it "detects Express apps" do
      wizard_config = {app_type: "express"}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.find { |p| p[:number] == 3000 }).not_to be_nil
    end

    it "detects apps with web interface flag" do
      wizard_config = {has_web_interface: true}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.find { |p| p[:number] == 3000 }).not_to be_nil
    end

    it "does not detect for non-web apps" do
      wizard_config = {app_type: "cli_tool"}
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      expect(ports.find { |p| p[:number] == 3000 }).to be_nil
    end
  end

  describe "API server port" do
    it "adds separate API port when configured" do
      wizard_config = {
        app_type: "web",
        api_port: 4000
      }
      manager = described_class.new(wizard_config)

      ports = manager.detect_required_ports

      api_port = ports.find { |p| p[:number] == 4000 }
      expect(api_port).not_to be_nil
      expect(api_port[:label]).to eq("API Server")
    end
  end
end
