# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/prompt_optimization/source_code_fragmenter"

RSpec.describe Aidp::PromptOptimization::SourceCodeFragmenter do
  let(:temp_dir) { Dir.mktmpdir }
  let(:fragmenter) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with project directory" do
      expect(fragmenter.project_dir).to eq(temp_dir)
    end
  end

  describe "#fragment_file" do
    context "when file does not exist" do
      it "returns empty array" do
        result = fragmenter.fragment_file("nonexistent.rb")
        expect(result).to eq([])
      end
    end

    context "when file is not Ruby" do
      it "returns empty array" do
        File.write(File.join(temp_dir, "test.txt"), "not ruby")
        result = fragmenter.fragment_file("test.txt")
        expect(result).to eq([])
      end
    end

    context "with simple Ruby file" do
      before do
        File.write(File.join(temp_dir, "simple.rb"), sample_simple_file)
      end

      it "fragments the file" do
        fragments = fragmenter.fragment_file("simple.rb")
        expect(fragments).not_to be_empty
      end

      it "creates CodeFragment objects" do
        fragments = fragmenter.fragment_file("simple.rb")
        expect(fragments.first).to be_a(Aidp::PromptOptimization::CodeFragment)
      end

      it "extracts requires fragment" do
        fragments = fragmenter.fragment_file("simple.rb")
        requires_fragment = fragments.find { |f| f.type == :requires }

        expect(requires_fragment).not_to be_nil
        expect(requires_fragment.content).to include("require")
      end

      it "extracts class fragment" do
        fragments = fragmenter.fragment_file("simple.rb")
        class_fragment = fragments.find { |f| f.type == :class }

        expect(class_fragment).not_to be_nil
        expect(class_fragment.name).to eq("User")
      end
    end

    context "with complex Ruby file" do
      before do
        File.write(File.join(temp_dir, "complex.rb"), sample_complex_file)
      end

      it "extracts multiple classes" do
        fragments = fragmenter.fragment_file("complex.rb")
        class_fragments = fragments.select { |f| f.type == :class }

        expect(class_fragments.count).to be >= 2
      end

      it "extracts top-level methods" do
        fragments = fragmenter.fragment_file("complex.rb")
        method_fragments = fragments.select { |f| f.type == :method }

        expect(method_fragments).not_to be_empty
      end

      it "sets correct line numbers" do
        fragments = fragmenter.fragment_file("complex.rb")
        fragments.each do |fragment|
          expect(fragment.line_start).to be > 0
          expect(fragment.line_end).to be >= fragment.line_start
        end
      end
    end
  end

  describe "#fragment_files" do
    before do
      File.write(File.join(temp_dir, "file1.rb"), sample_simple_file)
      File.write(File.join(temp_dir, "file2.rb"), sample_simple_file)
    end

    it "fragments multiple files" do
      fragments = fragmenter.fragment_files(["file1.rb", "file2.rb"])
      expect(fragments.count).to be >= 4 # At least 2 fragments per file
    end

    it "handles mixed existing and non-existing files" do
      fragments = fragmenter.fragment_files(["file1.rb", "nonexistent.rb"])
      expect(fragments).not_to be_empty
    end
  end

  describe "private methods" do
    describe "#extract_requires" do
      it "extracts require statements" do
        content = "require 'foo'\nrequire_relative 'bar'\nclass Test; end"
        requires = fragmenter.send(:extract_requires, content)

        expect(requires).to include("require 'foo'")
        expect(requires).to include("require_relative 'bar'")
      end

      it "returns nil when no requires" do
        content = "class Test; end"
        requires = fragmenter.send(:extract_requires, content)

        expect(requires).to be_nil
      end
    end
  end

  def sample_simple_file
    <<~RUBY
      # frozen_string_literal: true

      require "active_record"

      class User
        attr_reader :name, :email

        def initialize(name, email)
          @name = name
          @email = email
        end

        def valid?
          !name.empty? && email.include?("@")
        end
      end
    RUBY
  end

  def sample_complex_file
    <<~RUBY
      # frozen_string_literal: true

      require "active_record"
      require_relative "concerns/authenticatable"

      module Models
        class User < ApplicationRecord
          include Authenticatable

          def full_name
            "\#{first_name} \#{last_name}"
          end
        end

        class Admin < User
          def permissions
            [:read, :write, :delete]
          end
        end
      end

      def helper_method(arg)
        arg.to_s.upcase
      end
    RUBY
  end
end

RSpec.describe Aidp::PromptOptimization::CodeFragment do
  let(:fragment) do
    described_class.new(
      id: "lib/user.rb:User",
      file_path: "/project/lib/user.rb",
      type: :class,
      name: "User",
      content: "class User\n  def initialize\n  end\nend\n",
      line_start: 5,
      line_end: 8
    )
  end

  describe "#initialize" do
    it "initializes with all attributes" do
      expect(fragment.id).to eq("lib/user.rb:User")
      expect(fragment.file_path).to eq("/project/lib/user.rb")
      expect(fragment.type).to eq(:class)
      expect(fragment.name).to eq("User")
      expect(fragment.content).to include("class User")
      expect(fragment.line_start).to eq(5)
      expect(fragment.line_end).to eq(8)
    end
  end

  describe "#size" do
    it "returns character count" do
      expect(fragment.size).to eq(fragment.content.length)
    end
  end

  describe "#estimated_tokens" do
    it "estimates tokens from character count" do
      expected = (fragment.content.length / 4.0).ceil
      expect(fragment.estimated_tokens).to eq(expected)
    end

    it "returns positive integer" do
      expect(fragment.estimated_tokens).to be > 0
    end
  end

  describe "#line_count" do
    it "calculates line count from line range" do
      expect(fragment.line_count).to eq(4) # lines 5-8
    end
  end

  describe "#relative_path" do
    it "returns path relative to project dir" do
      result = fragment.relative_path("/project")
      expect(result).to eq("lib/user.rb")
    end

    it "handles trailing slash" do
      result = fragment.relative_path("/project/")
      expect(result).to eq("lib/user.rb")
    end
  end

  describe "#test_file?" do
    it "returns false for regular files" do
      expect(fragment.test_file?).to be false
    end

    it "returns true for spec files" do
      spec_fragment = described_class.new(
        id: "spec/user_spec.rb:User",
        file_path: "/project/spec/user_spec.rb",
        type: :class,
        name: "User",
        content: "describe User do\nend",
        line_start: 1,
        line_end: 2
      )

      expect(spec_fragment.test_file?).to be true
    end

    it "returns true for test files" do
      test_fragment = described_class.new(
        id: "test/user_test.rb:User",
        file_path: "/project/test/user_test.rb",
        type: :class,
        name: "User",
        content: "class UserTest\nend",
        line_start: 1,
        line_end: 2
      )

      expect(test_fragment.test_file?).to be true
    end
  end

  describe "#summary" do
    it "returns hash with all key information" do
      summary = fragment.summary

      expect(summary).to be_a(Hash)
      expect(summary[:id]).to eq("lib/user.rb:User")
      expect(summary[:file_path]).to eq("/project/lib/user.rb")
      expect(summary[:type]).to eq(:class)
      expect(summary[:name]).to eq("User")
      expect(summary[:lines]).to eq("5-8")
      expect(summary[:line_count]).to eq(4)
      expect(summary[:size]).to be_a(Integer)
      expect(summary[:estimated_tokens]).to be_a(Integer)
      expect(summary[:test_file]).to be false
    end
  end

  describe "#to_s" do
    it "returns readable string representation" do
      expect(fragment.to_s).to eq("CodeFragment<class:User>")
    end
  end

  describe "#inspect" do
    it "returns detailed inspection string" do
      inspection = fragment.inspect
      expect(inspection).to include("lib/user.rb:User")
      expect(inspection).to include("class")
      expect(inspection).to include("5-8")
    end
  end
end
