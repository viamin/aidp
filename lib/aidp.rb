# frozen_string_literal: true

# Bootstrap: Load essential files before Zeitwerk
# These files must be loaded first and are excluded from autoloading:
# - version.rb: Needed for version checks during load
# - core_ext: Ruby core extensions that need to be available globally
# - logger.rb: Logging infrastructure used throughout loading

require_relative "aidp/version"
require_relative "aidp/core_ext/class_attribute"
require_relative "aidp/logger"

# Now set up Zeitwerk autoloader for the rest of the codebase
require_relative "aidp/loader"

# Configure Zeitwerk based on environment
# In watch mode or development, enable reloading for hot code updates
# In production, disable reloading and eager load for performance
reloading_enabled = ENV["AIDP_ENABLE_RELOADING"] == "1" ||
  ENV["AIDP_WATCH_MODE"] == "1"

Aidp::Loader.setup(
  enable_reloading: reloading_enabled,
  eager_load: !reloading_enabled && ENV["AIDP_EAGER_LOAD"] == "1"
)

# Manually require files that contain multiple constants (not autoloadable by Zeitwerk)
require_relative "aidp/errors"
require_relative "aidp/auto_update/errors"
require_relative "aidp/harness/state/errors"
