# frozen_string_literal: true

module Aidp
  module Analyze
    module Seams
      # I/O and OS integration patterns
      IO_PATTERNS = [
        /^File\./, /^IO\./, /^Kernel\.system$/, /^Open3\./, /^Net::HTTP/,
        /Socket|TCPSocket|UDPSocket/, /^Dir\./, /^ENV/, /^ARGV/,
        /^STDIN|^STDOUT|^STDERR/, /^Process\./, /^Thread\./, /^Timeout\./
      ].freeze

      # Database and external service patterns
      EXTERNAL_SERVICE_PATTERNS = [
        /ActiveRecord|Sequel|DataMapper/, /Redis|Memcached/, /Elasticsearch/,
        /AWS::|Google::|Azure::/, /HTTParty|Faraday|Net::HTTP/,
        /Sidekiq|Resque|DelayedJob/, /ActionMailer|Mail/
      ].freeze

      # Global and singleton patterns
      GLOBAL_PATTERNS = [
        /^\$[a-zA-Z_]/, /^@@[a-zA-Z_]/, /^::[A-Z]/, /^Kernel\./,
        /include Singleton/, /extend Singleton/, /@singleton/
      ].freeze

      def self.detect_seams_in_ast(ast_nodes, file_path)
        seams = []

        ast_nodes.each do |node|
          case node[:type]
          when "method"
            seams.concat(detect_method_seams(node, file_path))
          when "class", "module"
            seams.concat(detect_class_module_seams(node, file_path))
          end
        end

        seams
      end

      def self.detect_method_seams(method_node, file_path)
        seams = []

        # Check for I/O calls in method body
        if (io_calls = extract_io_calls(method_node))
          io_calls.each do |call|
            seams << {
              kind: "io_integration",
              file: file_path,
              line: call[:line],
              symbol_id: "#{file_path}:#{method_node[:line]}:#{method_node[:name]}",
              detail: {
                call: call[:call],
                receiver: call[:receiver],
                method: call[:method]
              },
              suggestion: "Consider extracting I/O operations to a separate service class"
            }
          end
        end

        # Check for external service calls
        if (service_calls = extract_external_service_calls(method_node))
          service_calls.each do |call|
            seams << {
              kind: "external_service",
              file: file_path,
              line: call[:line],
              symbol_id: "#{file_path}:#{method_node[:line]}:#{method_node[:name]}",
              detail: {
                call: call[:call],
                service: call[:service]
              },
              suggestion: "Consider using dependency injection for external service calls"
            }
          end
        end

        # Check for global/singleton usage
        if (global_usage = extract_global_usage(method_node))
          global_usage.each do |usage|
            seams << {
              kind: "global_singleton",
              file: file_path,
              line: usage[:line],
              symbol_id: "#{file_path}:#{method_node[:line]}:#{method_node[:name]}",
              detail: {
                usage: usage[:usage],
                type: usage[:type]
              },
              suggestion: "Consider passing global state as parameters or using dependency injection"
            }
          end
        end

        seams
      end

      def self.detect_class_module_seams(class_node, file_path)
        seams = []

        # Check for singleton pattern
        if class_node[:content]&.include?("include Singleton")
          seams << {
            kind: "singleton_pattern",
            file: file_path,
            line: class_node[:line],
            symbol_id: "#{file_path}:#{class_node[:line]}:#{class_node[:name]}",
            detail: {
              pattern: "Singleton",
              class_name: class_node[:name]
            },
            suggestion: "Consider using dependency injection instead of singleton pattern"
          }
        end

        # Check for global state in class/module
        if (global_state = extract_global_state(class_node))
          global_state.each do |state|
            seams << {
              kind: "global_state",
              file: file_path,
              line: state[:line],
              symbol_id: "#{file_path}:#{class_node[:line]}:#{class_node[:name]}",
              detail: {
                state: state[:state],
                type: state[:type]
              },
              suggestion: "Consider encapsulating global state or using configuration objects"
            }
          end
        end

        seams
      end

      private_class_method def self.extract_io_calls(_method_node)
        # Extract I/O calls from the method's AST
        # TODO: Implement actual AST analysis
        []
      end

      private_class_method def self.extract_external_service_calls(_method_node)
        # This would extract external service calls from the method's AST
        []
      end

      private_class_method def self.extract_global_usage(_method_node)
        # This would extract global variable usage from the method's AST
        []
      end

      private_class_method def self.extract_global_state(_class_node)
        # This would extract global state from the class/module AST
        []
      end
    end
  end
end
