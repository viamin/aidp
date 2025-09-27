# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/aidp/harness/ui/navigation/main_menu"
require_relative "../../../../support/test_prompt"

RSpec.describe Aidp::Harness::UI::Navigation::MainMenu do
  let(:test_prompt) { TestPrompt.new }
  let(:main_menu) { described_class.new({prompt: test_prompt, output: test_prompt}) }
  let(:sample_menu_items) { build_sample_menu_items }

  describe "#display_menu" do
    context "when displaying main menu" do
      it "shows menu with correct title" do
        main_menu.display_menu("Test Menu", sample_menu_items)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Test Menu/) }).to be true
      end

      it "displays all menu items" do
        main_menu.display_menu("Test Menu", sample_menu_items)
        message_texts = test_prompt.messages.map { |m| m[:message] }
        expect(message_texts.join(" ")).to match(/Option 1.*Option 2/m)
      end

      it "includes navigation instructions" do
        main_menu.display_menu("Test Menu", sample_menu_items)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Use arrow keys/) }).to be true
      end
    end

    context "when menu items are empty" do
      it "displays empty menu message" do
        main_menu.display_menu("Empty Menu", [])
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/No options available/) }).to be true
      end
    end

    context "when menu title is nil" do
      it "uses default title" do
        main_menu.display_menu(nil, sample_menu_items)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Main Menu/) }).to be true
      end
    end
  end

  describe "#select_option" do
    context "when valid option is selected" do
      it "returns selected option" do
        test_prompt.responses[:ask] = "1"

        result = main_menu.select_option(sample_menu_items)

        expect(result).to eq(sample_menu_items[0])
      end

      it "handles numeric selection" do
        test_prompt.responses[:ask] = "2"

        result = main_menu.select_option(sample_menu_items)

        expect(result).to eq(sample_menu_items[1])
      end
    end

    context "when invalid option is selected" do
      it "prompts for valid selection" do
        test_prompt.responses[:ask] = ["99", "1"]

        result = main_menu.select_option(sample_menu_items)

        expect(result).to eq(sample_menu_items[0])
      end

      it "shows error message for invalid selection" do
        test_prompt.responses[:ask] = ["invalid", "1"]

        main_menu.select_option(sample_menu_items)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Invalid selection/) }).to be true
      end
    end

    context "when user cancels selection" do
      it "returns nil for cancel" do
        test_prompt.responses[:ask] = "q"

        result = main_menu.select_option(sample_menu_items)

        expect(result).to be_nil
      end
    end
  end

  describe "#display_breadcrumb" do
    context "when breadcrumb path exists" do
      before do
        main_menu.navigate_to("Section 1")
        main_menu.navigate_to("Subsection 1")
      end

      it "displays breadcrumb navigation" do
        main_menu.display_breadcrumb
        message_texts = test_prompt.messages.map { |m| m[:message] }
        expect(message_texts.join(" ")).to match(/Section 1.*Subsection 1/m)
      end

      it "includes breadcrumb separators" do
        main_menu.display_breadcrumb
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/>/) }).to be true
      end
    end

    context "when no navigation history exists" do
      it "displays root breadcrumb" do
        main_menu.display_breadcrumb
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Home/) }).to be true
      end
    end
  end

  describe "#navigate_to" do
    context "when navigating to new section" do
      it "adds section to navigation history" do
        main_menu.navigate_to("New Section")

        expect(main_menu.current_section).to eq("New Section")
        expect(main_menu.navigation_depth).to eq(1)
      end

      it "updates breadcrumb path" do
        main_menu.navigate_to("Test Section")

        breadcrumb = main_menu.get_breadcrumb_path
        expect(breadcrumb).to include("Test Section")
      end
    end

    context "when navigating to nested section" do
      before { main_menu.navigate_to("Parent Section") }

      it "maintains navigation hierarchy" do
        main_menu.navigate_to("Child Section")

        expect(main_menu.navigation_depth).to eq(2)
        expect(main_menu.current_section).to eq("Child Section")
      end
    end
  end

  describe "#navigate_back" do
    context "when navigation history exists" do
      before do
        main_menu.navigate_to("Section 1")
        main_menu.navigate_to("Section 2")
      end

      it "navigates to previous section" do
        main_menu.navigate_back

        expect(main_menu.current_section).to eq("Section 1")
        expect(main_menu.navigation_depth).to eq(1)
      end

      it "updates breadcrumb path" do
        main_menu.navigate_back

        breadcrumb = main_menu.get_breadcrumb_path
        expect(breadcrumb).to include("Section 1")
        expect(breadcrumb).not_to include("Section 2")
      end
    end

    context "when at root level" do
      it "does not navigate back" do
        main_menu.navigate_back

        expect(main_menu.current_section).to eq("Home")
        expect(main_menu.navigation_depth).to eq(0)
      end
    end
  end

  describe "#navigate_to_root" do
    context "when deep in navigation" do
      before do
        main_menu.navigate_to("Section 1")
        main_menu.navigate_to("Section 2")
        main_menu.navigate_to("Section 3")
      end

      it "navigates to root level" do
        main_menu.navigate_to_root

        expect(main_menu.current_section).to eq("Home")
        expect(main_menu.navigation_depth).to eq(0)
      end

      it "clears navigation history" do
        main_menu.navigate_to_root

        expect(main_menu.get_breadcrumb_path).to eq(["Home"])
      end
    end
  end

  describe "#get_navigation_history" do
    context "when navigation has occurred" do
      before do
        main_menu.navigate_to("Section 1")
        main_menu.navigate_to("Section 2")
        main_menu.navigate_back
      end

      it "returns navigation history" do
        history = main_menu.get_navigation_history

        expect(history).to be_an(Array)
        expect(history.length).to be >= 3
        expect(history.first[:action]).to eq(:navigate_to)
        expect(history.first[:section]).to eq("Section 1")
      end
    end

    context "when no navigation has occurred" do
      it "returns empty history" do
        history = main_menu.get_navigation_history

        expect(history).to be_empty
      end
    end
  end

  describe "#clear_navigation_history" do
    context "when navigation history exists" do
      before do
        main_menu.navigate_to("Section 1")
        main_menu.navigate_to("Section 2")
      end

      it "clears navigation history" do
        main_menu.clear_navigation_history

        expect(main_menu.get_navigation_history).to be_empty
        expect(main_menu.current_section).to eq("Home")
        expect(main_menu.navigation_depth).to eq(0)
      end
    end
  end

  describe "#display_navigation_help" do
    it "displays navigation help information" do
      main_menu.display_navigation_help
      expect(test_prompt.messages.any? { |msg| msg[:message].match(/Navigation Help/) }).to be true
    end

    it "includes keyboard shortcuts" do
      main_menu.display_navigation_help
      message_texts = test_prompt.messages.map { |m| m[:message] }
      expect(message_texts.join(" ")).to match(/arrow keys.*Enter.*Escape/m)
    end
  end

  describe "navigation state queries" do
    context "when at root level" do
      it "returns correct state" do
        expect(main_menu.at_root?).to be true
        expect(main_menu.can_navigate_back?).to be false
        expect(main_menu.navigation_depth).to eq(0)
      end
    end

    context "when in nested navigation" do
      before { main_menu.navigate_to("Test Section") }

      it "returns correct state" do
        expect(main_menu.at_root?).to be false
        expect(main_menu.can_navigate_back?).to be true
        expect(main_menu.navigation_depth).to eq(1)
      end
    end
  end

  private

  def build_sample_menu_items
    [
      Aidp::Harness::UI::Navigation::MenuItem.new("Option 1", :action, {description: "First option", action: -> { "option1" }}),
      Aidp::Harness::UI::Navigation::MenuItem.new("Option 2", :action, {description: "Second option", action: -> { "option2" }}),
      Aidp::Harness::UI::Navigation::MenuItem.new("Option 3", :action, {description: "Third option", action: -> { "option3" }})
    ]
  end
end
