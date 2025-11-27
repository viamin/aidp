# frozen_string_literal: true

require "zeitwerk"

module Aidp
  # Zeitwerk-based class loader with hot code reloading support
  #
  # This module configures Zeitwerk for autoloading AIDP classes and provides
  # a reload capability similar to Rails development mode. When files change
  # (e.g., after git pull in watch mode), calling Aidp::Loader.reload! will
  # unload all classes and allow them to be reloaded on next reference.
  #
  # @example Enable reloading in development
  #   Aidp::Loader.setup(enable_reloading: true)
  #   # ... code changes on disk ...
  #   Aidp::Loader.reload!
  #
  # @example Production mode (no reloading)
  #   Aidp::Loader.setup(enable_reloading: false)
  #   Aidp::Loader.eager_load!
  module Loader
    class << self
      # @return [Zeitwerk::Loader, nil] The configured loader instance
      attr_reader :loader

      # @return [Boolean] Whether reloading is enabled
      attr_reader :reloading_enabled

      # Set up the Zeitwerk loader for AIDP
      #
      # @param enable_reloading [Boolean] Whether to enable hot reloading
      # @param eager_load [Boolean] Whether to eager load all classes
      # @return [Zeitwerk::Loader] The configured loader
      def setup(enable_reloading: false, eager_load: false)
        return @loader if @loader

        Aidp.log_debug("loader", "setup_started",
          enable_reloading: enable_reloading,
          eager_load: eager_load)

        @reloading_enabled = enable_reloading
        @loader = create_loader
        configure_inflections(@loader)
        configure_ignores(@loader)

        if enable_reloading
          @loader.enable_reloading
          Aidp.log_debug("loader", "reloading_enabled")
        end

        @loader.setup

        if eager_load && !enable_reloading
          @loader.eager_load
          Aidp.log_debug("loader", "eager_load_complete")
        end

        Aidp.log_info("loader", "setup_complete",
          reloading: enable_reloading,
          eager_loaded: eager_load && !enable_reloading)

        @loader
      end

      # Reload all autoloaded classes
      #
      # This unloads all classes managed by Zeitwerk and allows them to be
      # reloaded on next reference. Only works if enable_reloading was true
      # during setup.
      #
      # @return [Boolean] Whether reload was performed
      def reload!
        unless @loader
          Aidp.log_warn("loader", "reload_skipped", reason: "loader_not_setup")
          return false
        end

        unless @reloading_enabled
          Aidp.log_warn("loader", "reload_skipped", reason: "reloading_disabled")
          return false
        end

        Aidp.log_info("loader", "reload_started")

        begin
          @loader.reload
          Aidp.log_info("loader", "reload_complete")
          true
        rescue => e
          Aidp.log_error("loader", "reload_failed", error: e.message)
          false
        end
      end

      # Check if loader is set up for reloading
      #
      # @return [Boolean]
      def reloading?
        @reloading_enabled == true
      end

      # Check if loader is set up
      #
      # @return [Boolean]
      def setup?
        !@loader.nil?
      end

      # Eager load all classes (production mode)
      #
      # @return [void]
      def eager_load!
        @loader&.eager_load
      end

      # Reset the loader (mainly for testing)
      #
      # @return [void]
      def reset!
        if @loader
          @loader.unload if @reloading_enabled
          @loader.unregister
        end
        @loader = nil
        @reloading_enabled = false
      end

      private

      def create_loader
        loader = Zeitwerk::Loader.new
        loader.tag = "aidp"

        # Set the root directory for autoloading
        lib_path = File.expand_path("..", __dir__)
        loader.push_dir(lib_path, namespace: Object)

        loader
      end

      # Configure inflections for non-standard class names
      def configure_inflections(loader)
        loader.inflector.inflect(
          # AI-prefixed classes
          "ai_decision_engine" => "AIDecisionEngine",
          "ai_filter_factory" => "AIFilterFactory",

          # Acronym-based names
          "kb_inspector" => "KBInspector",
          "ui_state" => "UIState",
          "ui_error" => "UIError",

          # TTY-related
          "tui" => "TUI",
          "enhanced_tui" => "EnhancedTUI",

          # Other acronyms
          "pr_worktree_manager" => "PRWorktreeManager",
          "csv_storage" => "CSVStorage",
          "cli" => "CLI",
          "ruby_llm_registry" => "RubyLLMRegistry",
          "rubygems_api_adapter" => "RubyGemsAPIAdapter",
          "submenu" => "SubMenu",

          # Module folders
          "ui" => "UI"
        )
      end

      # Configure files/directories to ignore
      def configure_ignores(loader)
        # Ignore files that are manually required before Zeitwerk
        loader.ignore(File.expand_path("version.rb", __dir__))
        loader.ignore(File.expand_path("core_ext", __dir__))
        loader.ignore(File.expand_path("logger.rb", __dir__))

        # Ignore the loader itself
        loader.ignore(__FILE__)

        # Ignore files with multiple constants (require manually after setup)
        loader.ignore(File.expand_path("auto_update/errors.rb", __dir__))
        loader.ignore(File.expand_path("errors.rb", __dir__))
        loader.ignore(File.expand_path("harness/state/errors.rb", __dir__))
      end
    end
  end
end
