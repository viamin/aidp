# frozen_string_literal: true

require 'open3'
require_relative 'base'
require_relative '../util'

module Aidp
  module Providers
    class Cursor < Base
      def self.available?
        !!Util.which('cursor-agent')
      end

      def name = 'cursor'

      def send(prompt:, session: nil)
        raise 'cursor-agent not available' unless self.class.available?

        cmd = ['cursor-agent', '-p', prompt]
        # Keep it simple: rely on user's Cursor auth & project context.
        Open3.popen3(*cmd) do |_stdin, _stdout, _stderr, wait|
          return :ok if wait.value.success?

          raise 'cursor-agent failed'
        end
      end
    end
  end
end
