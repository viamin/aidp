# frozen_string_literal: true

require_relative "supervised_base"
require_relative "../util"

module Aidp
  module Providers
    class SupervisedCursor < SupervisedBase
      def self.available?
        !!Aidp::Util.which("cursor-agent")
      end

      def provider_name
        "cursor"
      end

      def command
        ["cursor-agent", "-p"]
      end
    end
  end
end
