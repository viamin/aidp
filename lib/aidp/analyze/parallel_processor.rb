# frozen_string_literal: true

module Aidp
  module Analyze
    class ParallelProcessor
      def self.process_tasks(tasks)
        # TODO: Implement parallel processing
        tasks.map { |task| yield task }
      end
    end
  end
end
