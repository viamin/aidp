Feature: Execute Workflow with TUI
  As a developer
  I want to run execute mode workflows with enhanced TUI
  So that I can interact with the system through a rich terminal interface

  Background:
    Given I am in a project directory
    And the project has execute mode templates
    And all external AI providers are mocked

  Scenario: Start execute workflow with TUI
    When I run "aidp execute"
    Then I should see "Starting enhanced TUI harness"
    And I should see "Press Ctrl+C to stop"
    And I should see workflow selection options
    And the command should exit with status 0

  Scenario: Start execute workflow in traditional mode
    When I run "aidp execute --no-harness"
    Then I should see "Available execute steps"
    And I should see "Use 'aidp execute' without arguments"
    And the command should exit with status 0

  Scenario: Run specific execute step with TUI
    When I run "aidp execute 00_PRD"
    Then I should see "Running execute step '00_PRD' with enhanced TUI harness"
    And I should see progress indicators
    And the command should exit with status 0

  Scenario: Cancel execute workflow
    When I run "aidp execute"
    And I press "Ctrl+C"
    Then I should see "Enhanced TUI harness stopped by user"
    And the command should exit with status 0

  Scenario: Reset execute progress
    When I run "aidp execute --reset"
    Then I should see "Reset execute mode progress"
    And the command should exit with status 0

  Scenario: Approve execute gate step
    When I run "aidp execute --approve 00_PRD"
    Then I should see "Approved execute step: 00_PRD"
    And the command should exit with status 0
