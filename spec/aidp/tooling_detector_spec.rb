# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/aidp/tooling_detector"

RSpec.describe Aidp::ToolingDetector do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write(path, content)
    full = File.join(tmpdir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  it "detects rspec and standard in a Ruby project" do
    write("Gemfile", "source 'https://rubygems.org'\ngem 'rspec'\ngem 'standard'\n")
    write("spec/example_spec.rb", "RSpec.describe('x'){ }")

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("bundle exec rspec")
    expect(result.lint_commands).to include("bundle exec standardrb")
  end

  it "detects npm scripts with npm" do
    write("package.json", '{"scripts":{"test":"jest","lint":"eslint ."}}')

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("npm run test")
    expect(result.lint_commands.first).to match(/npm run (lint|eslint)/)
  end

  it "detects yarn if yarn.lock present" do
    write("package.json", '{"scripts":{"test":"jest"}}')
    write("yarn.lock", "# lock file")

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("yarn test")
  end

  it "detects pytest" do
    write("pytest.ini", "[pytest]")

    result = described_class.detect(tmpdir)
    expect(result.test_commands).to include("pytest -q")
  end

  it "is empty when nothing detectable" do
    result = described_class.detect(tmpdir)
    expect(result.test_commands).to be_empty
    expect(result.lint_commands).to be_empty
  end
end
