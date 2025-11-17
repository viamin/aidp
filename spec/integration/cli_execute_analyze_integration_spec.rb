# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "CLI Execute/Analyze Commands Integration", type: :integration do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(Dir).to receive(:pwd).and_return(tmpdir)
    allow(Aidp::CLI).to receive(:display_message)
  end

  after do
    FileUtils.rm_rf(tmpdir) if tmpdir && Dir.exist?(tmpdir)
  end

  describe "execute command without arguments" do
    it "displays available steps when no arguments provided" do
      Aidp::CLI.send(:run_execute_command, [], mode: :execute)

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end
  end

  describe "analyze command without arguments" do
    it "displays available steps when no arguments provided" do
      Aidp::CLI.send(:run_execute_command, [], mode: :analyze)

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end
  end

  describe "execute --approve flag" do
    it "accepts --approve with step argument" do
      Aidp::CLI.send(:run_execute_command, ["--approve", "00_PRD"], mode: :execute)

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end
  end

  describe "analyze --approve flag" do
    it "accepts --approve with step argument" do
      Aidp::CLI.send(:run_execute_command, ["--approve", "00_ANALYSIS"], mode: :analyze)

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end
  end
end
