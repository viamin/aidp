#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"
require "tty-prompt"

module Aidp
  class CLI
    # Wrapper around Aidp::Setup::Wizard to preserve existing CLI entry points.
    class FirstRunWizard
      include Aidp::MessageDisplay

      def self.ensure_config(project_dir, non_interactive: false, prompt: TTY::Prompt.new, wizard_class: Aidp::Setup::Wizard)
        return true if Aidp::Config.config_exists?(project_dir)

        wizard = new(project_dir, prompt: prompt, wizard_class: wizard_class)

        if non_interactive
          wizard.create_minimal_config
          wizard.send(:display_message, "Created minimal configuration (non-interactive default)", type: :success)
          true
        else
          wizard.run
        end
      end

      def self.setup_config(project_dir, non_interactive: false, prompt: TTY::Prompt.new, wizard_class: Aidp::Setup::Wizard)
        if non_interactive
          new(project_dir, prompt: prompt, wizard_class: wizard_class).send(:display_message, "Configuration setup skipped in non-interactive environment", type: :info)
          return true
        end

        new(project_dir, prompt: prompt, wizard_class: wizard_class).run
      end

      def initialize(project_dir, prompt: TTY::Prompt.new, wizard_class: Aidp::Setup::Wizard)
        @project_dir = project_dir
        @prompt = prompt
        @wizard_class = wizard_class
      end

      def run
        wizard = @wizard_class.new(@project_dir, prompt: @prompt)
        wizard.run
      end

      def create_minimal_config
        Aidp::ConfigPaths.ensure_config_dir(@project_dir)
        minimal = {
          "schema_version" => Aidp::Setup::Wizard::SCHEMA_VERSION,
          "generated_by" => "aidp setup wizard minimal",
          "generated_at" => Time.now.utc.iso8601,
          "providers" => {
            "llm" => {
              "name" => "cursor",
              "model" => "cursor-agent",
              "temperature" => 0.2,
              "max_tokens" => 1024
            }
          },
          "work_loop" => {
            "test" => {
              "unit" => "bundle exec rspec",
              "timeout_seconds" => 1800
            }
          }
        }

        File.write(Aidp::ConfigPaths.config_file(@project_dir), minimal.to_yaml)
      end
    end
  end
end
