# frozen_string_literal: true

module Aidp
  module Harness
    module UI
      module Navigation
        # Formats menu display elements
        class MenuFormatter
          def format_menu_title(title)
            CLI::UI.fmt("{{bold:{{blue:📋 #{title}}}}}")
          end

          def format_separator
            "─" * 50
          end

          def format_breadcrumb(breadcrumbs)
            breadcrumb_text = breadcrumbs.join(" > ")
            CLI::UI.fmt("{{dim:📍 #{breadcrumb_text}}}")
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
            CLI::UI.fmt("{{bold:#{index}.}}")
          end

          def format_item_title(item)
            if item.disabled?
              CLI::UI.fmt("{{dim:#{item.title}}}")
            elsif item.hidden?
              CLI::UI.fmt("{{dim:#{item.title}}}")
            else
              CLI::UI.fmt("{{bold:#{item.title}}}")
            end
          end

          def format_item_description(item)
            return "" unless item.description

            CLI::UI.fmt(" {{dim:- #{item.description}}}")
          end

          def format_item_status(item)
            return CLI::UI.fmt(" {{red:[DISABLED]}}") if item.disabled?
            return CLI::UI.fmt(" {{yellow:[HIDDEN]}}") if item.hidden?
            ""
          end

          def format_separator_item
            CLI::UI.fmt("{{dim:────────────────────────────────────────}}")
          end

          def format_shortcut(shortcut)
            CLI::UI.fmt("{{dim:(#{shortcut})}}")
          end

          def format_menu_depth(depth)
            CLI::UI.fmt("{{dim:Level #{depth}}}")
          end

          def format_navigation_prompt
            CLI::UI.fmt("{{bold:Select an option:}}")
          end

          def format_back_option
            CLI::UI.fmt("{{dim:← Back}}")
          end

          def format_exit_option
            CLI::UI.fmt("{{red:✗ Exit}}")
          end

          def format_workflow_title(workflow_name)
            CLI::UI.fmt("{{bold:{{green:🔄 #{workflow_name} Workflow}}}}")
          end

          def format_action_title(action_name)
            CLI::UI.fmt("{{bold:{{blue:⚡ #{action_name}}}}}")
          end

          def format_submenu_title(submenu_name)
            CLI::UI.fmt("{{bold:{{yellow:📁 #{submenu_name}}}}}")
          end

          def format_error_message(error)
            CLI::UI.fmt("{{red:❌ Error:}} #{error}")
          end

          def format_success_message(message)
            CLI::UI.fmt("{{green:✅ #{message}}}")
          end

          def format_warning_message(message)
            CLI::UI.fmt("{{yellow:⚠️ #{message}}}")
          end

          def format_info_message(message)
            CLI::UI.fmt("{{blue:ℹ️ #{message}}}")
          end
        end
      end
    end
  end
end
