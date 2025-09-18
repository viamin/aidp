# frozen_string_literal: true

require "pastel"

module Aidp
  module Harness
    module UI
      module Navigation
        # Formats menu display elements
        class MenuFormatter
          def initialize
            @pastel = Pastel.new
          end

          def format_menu_title(title)
            @pastel.bold(@pastel.blue("📋 #{title}"))
          end

          def format_separator
            "─" * 50
          end

          def format_breadcrumb(breadcrumbs)
            breadcrumb_text = breadcrumbs.join(" > ")
            @pastel.dim("📍 #{breadcrumb_text}")
          end

          def format_menu_item(item, index)
            return format_separator_item if item.separator?

            prefix = format_item_prefix(index)
            title = format_item_title(item)
            description = format_item_description(item)
            status = format_item_status(item)

            "#{prefix} #{title}#{description}#{status}"
          end

          def format_item_prefix(index)
            @pastel.bold("#{index}.")
          end

          def format_item_title(item)
            if item.disabled?
              @pastel.dim(item.title)
            elsif item.hidden?
              @pastel.dim(item.title)
            else
              @pastel.bold(item.title)
            end
          end

          def format_item_description(item)
            return "" unless item.description

            " #{@pastel.dim("- #{item.description}")}"
          end

          def format_item_status(item)
            return " #{@pastel.red("[DISABLED]")}" if item.disabled?
            return " #{@pastel.yellow("[HIDDEN]")}" if item.hidden?
            ""
          end

          def format_separator_item
            @pastel.dim("────────────────────────────────────────")
          end

          def format_shortcut(shortcut)
            @pastel.dim("(#{shortcut})")
          end

          def format_menu_depth(depth)
            @pastel.dim("Level #{depth}")
          end

          def format_navigation_prompt
            @pastel.bold("Select an option:")
          end

          def format_back_option
            @pastel.dim("← Back")
          end

          def format_exit_option
            @pastel.red("✗ Exit")
          end

          def format_workflow_title(workflow_name)
            @pastel.bold(@pastel.green("🔄 #{workflow_name} Workflow"))
          end

          def format_action_title(action_name)
            @pastel.bold(@pastel.blue("⚡ #{action_name}"))
          end

          def format_submenu_title(submenu_name)
            @pastel.bold(@pastel.yellow("📁 #{submenu_name}"))
          end

          def format_error_message(error)
            "#{@pastel.red("❌ Error:")} #{error}"
          end

          def format_success_message(message)
            @pastel.green("✅ #{message}")
          end

          def format_warning_message(message)
            @pastel.yellow("⚠️ #{message}")
          end

          def format_info_message(message)
            @pastel.blue("ℹ️ #{message}")
          end
        end
      end
    end
  end
end
