# frozen_string_literal: true

# Core extensions
require_relative "aidp/core_ext/class_attribute"

# Shared modules
require_relative "aidp/version"
require_relative "aidp/config"
require_relative "aidp/util"
require_relative "aidp/cli"
require_relative "aidp/cli/jobs_command"

# Job infrastructure (simplified - only harness jobs)
require_relative "aidp/jobs/harness_job"

# Providers
require_relative "aidp/providers/base"
require_relative "aidp/providers/cursor"
require_relative "aidp/providers/anthropic"
require_relative "aidp/providers/gemini"
require_relative "aidp/providers/macos_ui"
require_relative "aidp/providers/supervised_base"
require_relative "aidp/providers/supervised_cursor"
require_relative "aidp/provider_manager"

# Simple file-based storage
require_relative "aidp/storage/json_storage"
require_relative "aidp/storage/csv_storage"
require_relative "aidp/storage/file_manager"

# Analyze mode (simplified - file-based storage only)
require_relative "aidp/analyze/json_file_storage"
require_relative "aidp/analyze/error_handler"
require_relative "aidp/analyze/ruby_maat_integration"
require_relative "aidp/analyze/runner"
require_relative "aidp/analyze/steps"
require_relative "aidp/analyze/progress"

# Tree-sitter analysis
require_relative "aidp/analysis/tree_sitter_grammar_loader"
require_relative "aidp/analysis/seams"
require_relative "aidp/analysis/tree_sitter_scan"
require_relative "aidp/analysis/kb_inspector"

# Execute mode
require_relative "aidp/execute/steps"
require_relative "aidp/execute/runner"
require_relative "aidp/execute/progress"

# Harness mode
require_relative "aidp/harness/configuration"
require_relative "aidp/harness/config_schema"
require_relative "aidp/harness/config_validator"
require_relative "aidp/harness/config_loader"
require_relative "aidp/harness/config_manager"
require_relative "aidp/harness/config_migrator"
require_relative "aidp/harness/condition_detector"
require_relative "aidp/harness/user_interface"
require_relative "aidp/harness/provider_manager"
require_relative "aidp/harness/provider_config"
require_relative "aidp/harness/provider_factory"
require_relative "aidp/harness/state_manager"
require_relative "aidp/harness/error_handler"
require_relative "aidp/harness/error_logger"
require_relative "aidp/harness/status_display"
require_relative "aidp/harness/runner"

# UI components
require_relative "aidp/harness/ui/spinner_helper"

# CLI commands
