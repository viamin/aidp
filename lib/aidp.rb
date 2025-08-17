# frozen_string_literal: true

# Shared modules
require "aidp/version"
require "aidp/config"
require "aidp/workspace"
require "aidp/util"
require "aidp/cli"
require "aidp/project_detector"
require "aidp/sync"
require "aidp/providers/base"
require "aidp/providers/cursor"
require "aidp/providers/anthropic"
require "aidp/providers/gemini"
require "aidp/providers/macos_ui"

# Execute mode modules
require "aidp/execute/steps"
require "aidp/execute/runner"
require "aidp/execute/progress"

# Analyze mode modules
require "aidp/analyze/steps"
require "aidp/analyze/runner"
require "aidp/analyze/progress"
require "aidp/analyze/dependencies"
require "aidp/analyze/storage"
require "aidp/analyze/prioritizer"
require "aidp/analyze/database"
require "aidp/analyze/ruby_maat_integration"
require "aidp/analyze/feature_analyzer"
require "aidp/analyze/focus_guidance"
require "aidp/analyze/agent_personas"
require "aidp/analyze/agent_tool_executor"
require "aidp/analyze/static_analysis_detector"
require "aidp/analyze/tool_configuration"
require "aidp/analyze/tool_modernization"
require "aidp/analyze/language_analysis_strategies"
require "aidp/analyze/report_generator"
require "aidp/analyze/export_manager"
require "aidp/analyze/incremental_analyzer"
require "aidp/analyze/progress_visualizer"
require "aidp/analyze/data_retention_manager"
require "aidp/analyze/repository_chunker"
require "aidp/analyze/parallel_processor"
require "aidp/analyze/memory_manager"
require "aidp/analyze/large_analysis_progress"
require "aidp/analyze/performance_optimizer"
require "aidp/analyze/error_handler"

module Aidp
  class Error < StandardError; end
end
