Feature: Analyze Workflow with TUI
  As a developer
  I want to run analyze mode workflows with enhanced TUI
  So that I can analyze my codebase through a rich terminal interface

  Background:
    Given I am in a project directory
    And the project has analyze mode templates
    And all external AI providers are mocked

  Scenario: Start analyze workflow with TUI
    When I run "aidp analyze"
    Then I should see "Starting analyze mode with enhanced TUI harness"
    And I should see "Press Ctrl+C to stop"
    And I should see progress indicators
    And the command should exit with status 0

  Scenario: Start analyze workflow in traditional mode
    When I run "aidp analyze --no-harness"
    Then I should see "Available steps"
    And I should see "Use 'aidp analyze' without arguments"
    And the command should exit with status 0

  Scenario: Run specific analyze step with TUI
    When I run "aidp analyze 01_REPOSITORY_ANALYSIS"
    Then I should see "Running analyze step '01_REPOSITORY_ANALYSIS' with enhanced TUI harness"
    And I should see progress indicators
    And the command should exit with status 0

  Scenario: Run next analyze step
    When I run "aidp analyze next"
    Then I should see "Running analyze step"
    And I should see progress indicators
    And the command should exit with status 0

  Scenario: Run analyze step by number
    When I run "aidp analyze 01"
    Then I should see "Running analyze step '01_REPOSITORY_ANALYSIS'"
    And I should see progress indicators
    And the command should exit with status 0

  Scenario: Cancel analyze workflow
    When I run "aidp analyze"
    And I press "Ctrl+C"
    Then I should see "Enhanced TUI harness stopped by user"
    And the command should exit with status 0

  Scenario: Reset analyze progress
    When I run "aidp analyze --reset"
    Then I should see "Reset analyze mode progress"
    And the command should exit with status 0

  Scenario: Approve analyze gate step
    When I run "aidp analyze --approve 01_REPOSITORY_ANALYSIS"
    Then I should see "Approved analyze step: 01_REPOSITORY_ANALYSIS"
    And the command should exit with status 0

  Scenario: Run analyze with background jobs
    When I run "aidp analyze --background"
    Then I should see "Starting analyze mode with enhanced TUI harness"
    And I should see background job indicators
    And the command should exit with status 0
