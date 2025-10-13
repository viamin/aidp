# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/repl_macros"

RSpec.describe Aidp::Execute::ReplMacros, "interactive commands" do
  let(:macros) { described_class.new }

  describe "/pause command" do
    it "returns success with pause action" do
      result = macros.execute("/pause")
      expect(result[:success]).to be true
      expect(result[:action]).to eq(:pause_work_loop)
      expect(result[:message]).to include("Pause signal")
    end
  end

  describe "/resume command" do
    it "returns success with resume action" do
      result = macros.execute("/resume")
      expect(result[:success]).to be true
      expect(result[:action]).to eq(:resume_work_loop)
      expect(result[:message]).to include("Resume signal")
    end
  end

  describe "/cancel command" do
    context "without flags" do
      it "cancels with checkpoint save" do
        result = macros.execute("/cancel")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:cancel_work_loop)
        expect(result[:data][:save_checkpoint]).to be true
      end
    end

    context "with --no-checkpoint flag" do
      it "cancels without checkpoint save" do
        result = macros.execute("/cancel --no-checkpoint")
        expect(result[:success]).to be true
        expect(result[:data][:save_checkpoint]).to be false
      end
    end
  end

  describe "/inject command" do
    context "with instruction" do
      it "enqueues instruction with normal priority" do
        result = macros.execute("/inject Add error handling")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:enqueue_instruction)
        expect(result[:data][:instruction]).to eq("Add error handling")
        expect(result[:data][:type]).to eq(:user_input)
        expect(result[:data][:priority]).to eq(:normal)
      end
    end

    context "with priority flag" do
      it "enqueues with high priority" do
        result = macros.execute("/inject Fix security issue --priority high")
        expect(result[:data][:priority]).to eq(:high)
      end

      it "enqueues with low priority" do
        result = macros.execute("/inject Improve logging --priority low")
        expect(result[:data][:priority]).to eq(:low)
      end
    end

    context "without instruction" do
      it "returns error" do
        result = macros.execute("/inject")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage:")
      end
    end
  end

  describe "/merge command" do
    context "with plan update" do
      it "enqueues with plan_update type and high priority" do
        result = macros.execute("/merge Add acceptance criteria: handle timeouts")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:enqueue_instruction)
        expect(result[:data][:instruction]).to eq("Add acceptance criteria: handle timeouts")
        expect(result[:data][:type]).to eq(:plan_update)
        expect(result[:data][:priority]).to eq(:high)
      end
    end

    context "without plan update" do
      it "returns error" do
        result = macros.execute("/merge")
        expect(result[:success]).to be false
      end
    end
  end

  describe "/update command" do
    context "with guard category" do
      it "updates guard configuration" do
        result = macros.execute("/update guard max_lines=500")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:update_guard)
        expect(result[:data][:key]).to eq("max_lines")
        expect(result[:data][:value]).to eq("500")
      end

      it "handles key with underscores" do
        result = macros.execute("/update guard max_lines_per_commit=300")
        expect(result[:data][:key]).to eq("max_lines_per_commit")
        expect(result[:data][:value]).to eq("300")
      end
    end

    context "with invalid category" do
      it "returns error" do
        result = macros.execute("/update invalid key=value")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Only 'guard' updates supported")
      end
    end

    context "without key=value format" do
      it "returns error" do
        result = macros.execute("/update guard invalid")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Invalid format")
      end
    end

    context "without arguments" do
      it "returns error" do
        result = macros.execute("/update")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage:")
      end
    end
  end

  describe "/reload command" do
    context "with config category" do
      it "requests config reload" do
        result = macros.execute("/reload config")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:reload_config)
      end
    end

    context "with invalid category" do
      it "returns error" do
        result = macros.execute("/reload invalid")
        expect(result[:success]).to be false
      end
    end

    context "without category" do
      it "returns error" do
        result = macros.execute("/reload")
        expect(result[:success]).to be false
      end
    end
  end

  describe "/rollback command" do
    context "with valid count" do
      it "requests rollback of n commits" do
        result = macros.execute("/rollback 3")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:rollback_commits)
        expect(result[:data][:count]).to eq(3)
      end
    end

    context "with count of 1" do
      it "rolls back one commit" do
        result = macros.execute("/rollback 1")
        expect(result[:data][:count]).to eq(1)
      end
    end

    context "with invalid count" do
      it "returns error for zero" do
        result = macros.execute("/rollback 0")
        expect(result[:success]).to be false
      end

      it "returns error for negative" do
        result = macros.execute("/rollback -1")
        expect(result[:success]).to be false
      end

      it "returns error for non-numeric" do
        result = macros.execute("/rollback abc")
        expect(result[:success]).to be false
      end
    end

    context "without count" do
      it "returns error" do
        result = macros.execute("/rollback")
        expect(result[:success]).to be false
      end
    end
  end

  describe "/undo command" do
    context "with 'last' argument" do
      it "rolls back one commit" do
        result = macros.execute("/undo last")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:rollback_commits)
        expect(result[:data][:count]).to eq(1)
      end
    end

    context "without 'last' argument" do
      it "returns error" do
        result = macros.execute("/undo")
        expect(result[:success]).to be false
      end
    end

    context "with wrong argument" do
      it "returns error" do
        result = macros.execute("/undo first")
        expect(result[:success]).to be false
      end
    end
  end

  describe "help system" do
    it "includes new commands in help" do
      result = macros.execute("/help")
      expect(result[:message]).to include("/pause")
      expect(result[:message]).to include("/resume")
      expect(result[:message]).to include("/cancel")
      expect(result[:message]).to include("/inject")
      expect(result[:message]).to include("/merge")
      expect(result[:message]).to include("/update")
      expect(result[:message]).to include("/reload")
      expect(result[:message]).to include("/rollback")
      expect(result[:message]).to include("/undo")
    end

    it "provides detailed help for specific commands" do
      result = macros.execute("/help /inject")
      expect(result[:message]).to include("Usage:")
      expect(result[:message]).to include("--priority")
    end
  end

  describe "command list" do
    it "includes all interactive commands" do
      commands = macros.list_commands
      expect(commands).to include("/pause")
      expect(commands).to include("/resume")
      expect(commands).to include("/cancel")
      expect(commands).to include("/inject")
      expect(commands).to include("/merge")
      expect(commands).to include("/update")
      expect(commands).to include("/reload")
      expect(commands).to include("/rollback")
      expect(commands).to include("/undo")
    end
  end
end
