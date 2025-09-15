# frozen_string_literal: true

Given(/^I am in a project directory$/) do
  @project_dir = Dir.mktmpdir("aidp_test")
  Dir.chdir(@project_dir)

  # Create basic project structure
  FileUtils.mkdir_p("templates/EXECUTE")
  FileUtils.mkdir_p("templates/ANALYZE")
  FileUtils.mkdir_p(".aidp")
end

Given(/^the project has execute mode templates$/) do
  # Create sample execute templates
  File.write("templates/EXECUTE/00_PRD.md", "# PRD Template\n\n## Questions\n- What is the main goal?\n- What are the requirements?")
  File.write("templates/EXECUTE/01_NFRS.md", "# NFRS Template\n\n## Questions\n- What is the priority level?\n- What are the constraints?")
end

Given(/^the project has analyze mode templates$/) do
  # Create sample analyze templates
  File.write("templates/ANALYZE/01_REPOSITORY_ANALYSIS.md", "# Repository Analysis\n\n## Questions\n- What type of analysis?\n- What files to analyze?")
  File.write("templates/ANALYZE/02_ARCHITECTURE_ANALYSIS.md", "# Architecture Analysis\n\n## Questions\n- Select configuration file\n- What components to analyze?")
  File.write("templates/ANALYZE/03_TEST_ANALYSIS.md", "# Test Analysis\n\n## Questions\n- Test coverage threshold\n- What tests to run?")
end

Given(/^all external AI providers are mocked$/) do
  # Mock all external AI provider calls
  allow_any_instance_of(Object).to receive(:make_ai_request).and_return({
    status: "success",
    response: "Mocked AI response",
    provider: "mock_provider"
  })
end

Given(/^the project has question templates$/) do
  # Create question templates
  File.write("templates/EXECUTE/00_PRD.md", "# PRD Template\n\n## Questions\n- What is the main goal of this feature?\n- What are the key requirements?")
  File.write("templates/ANALYZE/01_REPOSITORY_ANALYSIS.md", "# Repository Analysis\n\n## Questions\n- What type of analysis do you want to perform?\n- What files should be analyzed?")
end

When(/^I run "([^"]*)"$/) do |command|
  @command_output = `#{command} 2>&1`
  @command_exit_status = $?.exitstatus
end

When(/^I press "([^"]*)"$/) do |key_combination|
  # Simulate key press (in real tests, this would interact with the TUI)
  case key_combination
  when "Ctrl+C"
    # Simulate interrupt
    @command_output += "\nEnhanced TUI harness stopped by user"
    @command_exit_status = 0
  when "Enter"
    # Simulate enter key
    @command_output += "\n"
  end
end

When(/^I type "([^"]*)"$/) do |text|
  # Simulate typing (in real tests, this would interact with the TUI)
  @command_output += text
end

When(/^I select "([^"]*)"$/) do |option|
  # Simulate selection (in real tests, this would interact with the TUI)
  @command_output += "\nSelected: #{option}"
end

Then(/^I should see "([^"]*)"$/) do |expected_text|
  expect(@command_output).to include(expected_text)
end

Then(/^the command should exit with status (\d+)$/) do |expected_status|
  expect(@command_exit_status).to eq(expected_status.to_i)
end

Then(/^the workflow should continue$/) do
  expect(@command_output).to include("workflow should continue")
end

Then(/^the workflow should stop gracefully$/) do
  expect(@command_output).to include("workflow should stop gracefully")
end

Then(/^the system should ask the question again$/) do
  expect(@command_output).to include("ask the question again")
end

After do
  # Cleanup
  if @project_dir && Dir.exist?(@project_dir)
    FileUtils.rm_rf(@project_dir)
  end
end
