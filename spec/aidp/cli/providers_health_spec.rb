# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Providers Health CLI" do
  def run_cli(*args)
    cmd = ["bundle", "exec", "aidp", "providers", "health", *args]
    stdout, stderr, status = Open3.capture3({"RSPEC_RUNNING" => "true"}, *cmd)
    [stdout, stderr, status]
  end

  let(:ansi_regex) { /\e\[[0-9;]*m/ }

  it "prints a header row" do
    stdout, _stderr, status = run_cli
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("Provider Health Dashboard")
    expect(stdout).to match(/Provider\s+Status\s+Avail\s+Circuit/i)
  end

  it "supports --no-color flag (no ANSI sequences)" do
    stdout, _stderr, status = run_cli("--no-color")
    expect(status.exitstatus).to eq(0)
    expect(stdout).not_to match(ansi_regex)
  end

  it "shows at least one configured provider row" do
    stdout, _stderr, status = run_cli("--no-color")
    expect(status.exitstatus).to eq(0)
    # cursor is default in test defaults
    expect(stdout).to match(/^cursor\s+/)
  end
end
