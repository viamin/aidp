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

      # Parse task filing signals from agent output
      # Returns array of task hashes with description, priority, and tags
      def self.parse_task_filing(output)
        return [] unless output

        tasks = []
        # Pattern: File task: "description" [priority: high|medium|low] [tags: tag1,tag2]
        pattern = /File\s+task:\s*"([^"]+)"(?:\s+priority:\s*(high|medium|low))?(?:\s+tags:\s*([^\s]+))?/i

        output.to_s.scan(pattern).each do |description, priority, tags|
          tasks << {
            description: description.strip,
            priority: (priority || "medium").downcase.to_sym,
            tags: tags ? tags.split(",").map(&:strip) : []
          }
        end

        tasks
      end

      # Parse task status update signals from agent output
      # Returns array of status update hashes with task_id, status, and optional reason
      # Pattern: Update task: task_id_here status: done|in_progress|pending|abandoned [reason: "reason"]
      def self.parse_task_status_updates(output)
        return [] unless output

        updates = []
        # Pattern matches: Update task: task_123_abc status: done
        # Or: Update task: task_123_abc status: abandoned reason: "No longer needed"
        pattern = /Update\s+task:\s*(\S+)\s+status:\s*(done|in_progress|pending|abandoned)(?:\s+reason:\s*"([^"]+)")?/i

        output.to_s.scan(pattern).each do |task_id, status, reason|
          updates << {
            task_id: task_id.strip,
            status: status.downcase.to_sym,
            reason: reason&.strip
          }
        end

        updates
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
