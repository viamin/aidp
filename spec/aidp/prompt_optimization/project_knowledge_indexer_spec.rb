# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/prompt_optimization/project_knowledge_indexer"

RSpec.describe Aidp::PromptOptimization::ProjectKnowledgeIndexer do
  let(:temp_dir) { Dir.mktmpdir }
  let(:indexer) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  it "indexes feature and tool notes with linked paths" do
    FileUtils.mkdir_p(File.join(temp_dir, "docs", "features"))
    FileUtils.mkdir_p(File.join(temp_dir, "docs", "tools"))

    File.write(File.join(temp_dir, "docs", "features", "auth.md"), <<~MARKDOWN)
      # Authentication

      <authentication:lib/user.rb>
    MARKDOWN

    File.write(File.join(temp_dir, "docs", "tools", "rspec.md"), <<~MARKDOWN)
      # Rspec

      <rspec:spec/user_spec.rb>
    MARKDOWN

    fragments = indexer.index!

    expect(fragments.map(&:note_type)).to contain_exactly(:feature, :tool)
    expect(fragments.find { |fragment| fragment.note_type == :feature }.linked_paths).to eq(["lib/user.rb"])
  end
end
