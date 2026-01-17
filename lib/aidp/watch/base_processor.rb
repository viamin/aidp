# frozen_string_literal: true

module Aidp
  module Watch
    # Base class for Watch Mode processors
    class BaseProcessor
      def initialize(repository_client:, state_store: nil, label_config: {}, verbose: false)
        @repository_client = repository_client
        @state_store = state_store
        @verbose = verbose

        # Only use string or symbol access for label_config
        @rebase_label = label_config[:rebase_trigger] ||
          label_config["rebase_trigger"] ||
          "aidp-rebase"
      end

      # Checks if this processor can handle the current work item
      # @param work_item [WorkItem] The work item to check
      # @return [Boolean] Whether the work item can be processed
      def can_process?(work_item)
        raise NotImplementedError, "Subclasses must implement can_process?"
      end

      # Process the work item
      # @param work_item [WorkItem] The work item to process
      # @return [Boolean] Whether the work item was processed successfully
      def process(work_item)
        raise NotImplementedError, "Subclasses must implement process"
      end

      # Execute a system command (wrapped for testability)
      # @param command [String] The command to execute
      # @return [Boolean] The result of the system call
      def system(command)
        Kernel.system(command)
      end

      attr_reader :rebase_label
    end
  end
end
