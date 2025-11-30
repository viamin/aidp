# frozen_string_literal: true

module Aidp
  # Namespace marker for metadata components
  module Metadata
  end
end

# Load key metadata components
require_relative "metadata/parser"
require_relative "metadata/tool_metadata"
require_relative "metadata/scanner"
require_relative "metadata/validator"
require_relative "metadata/compiler"
require_relative "metadata/cache"
require_relative "metadata/query"
