# frozen_string_literal: true

module Aidp
  module Execute
    module AgentSignalParser
      def self.extract_next_unit(output)
        return nil unless output

        output.to_s.each_line do |line|
          token = token_from_line(line)
          next unless token

          return normalize_token(token)
        end

        nil
      end

      def self.normalize_token(raw)
        return nil if raw.nil? || raw.empty?

        token = raw.downcase.strip
        token.gsub!(/\s+/, "_")
        token.to_sym
      end

      def self.token_from_line(line)
        return nil unless line

        trimmed = line.lstrip
        separator_index = trimmed.index(":") || trimmed.index("=")
        return nil unless separator_index

        key = trimmed[0...separator_index].strip
        value = trimmed[(separator_index + 1)..]&.strip

        return nil unless key && value
        return value if key.casecmp("next_unit").zero? || key.casecmp("next_step").zero?

        nil
      end

      private_class_method :token_from_line
    end
  end
end
