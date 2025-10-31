# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/ui/navigation/menu_state"

RSpec.describe Aidp::Harness::UI::Navigation::MenuState do
  let(:menu_state) { described_class.new }

  describe "#initialize" do
    it "initializes with empty navigation history" do
      expect(menu_state.get_navigation_history).to be_empty
    end

    it "initializes with nil current_menu" do
      expect(menu_state.current_menu).to be_nil
    end

    it "initializes with empty menu stack" do
      expect(menu_state.get_menu_stack).to be_empty
    end

    it "initializes with empty breadcrumbs" do
      expect(menu_state.get_breadcrumbs).to be_empty
    end
  end

  describe "#push_menu" do
    it "adds menu to stack" do
      menu_state.push_menu("Main Menu")
      expect(menu_state.get_menu_stack).to eq(["Main Menu"])
    end

    it "sets current menu" do
      menu_state.push_menu("Settings")
      expect(menu_state.current_menu).to eq("Settings")
    end

    it "adds to breadcrumbs" do
      menu_state.push_menu("Home")
      expect(menu_state.get_breadcrumbs).to eq(["Home"])
    end

    it "allows multiple menus" do
      menu_state.push_menu("Menu 1")
      menu_state.push_menu("Menu 2")
      expect(menu_state.get_menu_stack).to eq(["Menu 1", "Menu 2"])
    end

    it "raises error for empty menu title" do
      expect { menu_state.push_menu("") }.to raise_error(Aidp::Harness::UI::Navigation::MenuState::InvalidStateError)
    end

    it "raises error for whitespace-only menu title" do
      expect { menu_state.push_menu("   ") }.to raise_error(Aidp::Harness::UI::Navigation::MenuState::InvalidStateError)
    end
  end

  describe "#pop_menu" do
    it "removes last menu from stack" do
      menu_state.push_menu("Menu 1")
      menu_state.push_menu("Menu 2")
      menu_state.pop_menu
      expect(menu_state.get_menu_stack).to eq(["Menu 1"])
    end

    it "returns popped menu" do
      menu_state.push_menu("Menu 1")
      menu_state.push_menu("Menu 2")
      result = menu_state.pop_menu
      expect(result).to eq("Menu 1")
    end

    it "updates current menu to previous" do
      menu_state.push_menu("Menu 1")
      menu_state.push_menu("Menu 2")
      menu_state.pop_menu
      expect(menu_state.current_menu).to eq("Menu 1")
    end

    it "returns nil when stack is empty" do
      expect(menu_state.pop_menu).to be_nil
    end

    it "removes from breadcrumbs" do
      menu_state.push_menu("Menu 1")
      menu_state.push_menu("Menu 2")
      menu_state.pop_menu
      expect(menu_state.get_breadcrumbs).to eq(["Menu 1"])
    end
  end

  describe "#set_current_menu" do
    it "sets current menu" do
      menu_state.set_current_menu("Dashboard")
      expect(menu_state.current_menu).to eq("Dashboard")
    end

    it "raises error for empty title" do
      expect { menu_state.set_current_menu("") }.to raise_error(Aidp::Harness::UI::Navigation::MenuState::InvalidStateError)
    end
  end

  describe "#record_selection" do
    it "records selection in history" do
      menu_state.push_menu("Main")
      menu_state.record_selection("Option 1")
      history = menu_state.get_navigation_history
      expect(history.size).to eq(1)
      expect(history.first[:selection]).to eq("Option 1")
    end

    it "includes menu in history entry" do
      menu_state.push_menu("Settings")
      menu_state.record_selection("Change theme")
      history = menu_state.get_navigation_history
      expect(history.first[:menu]).to eq("Settings")
    end

    it "includes timestamp in history entry" do
      menu_state.record_selection("Action")
      history = menu_state.get_navigation_history
      expect(history.first[:timestamp]).to be_a(Time)
    end

    it "updates last_selection" do
      menu_state.record_selection("Last action")
      expect(menu_state.last_selection).to eq("Last action")
    end
  end

  describe "#record_workflow_mode_selection" do
    it "records workflow mode in history" do
      menu_state.push_menu("Workflow")
      menu_state.record_workflow_mode_selection("auto")
      history = menu_state.get_navigation_history
      expect(history.first[:selection]).to eq("workflow_mode: auto")
    end
  end

  describe "#record_keyboard_navigation" do
    it "records keyboard navigation" do
      menu_state.push_menu("Main")
      menu_state.record_keyboard_navigation("ctrl+n", "new_file")
      history = menu_state.get_navigation_history
      expect(history.first[:selection]).to eq("keyboard: ctrl+n -> new_file")
    end
  end

  describe "#record_progressive_disclosure" do
    it "records progressive disclosure action" do
      menu_state.push_menu("Advanced")
      menu_state.record_progressive_disclosure(2, "expand")
      history = menu_state.get_navigation_history
      expect(history.first[:selection]).to eq("progressive: level 2 -> expand")
    end
  end

  describe "#menu_depth" do
    it "returns 0 for empty stack" do
      expect(menu_state.menu_depth).to eq(0)
    end

    it "returns correct depth" do
      menu_state.push_menu("Menu 1")
      menu_state.push_menu("Menu 2")
      expect(menu_state.menu_depth).to eq(2)
    end
  end

  describe "#can_go_back?" do
    it "returns false when depth is 0" do
      expect(menu_state.can_go_back?).to be false
    end

    it "returns false when depth is 1" do
      menu_state.push_menu("Main")
      expect(menu_state.can_go_back?).to be false
    end

    it "returns true when depth is greater than 1" do
      menu_state.push_menu("Main")
      menu_state.push_menu("Sub")
      expect(menu_state.can_go_back?).to be true
    end
  end

  describe "#clear_history" do
    it "clears navigation history" do
      menu_state.record_selection("Action")
      menu_state.clear_history
      expect(menu_state.get_navigation_history).to be_empty
    end
  end

  describe "#clear_breadcrumbs" do
    it "clears breadcrumbs" do
      menu_state.push_menu("Menu")
      menu_state.clear_breadcrumbs
      expect(menu_state.get_breadcrumbs).to be_empty
    end
  end

  describe "#clear_menu_stack" do
    it "clears menu stack" do
      menu_state.push_menu("Menu")
      menu_state.clear_menu_stack
      expect(menu_state.get_menu_stack).to be_empty
    end

    it "sets current_menu to nil" do
      menu_state.push_menu("Menu")
      menu_state.clear_menu_stack
      expect(menu_state.current_menu).to be_nil
    end
  end

  describe "#reset" do
    it "clears all state" do
      menu_state.push_menu("Menu")
      menu_state.record_selection("Action")
      menu_state.reset
      expect(menu_state.get_navigation_history).to be_empty
      expect(menu_state.get_breadcrumbs).to be_empty
      expect(menu_state.get_menu_stack).to be_empty
      expect(menu_state.last_selection).to be_nil
    end
  end

  describe "#export_state" do
    it "exports full state" do
      menu_state.push_menu("Main")
      menu_state.record_selection("Action")
      state = menu_state.export_state
      expect(state).to have_key(:current_menu)
      expect(state).to have_key(:menu_stack)
      expect(state).to have_key(:breadcrumbs)
      expect(state).to have_key(:last_selection)
      expect(state).to have_key(:navigation_history)
      expect(state).to have_key(:menu_depth)
    end

    it "includes correct values" do
      menu_state.push_menu("Settings")
      menu_state.record_selection("Toggle")
      state = menu_state.export_state
      expect(state[:current_menu]).to eq("Settings")
      expect(state[:last_selection]).to eq("Toggle")
      expect(state[:menu_depth]).to eq(1)
    end
  end

  describe "error classes" do
    it "defines StateError" do
      expect(Aidp::Harness::UI::Navigation::MenuState::StateError).to be < StandardError
    end

    it "defines InvalidStateError as subclass of StateError" do
      expect(Aidp::Harness::UI::Navigation::MenuState::InvalidStateError).to be < Aidp::Harness::UI::Navigation::MenuState::StateError
    end
  end
end
