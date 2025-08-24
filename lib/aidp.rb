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

# Execute mode
require "aidp/execute/steps"
require "aidp/execute/runner"
require "aidp/execute/progress"
