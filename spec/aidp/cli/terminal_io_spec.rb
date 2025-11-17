# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/terminal_io"
require "stringio"

describe Aidp::CLI::TerminalIO do
  let(:output) { StringIO.new }

  describe "#ready?" do
    it "returns true for a StringIO" do
      io = described_class.new(input: StringIO.new("hi"), output: output)
      expect(io.ready?).to be(true)
    end

    it "returns false when input is closed" do
      s = StringIO.new("data")
      s.close
      io = described_class.new(input: s, output: output)
      expect(io.ready?).to be(false)
    end

    it "returns true for a non-StringIO input" do
      fake_input = Class.new do
        def closed?
          false
        end
      end.new
      io = described_class.new(input: fake_input, output: output)
      expect(io.ready?).to be(true)
    end
  end

  describe "#getch" do
    it "returns nil when not ready" do
      s = StringIO.new("x")
      s.close
      io = described_class.new(input: s, output: output)
      expect(io.getch).to be_nil
    end

    it "returns a single character for StringIO input" do
      s = StringIO.new("abc")
      io = described_class.new(input: s, output: output)
      expect(io.getch).to eq("a")
      expect(io.getch).to eq("b")
      expect(io.getch).to eq("c")
    end

    it "returns empty string at EOF for StringIO" do
      s = StringIO.new("")
      io = described_class.new(input: s, output: output)
      expect(io.getch).to eq("")
    end

    it "delegates to underlying getch for non-StringIO input" do
      fake_input = Class.new do
        attr_reader :calls
        def initialize
          @calls = 0
        end

        def closed?
          false
        end

        def getch
          @calls += 1
          "Z"
        end
      end.new
      io = described_class.new(input: fake_input, output: output)
      expect(io.getch).to eq("Z")
      expect(fake_input.calls).to eq(1)
    end
  end

  describe "#gets" do
    it "returns full line including newline" do
      s = StringIO.new("line1\nline2\n")
      io = described_class.new(input: s, output: output)
      expect(io.gets).to eq("line1\n")
      expect(io.gets).to eq("line2\n")
      expect(io.gets).to be_nil
    end
  end

  describe "#readline" do
    it "prints prompt and returns chomped line for StringIO" do
      s = StringIO.new("value\n")
      io = described_class.new(input: s, output: output)
      result = io.readline("Enter: ")
      expect(result).to eq("value")
      expect(output.string).to start_with("Enter: ")
    end

    it "returns default when StringIO has no data" do
      s = StringIO.new("")
      io = described_class.new(input: s, output: output)
      result = io.readline("Prompt: ", default: "fallback")
      expect(result).to eq("fallback")
    end

    context "with TTY::Reader" do
      it "delegates to TTY::Reader and chomps" do
        fake_input = Class.new do
          def closed?
            false
          end
        end.new
        reader_double = instance_double(TTY::Reader)
        expect(TTY::Reader).to receive(:new).with(input: fake_input, output: output, interrupt: :exit).and_return(reader_double)
        expect(reader_double).to receive(:read_line).with("Prompt") { "result\n" }
        io = described_class.new(input: fake_input, output: output)
        expect(io.readline("Prompt")).to eq("result")
      end

      it "raises Interrupt when TTY::Reader signals input interrupt" do
        fake_input = Class.new do
          def closed?
            false
          end
        end.new
        reader_double = instance_double(TTY::Reader)
        expect(TTY::Reader).to receive(:new).and_return(reader_double)
        expect(reader_double).to receive(:read_line).with("Prompt").and_raise(TTY::Reader::InputInterrupt)
        io = described_class.new(input: fake_input, output: output)
        expect { io.readline("Prompt") }.to raise_error(Interrupt)
      end
    end
  end

  describe "output helpers" do
    it "#write writes raw string" do
      io = described_class.new(input: StringIO.new(""), output: output)
      io.write("abc")
      expect(output.string).to eq("abc")
    end

    it "#print appends without newline" do
      io = described_class.new(input: StringIO.new(""), output: output)
      io.print("one")
      io.print("two")
      expect(output.string).to eq("onetwo")
    end

    it "#puts appends with newline" do
      io = described_class.new(input: StringIO.new(""), output: output)
      io.puts("line")
      expect(output.string).to eq("line\n")
    end

    it "#puts with no args writes newline" do
      io = described_class.new(input: StringIO.new(""), output: output)
      io.puts
      expect(output.string).to eq("\n")
    end

    it "#flush flushes output (no error)" do
      io = described_class.new(input: StringIO.new(""), output: output)
      io.print("x")
      expect { io.flush }.not_to raise_error
    end
  end
end
