Feature: TUI Dashboard
  As a developer
  I want to access the TUI dashboard
  So that I can monitor system status and job progress

  Background:
    Given I am in a project directory
    And all external AI providers are mocked

  Scenario: Show TUI dashboard overview
    When I run "aidp dashboard"
    Then I should see "Starting TUI Dashboard"
    And I should see "View: overview"
    And I should see "TUI Dashboard would be displayed here"
    And I should see "Real-time job monitoring"
    And the command should exit with status 0

  Scenario: Show TUI dashboard with specific view
    When I run "aidp dashboard --view jobs"
    Then I should see "Starting TUI Dashboard"
    And I should see "View: jobs"
    And I should see "TUI Dashboard would be displayed here"
    And the command should exit with status 0

  Scenario: Show enhanced status
    When I run "aidp status"
    Then I should see "AI Dev Pipeline Enhanced Status"
    And I should see "Execute Mode"
    And I should see "Analyze Mode"
    And the command should exit with status 0

  Scenario: Show jobs command
    When I run "aidp jobs"
    Then I should see job management interface
    And the command should exit with status 0

  Scenario: Show harness status
    When I run "aidp harness status"
    Then I should see "Enhanced Harness Status"
    And I should see "Analyze Mode"
    And I should see "Execute Mode"
    And the command should exit with status 0

  Scenario: Reset harness with confirmation
    When I run "aidp harness reset --mode analyze"
    Then I should see "This will reset all harness state for analyze mode"
    And I should see "Reset harness state for analyze mode"
    And the command should exit with status 0
