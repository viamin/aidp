# frozen_string_literal: true

module Aidp
  module Setup
    module Devcontainer
      # Manages port configuration for devcontainers and generates documentation
      class PortManager
        # Standard port assignments for common services
        STANDARD_PORTS = {
          web_app: {number: 3000, label: "Application", protocol: "http"},
          remote_terminal: {number: 7681, label: "Remote Terminal (ttyd)", protocol: "http"},
          playwright_debug: {number: 9222, label: "Playwright Debug", protocol: "http"},
          mcp_server: {number: 8080, label: "MCP Server", protocol: "http"},
          postgres: {number: 5432, label: "PostgreSQL", protocol: "tcp"},
          redis: {number: 6379, label: "Redis", protocol: "tcp"},
          mysql: {number: 3306, label: "MySQL", protocol: "tcp"}
        }.freeze

        def initialize(wizard_config)
          @wizard_config = wizard_config
          @detected_ports = []
        end

        # Detect all required ports based on wizard configuration
        # @return [Array<Hash>] Array of port configurations
        def detect_required_ports
          return @detected_ports if @detected_ports.any?

          @detected_ports = []

          detect_application_ports
          detect_tool_ports
          detect_service_ports
          add_custom_ports

          Aidp.log_debug("port_manager", "detected ports",
            count: @detected_ports.size,
            ports: @detected_ports.map { |p| p[:number] })

          @detected_ports
        end

        # Generate forwardPorts array for devcontainer.json
        # @return [Array<Integer>] Port numbers
        def generate_forward_ports
          detect_required_ports.map { |p| p[:number] }
        end

        # Generate portsAttributes hash for devcontainer.json
        # @return [Hash] Port attributes with labels and settings
        def generate_port_attributes
          detect_required_ports.each_with_object({}) do |port, attrs|
            attrs[port[:number].to_s] = {
              "label" => port[:label],
              "protocol" => port[:protocol] || "http",
              "onAutoForward" => port[:auto_open] ? "notify" : "silent"
            }
          end
        end

        # Generate PORTS.md documentation
        # @param output_path [String] Path to write PORTS.md
        # @return [String] Generated markdown content
        def generate_ports_documentation(output_path = nil)
          detect_required_ports

          content = build_ports_markdown
          File.write(output_path, content) if output_path

          content
        end

        private

        def detect_application_ports
          # Web application port
          if web_application?
            @detected_ports << {
              number: @wizard_config[:app_port] || 3000,
              label: @wizard_config[:app_label] || "Application",
              protocol: "http",
              auto_open: true,
              description: "Main application web server"
            }
          end

          # API server (if separate from main app)
          if @wizard_config[:api_port]
            @detected_ports << {
              number: @wizard_config[:api_port],
              label: "API Server",
              protocol: "http",
              auto_open: false,
              description: "REST/GraphQL API endpoint"
            }
          end
        end

        def detect_tool_ports
          # Watch mode remote terminal
          if @wizard_config[:watch_mode] || @wizard_config[:enable_watch]
            @detected_ports << STANDARD_PORTS[:remote_terminal].merge(
              auto_open: false,
              description: "Terminal access via ttyd for watch mode operations"
            )
          end

          # Playwright debug port
          if playwright_enabled?
            @detected_ports << STANDARD_PORTS[:playwright_debug].merge(
              auto_open: false,
              description: "Chrome DevTools Protocol for Playwright debugging"
            )
          end

          # MCP server
          if mcp_enabled?
            port_config = STANDARD_PORTS[:mcp_server].dup
            port_config[:number] = @wizard_config[:mcp_port] if @wizard_config[:mcp_port]
            @detected_ports << port_config.merge(
              auto_open: false,
              description: "Model Context Protocol server endpoint"
            )
          end
        end

        def detect_service_ports
          return unless @wizard_config[:services]

          @wizard_config[:services].each do |service|
            service_key = service.to_sym
            next unless STANDARD_PORTS.key?(service_key)

            @detected_ports << STANDARD_PORTS[service_key].merge(
              auto_open: false,
              description: service_description(service_key)
            )
          end
        end

        def add_custom_ports
          return unless @wizard_config[:custom_ports]

          @wizard_config[:custom_ports].each do |port|
            port_config = if port.is_a?(Hash)
              {
                number: port[:number],
                label: port[:label] || "Custom Port",
                protocol: port[:protocol] || "http",
                auto_open: port[:auto_open] || false,
                description: port[:description] || "User-defined port"
              }
            else
              {
                number: port.to_i,
                label: "Custom Port",
                protocol: "http",
                auto_open: false,
                description: "User-defined port"
              }
            end

            @detected_ports << port_config if port_config[:number]&.positive?
          end
        end

        def build_ports_markdown
          <<~MARKDOWN
            # Port Configuration

            This document lists all ports configured for this development environment.

            ## Overview

            Total ports configured: **#{@detected_ports.size}**

            ## Port Details

            #{build_port_table}

            ## Security Considerations

            - All ports are forwarded from the devcontainer to your local machine
            - Ports marked as "Auto-open" will trigger a notification when the container starts
            - Ensure sensitive services (databases, etc.) are not exposed publicly
            - Use firewall rules to restrict access if deploying to a remote environment

            ## Adding Custom Ports

            To add custom ports, update your `aidp.yml`:

            ```yaml
            devcontainer:
              custom_ports:
                - number: 8000
                  label: "Custom Service"
                  protocol: "http"
                  auto_open: false
            ```

            Then re-run `aidp config --interactive` to update your devcontainer.

            ## Firewall Configuration

            #{build_firewall_section}

            ---

            *Generated by AIDP #{Aidp::VERSION} on #{Time.now.utc.strftime("%Y-%m-%d")}*
          MARKDOWN
        end

        def build_port_table
          return "*No ports configured*" if @detected_ports.empty?

          table = "| Port | Label | Protocol | Auto-open | Description |\n"
          table += "|------|-------|----------|-----------|-------------|\n"

          @detected_ports.sort_by { |p| p[:number] }.each do |port|
            auto_open = port[:auto_open] ? "Yes" : "No"
            table += "| #{port[:number]} | #{port[:label]} | #{port[:protocol]} | #{auto_open} | #{port[:description] || "-"} |\n"
          end

          table
        end

        def build_firewall_section
          if @detected_ports.empty?
            return "No ports require firewall configuration."
          end

          ports_list = @detected_ports.map { |p| p[:number] }.sort.join(", ")

          <<~FIREWALL
            If running in a cloud environment or VM, ensure these ports are allowed through your firewall:

            ```bash
            # Example: UFW (Ubuntu)
            #{@detected_ports.sort_by { |p| p[:number] }.map { |p| "sudo ufw allow #{p[:number]}/tcp  # #{p[:label]}" }.join("\n")}

            # Example: firewalld (RHEL/CentOS)
            #{@detected_ports.sort_by { |p| p[:number] }.map { |p| "sudo firewall-cmd --permanent --add-port=#{p[:number]}/tcp  # #{p[:label]}" }.join("\n")}
            sudo firewall-cmd --reload
            ```

            **Ports to allow:** #{ports_list}
          FIREWALL
        end

        def web_application?
          @wizard_config[:app_type]&.match?(/web|rails|sinatra|express|django|flask/) ||
            @wizard_config[:has_web_interface] == true
        end

        def playwright_enabled?
          @wizard_config[:interactive_tools]&.include?("playwright") ||
            @wizard_config[:test_framework]&.include?("playwright")
        end

        def mcp_enabled?
          @wizard_config[:interactive_tools]&.include?("mcp") ||
            @wizard_config[:enable_mcp] == true
        end

        def service_description(service_key)
          case service_key
          when :postgres
            "PostgreSQL database server"
          when :redis
            "Redis in-memory data store"
          when :mysql
            "MySQL database server"
          when :remote_terminal
            "Remote terminal access"
          when :playwright_debug
            "Browser automation debugging"
          when :mcp_server
            "Model Context Protocol server"
          else
            "Service port"
          end
        end
      end
    end
  end
end
