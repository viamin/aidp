# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/ui/navigation/submenu"
require "aidp/harness/ui/navigation/menu_item"

RSpec.describe Aidp::Harness::UI::Navigation::SubMenu do
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:formatter) { double("MenuFormatter") }
  let(:ui_components) { {prompt: prompt, formatter: formatter} }
  let(:submenu) { described_class.new("Test Menu", nil, ui_components) }
  let(:menu_item) do
    Aidp::Harness::UI::Navigation::MenuItem.new("Test Item", :action, {action: -> { "executed" }})
  end

  before do
    allow(formatter).to receive(:format_submenu_title).and_return("Test Menu")
    allow(formatter).to receive(:format_separator).and_return("---")
    allow(formatter).to receive(:format_parent_path).and_return("parent > path")
    allow(formatter).to receive(:format_submenu_item).and_return("1. Test Item")
    allow(formatter).to receive(:format_menu_item).and_return("Test Item")
    allow(prompt).to receive(:say)
    allow(prompt).to receive(:ask).and_return("Exit")
  end

  describe "#initialize" do
    it "accepts a title and parent menu" do
      parent = described_class.new("Parent", nil, ui_components)
      child = described_class.new("Child", parent, ui_components)
      expect(child.title).to eq("Child")
      expect(child.parent_menu).to eq(parent)
    end

    it "initializes with default settings" do
      expect(submenu.drill_down_enabled).to be true
      expect(submenu.max_depth).to eq(5)
    end
  end

  describe "#add_submenu_item" do
    it "adds a valid menu item" do
      expect { submenu.add_submenu_item(menu_item) }.not_to raise_error
    end

    it "raises error for invalid item" do
      expect { submenu.add_submenu_item("not a menu item") }.to raise_error(Aidp::Harness::UI::Navigation::MainMenu::InvalidMenuError)
    end
  end

  describe "#add_submenu_items" do
    it "adds multiple items" do
      item1 = Aidp::Harness::UI::Navigation::MenuItem.new("Item 1", :action, {action: -> {}})
      item2 = Aidp::Harness::UI::Navigation::MenuItem.new("Item 2", :action, {action: -> {}})
      expect { submenu.add_submenu_items([item1, item2]) }.not_to raise_error
    end

    it "raises error for non-array input" do
      expect { submenu.add_submenu_items("not an array") }.to raise_error(Aidp::Harness::UI::Navigation::SubMenu::InvalidSubMenuError)
    end
  end

  describe "#show_submenu" do
    before do
      submenu.add_submenu_item(menu_item)
    end

    it "displays submenu when conditions are met" do
      expect(prompt).to receive(:say).at_least(:once)
      expect(prompt).to receive(:ask).and_return("Exit")
      submenu.show_submenu
    end

    it "does not display when drill down is disabled" do
      submenu.drill_down_enabled = false
      expect(prompt).not_to receive(:say)
      submenu.show_submenu
    end
  end

  describe "#can_show_submenu?" do
    it "returns true when all conditions are met" do
      submenu.add_submenu_item(menu_item)
      expect(submenu.can_show_submenu?).to be true
    end

    it "returns false when no items" do
      expect(submenu.can_show_submenu?).to be false
    end

    it "returns false when drill down disabled" do
      submenu.add_submenu_item(menu_item)
      submenu.drill_down_enabled = false
      expect(submenu.can_show_submenu?).to be false
    end
  end

  describe "#within_depth_limit?" do
    it "returns true when within limit" do
      submenu.instance_variable_set(:@current_level, 2)
      expect(submenu.within_depth_limit?).to be true
    end

    it "returns false when at limit" do
      submenu.instance_variable_set(:@current_level, 5)
      expect(submenu.within_depth_limit?).to be false
    end
  end

  describe "#has_parent?" do
    it "returns false when no parent" do
      expect(submenu.has_parent?).to be false
    end

    it "returns true when has parent" do
      parent = described_class.new("Parent", nil, ui_components)
      child = described_class.new("Child", parent, ui_components)
      expect(child.has_parent?).to be true
    end
  end

  describe "#get_parent_path" do
    it "returns empty array when no parent" do
      expect(submenu.get_parent_path).to eq([])
    end

    it "returns path with single parent" do
      parent = described_class.new("Parent", nil, ui_components)
      child = described_class.new("Child", parent, ui_components)
      expect(child.get_parent_path).to eq(["Child"])
    end
  end

  describe "#get_full_path" do
    it "returns path including self" do
      expect(submenu.get_full_path).to include("Test Menu")
    end

    it "returns full hierarchy path" do
      parent = described_class.new("Parent", nil, ui_components)
      child = described_class.new("Child", parent, ui_components)
      path = child.get_full_path
      expect(path).to be_an(Array)
      expect(path).to include("Child")
    end
  end

  describe "#create_child_submenu" do
    it "creates a child submenu" do
      child = submenu.create_child_submenu("Child Menu")
      expect(child).to be_a(described_class)
      expect(child.title).to eq("Child Menu")
      expect(child.parent_menu).to eq(submenu)
    end

    it "raises error at max depth" do
      submenu.instance_variable_set(:@current_level, 5)
      expect { submenu.create_child_submenu("Child") }.to raise_error(Aidp::Harness::UI::Navigation::SubMenu::InvalidSubMenuError)
    end
  end

  describe "#navigate_to_parent" do
    it "returns false when no parent" do
      expect(submenu.navigate_to_parent).to be false
    end

    it "navigates to parent when available" do
      parent = described_class.new("Parent", nil, ui_components)
      child = described_class.new("Child", parent, ui_components)

      allow(parent).to receive(:show_menu)
      result = child.navigate_to_parent
      expect(result).to be true
    end
  end
end
