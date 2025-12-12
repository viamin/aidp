# frozen_string_literal: true

require_relative "evaluations/evaluation_record"
require_relative "evaluations/evaluation_storage"
require_relative "evaluations/context_capture"

module Aidp
  # Evaluation and feedback system for AIDP outputs
  #
  # Enables users to rate generated outputs (prompts, work units, work loops)
  # as good, neutral, or bad while capturing rich execution context.
  #
  # @example Creating and storing an evaluation
  #   record = Aidp::Evaluations::EvaluationRecord.new(
  #     rating: "good",
  #     comment: "Clean code generated",
  #     target_type: "work_unit"
  #   )
  #   storage = Aidp::Evaluations::EvaluationStorage.new
  #   storage.store(record)
  module Evaluations
  end
end
