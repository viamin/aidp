# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Init::DocGenerator do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:analysis) do
    {
      languages: {"Ruby" => 1200, "JavaScript" => 400},
      frameworks: [
        {name: "Rails", confidence: 0.9, evidence: ["Found files: config/application.rb", "Found pattern /rails/i in config/application.rb"]}
      ],
      key_directories: ["app", "lib", "spec"],
      config_files: [".rubocop.yml", "package.json"],
      test_frameworks: [
        {name: "RSpec", confidence: 0.8, evidence: ["Found directories: spec", "Found dependency pattern /rspec/ in Gemfile"]}
      ],
      tooling: [
        {tool: :rubocop, confidence: 0.8, evidence: ["Found config files: .rubocop.yml"]},
        {tool: :eslint, confidence: 0.6, evidence: ["Referenced in package.json scripts"]}
      ],
      repo_stats: {total_files: 10, total_directories: 4, docs_present: false, has_ci_config: true, has_containerization: false}
    }
  end
  let(:preferences) do
    {adopt_new_conventions: true, stricter_linters: true, migrate_styles: false}
  end
  let(:generator) { described_class.new(tmp_dir) }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it "produces the expected documentation files" do
    generator.generate(analysis: analysis, preferences: preferences)

    style_path = File.join(tmp_dir, "docs", "LLM_STYLE_GUIDE.md")
    analysis_path = File.join(tmp_dir, "docs", "PROJECT_ANALYSIS.md")
    quality_path = File.join(tmp_dir, "docs", "CODE_QUALITY_PLAN.md")

    expect(File).to exist(style_path)
    expect(File.read(style_path)).to include("Project LLM Style Guide")
    expect(File).to exist(analysis_path)
    expect(File.read(analysis_path)).to include("Project Analysis")
    expect(File).to exist(quality_path)
    expect(File.read(quality_path)).to include("Code Quality Plan")
  end
end
