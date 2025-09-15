Feature: Question Answering with TUI
  As a developer
  I want to answer questions through the TUI interface
  So that I can provide input to the system interactively

  Background:
    Given I am in a project directory
    And the project has question templates
    And all external AI providers are mocked

  Scenario: Answer questions through TUI prompts
    When I run "aidp execute 00_PRD"
    And the system asks "What is the main goal of this feature?"
    And I type "To enhance the user interface"
    And I press "Enter"
    Then I should see "Question answered successfully"
    And the workflow should continue

  Scenario: Answer required questions
    When I run "aidp analyze 01_REPOSITORY_ANALYSIS"
    And the system asks "What type of analysis do you want to perform?"
    And I type ""
    And I press "Enter"
    Then I should see "This question is required"
    And the system should ask the question again

  Scenario: Answer multiple choice questions
    When I run "aidp execute 01_NFRS"
    And the system asks "What is the priority level?"
    And I select "High"
    Then I should see "Priority set to High"
    And the workflow should continue

  Scenario: Answer file selection questions
    When I run "aidp analyze 02_ARCHITECTURE_ANALYSIS"
    And the system asks "Select the main configuration file"
    And I select "config.yml"
    Then I should see "Configuration file selected: config.yml"
    And the workflow should continue

  Scenario: Cancel question answering
    When I run "aidp execute 00_PRD"
    And the system asks "What is the main goal of this feature?"
    And I press "Ctrl+C"
    Then I should see "Question answering cancelled"
    And the workflow should stop gracefully

  Scenario: Answer questions with validation
    When I run "aidp analyze 03_TEST_ANALYSIS"
    And the system asks "Enter the test coverage threshold (0-100)"
    And I type "150"
    And I press "Enter"
    Then I should see "Invalid input: value must be between 0 and 100"
    And the system should ask the question again
