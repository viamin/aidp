# frozen_string_literal: true

module Aidp
  module Providers
    class Base
      def name = raise(NotImplementedError)

      # Send a composed prompt string to the provider.
      # Return :ok when command completed successfully,
      # Return :interactive when starting an interactive session (for gate steps),
      # or return a string if we captured output and the caller should write to a file.
      def send(prompt:, session: nil) = raise(NotImplementedError)
    end
  end
end
