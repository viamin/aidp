# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/execute/project_knowledge_manager"

RSpec.describe Aidp::Execute::ProjectKnowledgeManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:manager) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  it "uses an explicit feature identifier instead of the workflow step name" do
    manager.sync!(
      step_name: "16_IMPLEMENTATION",
      feature_identifier: "authentication_flow",
      task_description: "Update authentication flow",
      affected_files: ["lib/user.rb", "spec/user_spec.rb"],
      tool_commands: ["bundle exec rspec"]
    )

    feature_note = File.read(File.join(temp_dir, "docs", "features", "authentication_flow.md"))
    tool_note = File.read(File.join(temp_dir, "docs", "tools", "bundle_exec_rspec.md"))

    expect(feature_note).to include("<authentication_flow:lib/user.rb>")
    expect(feature_note).not_to include("16 Implementation")
    expect(feature_note).to include("## Recent Learnings")
    expect(tool_note).to include("<bundle_exec_rspec:spec/user_spec.rb>")
    expect(tool_note).to include("`bundle exec rspec`")
  end

  it "derives a feature identifier from affected files when none is provided" do
    manager.sync!(
      step_name: "99_SIMPLE_TASK",
      task_description: "Update authentication flow",
      affected_files: ["lib/authentication/session_manager.rb", "spec/authentication/session_manager_spec.rb"],
      tool_commands: []
    )

    feature_note = File.read(File.join(temp_dir, "docs", "features", "authentication_session_manager.md"))

    expect(feature_note).to include("<authentication_session_manager:lib/authentication/session_manager.rb>")
  end

  it "updates existing notes without duplicating entries" do
    manager.sync!(
      step_name: "authentication_flow",
      feature_identifier: "authentication_flow",
      task_description: "Update authentication flow",
      affected_files: ["lib/user.rb"],
      tool_commands: ["bundle exec rspec"]
    )

    manager.sync!(
      step_name: "authentication_flow",
      feature_identifier: "authentication_flow",
      task_description: "Update authentication flow",
      affected_files: ["lib/user.rb"],
      tool_commands: ["bundle exec rspec"]
    )

    feature_note = File.read(File.join(temp_dir, "docs", "features", "authentication_flow.md"))
    expect(feature_note.scan("<authentication_flow:lib/user.rb>").size).to eq(1)
  end
end
