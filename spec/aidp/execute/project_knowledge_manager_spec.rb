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
    tool_note = File.read(File.join(temp_dir, "docs", "tools", "rspec.md"))

    expect(feature_note).to include("<authentication_flow:lib/user.rb>")
    expect(feature_note).not_to include("16 Implementation")
    expect(feature_note).to include("## Recent Learnings")
    expect(tool_note).to include("<rspec:spec/user_spec.rb>")
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

  it "does not collapse feature notes to a generic container directory" do
    manager.sync!(
      step_name: "99_SIMPLE_TASK",
      task_description: "Update frontend components and hooks",
      affected_files: ["src/components/Button.tsx", "src/hooks/useAuth.ts"],
      tool_commands: []
    )

    expect(File).to exist(File.join(temp_dir, "docs", "features", "components_button.md"))
    expect(File).not_to exist(File.join(temp_dir, "docs", "features", "src.md"))
  end

  it "does not create a feature note from docs and spec paths alone" do
    manager.sync!(
      step_name: "99_SIMPLE_TASK",
      task_description: "Update documentation",
      affected_files: ["docs/guide.md", "spec/models/user_spec.rb"],
      tool_commands: []
    )

    expect(Dir.glob(File.join(temp_dir, "docs", "features", "*.md"))).to be_empty
  end

  it "stores recent learnings as a single concise line" do
    manager.sync!(
      step_name: "authentication_flow",
      feature_identifier: "authentication_flow",
      task_description: "Update authentication flow\n\nSummary line one\nSummary line two",
      affected_files: ["lib/authentication/session_manager.rb"],
      tool_commands: []
    )

    feature_note = File.read(File.join(temp_dir, "docs", "features", "authentication_flow.md"))

    expect(feature_note).to include("Update authentication flow Summary line one Summary line two")
    expect(feature_note).not_to include("Update authentication flow\n\nSummary line one")
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

  it "deduplicates recent learnings by normalized text instead of timestamp" do
    allow(Time).to receive(:now)
      .and_return(
        Time.utc(2026, 7, 29, 10, 0, 0),
        Time.utc(2026, 7, 29, 10, 0, 0),
        Time.utc(2026, 7, 29, 10, 5, 0),
        Time.utc(2026, 7, 29, 10, 5, 0)
      )

    2.times do
      manager.sync!(
        step_name: "authentication_flow",
        feature_identifier: "authentication_flow",
        task_description: "Update authentication flow",
        affected_files: ["lib/user.rb"],
        tool_commands: ["bundle exec rspec"]
      )
    end

    feature_note = File.read(File.join(temp_dir, "docs", "features", "authentication_flow.md"))
    tool_note = File.read(File.join(temp_dir, "docs", "tools", "rspec.md"))

    expect(feature_note.scan("Update authentication flow").size).to eq(1)
    expect(tool_note.scan("Used `bundle exec rspec` during `authentication_flow`.").size).to eq(1)
  end

  it "groups command variants under the executable tool note" do
    manager.sync!(
      step_name: "test_authentication",
      task_description: "Verify authentication specs",
      affected_files: ["spec/models/user_spec.rb"],
      tool_commands: [
        "bundle exec rspec spec/models/user_spec.rb",
        "bundle exec rspec spec/services/auth_spec.rb"
      ]
    )

    tool_note = File.read(File.join(temp_dir, "docs", "tools", "rspec.md"))

    expect(tool_note).to include("<rspec:spec/models/user_spec.rb>")
    expect(tool_note).to include("`bundle exec rspec spec/models/user_spec.rb`")
    expect(tool_note).to include("`bundle exec rspec spec/services/auth_spec.rb`")
  end

  it "unwraps launcher commands before deriving the tool identifier" do
    manager.sync!(
      step_name: "tooling_updates",
      task_description: "Run test and maintenance commands",
      affected_files: ["bin/update-firewall-config", "spec/models/user_spec.rb"],
      tool_commands: [
        "mise exec -- bundle exec rspec spec/models/user_spec.rb",
        "/usr/bin/env RUBYOPT=-W0 bundle exec ruby bin/update-firewall-config"
      ]
    )

    rspec_note = File.read(File.join(temp_dir, "docs", "tools", "rspec.md"))
    firewall_note = File.read(File.join(temp_dir, "docs", "tools", "update_firewall_config.md"))

    expect(rspec_note).to include("`mise exec -- bundle exec rspec spec/models/user_spec.rb`")
    expect(firewall_note).to include("`/usr/bin/env RUBYOPT=-W0 bundle exec ruby bin/update-firewall-config`")
    expect(File).not_to exist(File.join(temp_dir, "docs", "tools", "mise.md"))
    expect(File).not_to exist(File.join(temp_dir, "docs", "tools", "ruby.md"))
  end
end
