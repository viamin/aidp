# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "CLI Workstream Commands Integration", type: :integration do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(Dir).to receive(:pwd).and_return(tmpdir)
    allow(Aidp::CLI).to receive(:display_message)
    # Initialize git repo
    FileUtils.mkdir_p(File.join(tmpdir, ".git"))
  end

  after do
    FileUtils.rm_rf(tmpdir) if tmpdir && Dir.exist?(tmpdir)
  end

  describe "workstream pause command" do
    it "displays error when no slug provided" do
      Aidp::CLI.send(:run_ws_command, ["pause"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "displays error when workstream not found" do
      allow(Aidp::Worktree).to receive(:list).and_return([])

      Aidp::CLI.send(:run_ws_command, ["pause", "nonexistent"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Workstream not found/, type: :error)
    end
  end

  describe "workstream resume command" do
    it "displays error when no slug provided" do
      Aidp::CLI.send(:run_ws_command, ["resume"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "displays error when workstream not found" do
      allow(Aidp::Worktree).to receive(:list).and_return([])

      Aidp::CLI.send(:run_ws_command, ["resume", "nonexistent"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Workstream not found/, type: :error)
    end
  end

  describe "workstream complete command" do
    it "displays error when no slug provided" do
      Aidp::CLI.send(:run_ws_command, ["complete"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "displays error when workstream not found" do
      allow(Aidp::Worktree).to receive(:list).and_return([])

      Aidp::CLI.send(:run_ws_command, ["complete", "nonexistent"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Workstream not found/, type: :error)
    end
  end

  describe "workstream list command" do
    it "displays message when no workstreams exist" do
      allow(Aidp::Worktree).to receive(:list).and_return([])

      Aidp::CLI.send(:run_ws_command, ["list"])

      expect(Aidp::CLI).to have_received(:display_message).with(/No workstreams found/, type: :info)
    end
  end

  describe "workstream new command" do
    it "displays usage when no slug provided" do
      Aidp::CLI.send(:run_ws_command, ["new"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end
  end

  describe "workstream rm command" do
    it "displays usage when no slug provided" do
      Aidp::CLI.send(:run_ws_command, ["rm"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end
  end

  describe "workstream status command" do
    it "displays usage when no slug provided" do
      Aidp::CLI.send(:run_ws_command, ["status"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "displays error when workstream not found" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)

      Aidp::CLI.send(:run_ws_command, ["status", "nonexistent"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Workstream not found/, type: :error)
    end
  end

  describe "workstream run command" do
    it "displays usage when no slug provided" do
      Aidp::CLI.send(:run_ws_command, ["run"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end
  end

  describe "workstream unknown command" do
    it "displays usage for unknown subcommand" do
      Aidp::CLI.send(:run_ws_command, ["unknown"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end
  end
end
