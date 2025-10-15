# frozen_string_literal: true

module Aidp
  module Execute
    module AgentSignalParser
      NEXT_UNIT_PATTERN = /^\s*(?:NEXT_UNIT|NEXT_STEP)\s*[:=]\s*(.+)$/i

      def self.extract_next_unit(output)
        return nil unless output

        output.to_s.each_line do |line|
          match = line.match(NEXT_UNIT_PATTERN)
          next unless match

          token = match[1].strip
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
    end
  end
end
