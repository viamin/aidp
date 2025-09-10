# frozen_string_literal: true

# Core extensions
require "aidp/core_ext/class_attribute"

# Shared modules
require "aidp/version"
require "aidp/config"
require "aidp/workspace"
require "aidp/util"
require "aidp/cli"
require "aidp/cli/jobs_command"
require "aidp/project_detector"
require "aidp/sync"

# Database
require "aidp/database_connection"

# Job infrastructure
require "aidp/job_manager"
require "aidp/jobs/base_job"
require "aidp/jobs/provider_execution_job"

# Providers
require "aidp/providers/base"
require "aidp/providers/cursor"
require "aidp/providers/anthropic"
require "aidp/providers/gemini"
require "aidp/providers/macos_ui"
require "aidp/provider_manager"

# Analyze mode
require "aidp/analyze/error_handler"
require "aidp/analyze/parallel_processor"
require "aidp/analyze/repository_chunker"
require "aidp/analyze/ruby_maat_integration"
require "aidp/analyze/runner"
require "aidp/analyze/steps"
require "aidp/analyze/progress"

# Tree-sitter analysis
require "aidp/analysis/tree_sitter_grammar_loader"
require "aidp/analysis/seams"
require "aidp/analysis/tree_sitter_scan"
require "aidp/analysis/kb_inspector"

# Execute mode
require "aidp/execute/steps"
require "aidp/execute/runner"
require "aidp/execute/progress"

# Harness mode
require "aidp/harness/configuration"
require "aidp/harness/config_schema"
require "aidp/harness/config_validator"
require "aidp/harness/config_loader"
require "aidp/harness/config_manager"
require "aidp/harness/config_migrator"
require "aidp/harness/condition_detector"
require "aidp/harness/user_interface"
require "aidp/harness/provider_manager"
require "aidp/harness/provider_config"
require "aidp/harness/provider_factory"
require "aidp/harness/state_manager"
require "aidp/harness/error_handler"
require "aidp/harness/error_logger"
require "aidp/harness/status_display"
require "aidp/harness/runner"
require "aidp/harness/job_manager"
require "aidp/harness/progress_tracker"
require "aidp/harness/metrics_manager"
require "aidp/harness/circuit_breaker_manager"
require "aidp/harness/fallback_manager"
require "aidp/harness/rate_limit_manager"
require "aidp/harness/rate_limit_recovery_manager"
require "aidp/harness/rate_limit_display"
require "aidp/harness/token_monitor"
require "aidp/harness/provider_status_tracker"

# CLI commands
require "aidp/cli/config_command"
