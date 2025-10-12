# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Init::ProjectAnalyzer do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:project_path) { tmp_dir }
  let(:analyzer) { described_class.new(project_path) }

  before do
    FileUtils.mkdir_p(File.join(project_path, "lib"))
    FileUtils.mkdir_p(File.join(project_path, "spec"))
    FileUtils.mkdir_p(File.join(project_path, "config"))

    File.write(File.join(project_path, "lib", "sample.rb"), "class Sample; end\n")
    File.write(File.join(project_path, "spec", "sample_spec.rb"), "RSpec.describe Sample do; end\n")
    File.write(File.join(project_path, ".rubocop.yml"), "inherit_mode: merge\n")

    File.write(File.join(project_path, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "rails"
      gem "rspec"
    GEMFILE

    FileUtils.mkdir_p(File.join(project_path, "config"))
    File.write(File.join(project_path, "config", "application.rb"), "require 'rails'\nmodule Demo; class Application < Rails::Application; end; end\n")
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it "detects languages, frameworks, and tooling" do
    analysis = analyzer.analyze

    expect(analysis[:languages].keys).to include("Ruby")
    expect(analysis[:frameworks]).to include("Rails")
    expect(analysis[:config_files]).to include(".rubocop.yml")
    expect(analysis[:test_frameworks]).to include("RSpec")
    expect(analysis[:tooling]).to have_key(:rubocop)
  end

  it "summarises repository stats" do
    stats = analyzer.analyze[:repo_stats]
    expect(stats[:total_files]).to be > 0
    expect(stats[:total_directories]).to be > 0
  end
end
