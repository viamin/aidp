# frozen_string_literal: true

require "date"
require "yaml"
require_relative "strategy_spec"

module Aidp
  module StrategyExecution
    class StrategyLoader
      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
      end

      def load_file(path)
        raw = YAML.safe_load_file(expand_path(path), permitted_classes: [Date, Time, Symbol], aliases: true) || {}
        StrategySpec.from_hash(raw)
      end

      private

      def expand_path(path)
        File.expand_path(path, @project_dir)
      end
    end
  end
end
