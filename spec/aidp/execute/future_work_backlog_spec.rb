# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/future_work_backlog"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Execute::FutureWorkBacklog do
  let(:temp_dir) { Dir.mktmpdir }
  let(:backlog) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates backlog directory" do
      # Create a new backlog instance to trigger directory creation
      described_class.new(temp_dir)
      expect(Dir.exist?(File.join(temp_dir, ".aidp"))).to be true
    end

    it "starts with empty entries" do
      expect(backlog.entries).to be_empty
    end

    it "loads existing backlog if present" do
      # Create existing backlog
      FileUtils.mkdir_p(File.join(temp_dir, ".aidp"))
      existing_data = {
        "version" => "1.0",
        "entries" => [
          {
            "id" => "fw-123-abc",
            "type" => "style_violation",
            "file" => "lib/test.rb",
            "lines" => "10-20",
            "reason" => "Test reason",
            "recommendation" => "Test recommendation",
            "priority" => "medium"
          }
        ]
      }
      File.write(File.join(temp_dir, ".aidp/future_work.yml"), YAML.dump(existing_data))

      new_backlog = described_class.new(temp_dir)
      expect(new_backlog.entries.size).to eq(1)
      expect(new_backlog.entries.first[:id]).to eq("fw-123-abc")
    end
  end

  describe "#add_entry" do
    let(:entry_data) do
      {
        type: :style_violation,
        file: "lib/user.rb",
        lines: 10,
        reason: "Method too long",
        recommendation: "Extract into smaller methods",
        priority: :high
      }
    end

    it "adds entry to backlog" do
      expect {
        backlog.add_entry(entry_data)
      }.to change { backlog.entries.size }.by(1)
    end

    it "assigns unique ID to entry" do
      entry = backlog.add_entry(entry_data)
      expect(entry[:id]).to match(/^fw-\d+-[a-f0-9]+$/)
    end

    it "adds timestamp to entry" do
      entry = backlog.add_entry(entry_data)
      expect(entry[:created_at]).to match(/^\d{4}-\d{2}-\d{2}T/)
    end

    it "includes current context" do
      backlog.set_context(work_loop: "test_loop", step: "implementation")
      entry = backlog.add_entry(entry_data)
      expect(entry[:context][:work_loop]).to eq("test_loop")
      expect(entry[:context][:step]).to eq("implementation")
    end

    it "prevents duplicate entries" do
      backlog.add_entry(entry_data)
      expect {
        backlog.add_entry(entry_data)
      }.not_to change { backlog.entries.size }
    end

    it "normalizes line numbers" do
      entry = backlog.add_entry(entry_data.merge(lines: 10..20))
      expect(entry[:lines]).to eq("10-20")
    end

    it "normalizes file paths" do
      entry = backlog.add_entry(entry_data.merge(file: "lib/user.rb"))
      # Path normalization keeps relative paths as-is
      expect(entry[:file]).to eq("lib/user.rb")
    end

    it "sets default values for missing fields" do
      minimal_entry = backlog.add_entry(file: "test.rb")
      expect(minimal_entry[:type]).to eq(:technical_debt)
      expect(minimal_entry[:priority]).to eq(:medium)
      expect(minimal_entry[:reason]).to eq("No reason provided")
    end
  end

  describe "#set_context and #clear_context" do
    it "sets context for subsequent entries" do
      backlog.set_context(work_loop: "auth_feature", step: "implementation")
      expect(backlog.current_context[:work_loop]).to eq("auth_feature")
    end

    it "merges new context with existing" do
      backlog.set_context(work_loop: "auth_feature")
      backlog.set_context(step: "implementation")
      expect(backlog.current_context).to include(work_loop: "auth_feature", step: "implementation")
    end

    it "clears context" do
      backlog.set_context(work_loop: "test")
      backlog.clear_context
      expect(backlog.current_context).to be_empty
    end
  end

  describe "#save" do
    let(:entry_data) do
      {
        type: :refactor_opportunity,
        file: "lib/service.rb",
        lines: "100-150",
        reason: "Complex method",
        recommendation: "Simplify logic",
        priority: :medium
      }
    end

    before do
      backlog.add_entry(entry_data)
      backlog.save
    end

    it "saves YAML file" do
      yaml_file = File.join(temp_dir, ".aidp/future_work.yml")
      expect(File.exist?(yaml_file)).to be true
    end

    it "saves Markdown file" do
      md_file = File.join(temp_dir, ".aidp/future_work.md")
      expect(File.exist?(md_file)).to be true
    end

    it "YAML contains entry data" do
      yaml_file = File.join(temp_dir, ".aidp/future_work.yml")
      data = YAML.load_file(yaml_file)
      expect(data["entries"]).to be_an(Array)
      expect(data["entries"].first["file"]).to eq("lib/service.rb")
    end

    it "Markdown is human-readable" do
      md_file = File.join(temp_dir, ".aidp/future_work.md")
      content = File.read(md_file)
      expect(content).to include("Future Work Backlog")
      expect(content).to include("lib/service.rb")
      expect(content).to include("Complex method")
    end
  end

  describe "#filter" do
    before do
      backlog.add_entry(type: :style_violation, file: "lib/user.rb", lines: 10, reason: "Test1", recommendation: "Fix1", priority: :high)
      backlog.add_entry(type: :refactor_opportunity, file: "lib/user.rb", lines: 20, reason: "Test2", recommendation: "Fix2", priority: :medium)
      backlog.add_entry(type: :style_violation, file: "lib/service.rb", lines: 30, reason: "Test3", recommendation: "Fix3", priority: :high)
    end

    it "filters by type" do
      filtered = backlog.filter(type: :style_violation)
      expect(filtered.size).to eq(2)
      expect(filtered.all? { |e| e[:type] == :style_violation }).to be true
    end

    it "filters by file" do
      filtered = backlog.filter(file: "lib/user.rb")
      expect(filtered.size).to eq(2)
      expect(filtered.all? { |e| e[:file] == "lib/user.rb" }).to be true
    end

    it "filters by priority" do
      filtered = backlog.filter(priority: :high)
      expect(filtered.size).to eq(2)
      expect(filtered.all? { |e| e[:priority] == :high }).to be true
    end

    it "filters by work loop context" do
      backlog.set_context(work_loop: "feature_a")
      backlog.add_entry(type: :todo, file: "test.rb", lines: 1, reason: "Test", recommendation: "Fix")

      filtered = backlog.filter(work_loop: "feature_a")
      expect(filtered.size).to eq(1)
    end
  end

  describe "#by_type" do
    before do
      backlog.add_entry(type: :style_violation, file: "test1.rb", lines: 1, reason: "R1", recommendation: "F1")
      backlog.add_entry(type: :style_violation, file: "test2.rb", lines: 2, reason: "R2", recommendation: "F2")
      backlog.add_entry(type: :refactor_opportunity, file: "test3.rb", lines: 3, reason: "R3", recommendation: "F3")
    end

    it "groups entries by type" do
      grouped = backlog.by_type
      expect(grouped[:style_violation].size).to eq(2)
      expect(grouped[:refactor_opportunity].size).to eq(1)
    end
  end

  describe "#by_file" do
    before do
      backlog.add_entry(type: :style_violation, file: "lib/user.rb", lines: 1, reason: "R1", recommendation: "F1")
      backlog.add_entry(type: :refactor_opportunity, file: "lib/user.rb", lines: 2, reason: "R2", recommendation: "F2")
      backlog.add_entry(type: :todo, file: "lib/service.rb", lines: 3, reason: "R3", recommendation: "F3")
    end

    it "groups entries by file" do
      grouped = backlog.by_file
      expect(grouped["lib/user.rb"].size).to eq(2)
      expect(grouped["lib/service.rb"].size).to eq(1)
    end
  end

  describe "#by_priority" do
    before do
      backlog.add_entry(type: :style_violation, file: "test.rb", lines: 1, reason: "R1", recommendation: "F1", priority: :high)
      backlog.add_entry(type: :refactor_opportunity, file: "test.rb", lines: 2, reason: "R2", recommendation: "F2", priority: :critical)
      backlog.add_entry(type: :todo, file: "test.rb", lines: 3, reason: "R3", recommendation: "F3", priority: :low)
    end

    it "groups entries by priority" do
      grouped = backlog.by_priority
      expect(grouped[:high].size).to eq(1)
      expect(grouped[:critical].size).to eq(1)
      expect(grouped[:low].size).to eq(1)
    end

    it "sorts by priority descending" do
      grouped = backlog.by_priority
      priorities = grouped.keys
      expect(priorities.first).to eq(:critical)
      expect(priorities.last).to eq(:low)
    end
  end

  describe "#summary" do
    before do
      backlog.add_entry(type: :style_violation, file: "lib/user.rb", lines: 1, reason: "R1", recommendation: "F1", priority: :high)
      backlog.add_entry(type: :style_violation, file: "lib/service.rb", lines: 2, reason: "R2", recommendation: "F2", priority: :medium)
      backlog.add_entry(type: :refactor_opportunity, file: "lib/user.rb", lines: 3, reason: "R3", recommendation: "F3", priority: :high)
    end

    it "returns total count" do
      expect(backlog.summary[:total]).to eq(3)
    end

    it "returns counts by type" do
      expect(backlog.summary[:by_type][:style_violation]).to eq(2)
      expect(backlog.summary[:by_type][:refactor_opportunity]).to eq(1)
    end

    it "returns counts by priority" do
      expect(backlog.summary[:by_priority][:high]).to eq(2)
      expect(backlog.summary[:by_priority][:medium]).to eq(1)
    end

    it "returns affected files count" do
      expect(backlog.summary[:files_affected]).to eq(2)
    end
  end

  describe "#resolve_entry" do
    let(:entry) do
      backlog.add_entry(type: :style_violation, file: "test.rb", lines: 1, reason: "Test", recommendation: "Fix")
    end

    it "marks entry as resolved" do
      backlog.resolve_entry(entry[:id])
      resolved_entry = backlog.entries.find { |e| e[:id] == entry[:id] }
      expect(resolved_entry[:resolved]).to be true
    end

    it "adds resolution timestamp" do
      backlog.resolve_entry(entry[:id])
      resolved_entry = backlog.entries.find { |e| e[:id] == entry[:id] }
      expect(resolved_entry[:resolved_at]).to match(/^\d{4}-\d{2}-\d{2}T/)
    end

    it "adds resolution note" do
      backlog.resolve_entry(entry[:id], "Fixed in PR #123")
      resolved_entry = backlog.entries.find { |e| e[:id] == entry[:id] }
      expect(resolved_entry[:resolution_note]).to eq("Fixed in PR #123")
    end

    it "does nothing for unknown entry ID" do
      expect {
        backlog.resolve_entry("unknown-id")
      }.not_to raise_error
    end
  end

  describe "#clear_resolved" do
    before do
      entry1 = backlog.add_entry(type: :style_violation, file: "test1.rb", lines: 1, reason: "R1", recommendation: "F1")
      backlog.add_entry(type: :refactor_opportunity, file: "test2.rb", lines: 2, reason: "R2", recommendation: "F2")
      backlog.resolve_entry(entry1[:id])
    end

    it "removes resolved entries" do
      expect {
        backlog.clear_resolved
      }.to change { backlog.entries.size }.from(2).to(1)
    end

    it "keeps unresolved entries" do
      backlog.clear_resolved
      expect(backlog.entries.first[:resolved]).to be_falsey
    end
  end

  describe "#entry_to_prompt" do
    let(:entry) do
      backlog.set_context(work_loop: "test_loop", step: "implementation")
      backlog.add_entry(
        type: :refactor_opportunity,
        file: "lib/complex_service.rb",
        lines: "50-100",
        reason: "Method is too complex and violates single responsibility",
        recommendation: "Extract payment logic into separate class",
        priority: :high
      )
    end

    it "generates PROMPT.md content" do
      prompt = backlog.entry_to_prompt(entry[:id])
      expect(prompt).to be_a(String)
      expect(prompt).to include("Work Loop:")
      expect(prompt).to include("lib/complex_service.rb")
    end

    it "includes file and line information" do
      prompt = backlog.entry_to_prompt(entry[:id])
      expect(prompt).to include("**File**: lib/complex_service.rb")
      expect(prompt).to include("**Lines**: 50-100")
    end

    it "includes issue and recommendation" do
      prompt = backlog.entry_to_prompt(entry[:id])
      expect(prompt).to include("Method is too complex")
      expect(prompt).to include("Extract payment logic")
    end

    it "includes acceptance criteria" do
      prompt = backlog.entry_to_prompt(entry[:id])
      expect(prompt).to include("Acceptance Criteria")
      expect(prompt).to include("Tests pass")
    end

    it "includes completion marker" do
      prompt = backlog.entry_to_prompt(entry[:id])
      expect(prompt).to include("STATUS: COMPLETE")
    end

    it "returns nil for unknown entry ID" do
      prompt = backlog.entry_to_prompt("unknown-id")
      expect(prompt).to be_nil
    end
  end

  describe "#display_summary" do
    let(:output) { StringIO.new }

    context "with entries" do
      before do
        backlog.add_entry(type: :style_violation, file: "test1.rb", lines: 1, reason: "R1", recommendation: "F1", priority: :high)
        backlog.add_entry(type: :refactor_opportunity, file: "test2.rb", lines: 2, reason: "R2", recommendation: "F2", priority: :medium)
      end

      it "displays summary header" do
        backlog.display_summary(output)
        expect(output.string).to include("Future Work Backlog Summary")
      end

      it "displays total items" do
        backlog.display_summary(output)
        expect(output.string).to include("Total Items: 2")
      end

      it "displays by type" do
        backlog.display_summary(output)
        expect(output.string).to include("By Type:")
        expect(output.string).to include("Style Violation")
      end

      it "displays by priority" do
        backlog.display_summary(output)
        expect(output.string).to include("By Priority:")
        expect(output.string).to include("HIGH:")
      end

      it "displays usage instructions" do
        backlog.display_summary(output)
        expect(output.string).to include("Review backlog:")
        expect(output.string).to include("Convert to work loop:")
      end
    end

    context "with no entries" do
      it "does not display anything" do
        backlog.display_summary(output)
        expect(output.string).to be_empty
      end
    end
  end

  describe "entry types" do
    it "supports all defined entry types" do
      described_class::ENTRY_TYPES.each_with_index do |(type, _name), idx|
        entry = backlog.add_entry(type: type, file: "test#{idx}.rb", lines: idx + 1, reason: "Test #{idx}", recommendation: "Fix #{idx}")
        expect(entry[:type]).to eq(type)
      end
    end
  end

  describe "priority levels" do
    it "supports all defined priority levels" do
      described_class::PRIORITIES.each_with_index do |(priority, _value), idx|
        entry = backlog.add_entry(type: :todo, file: "test#{idx}.rb", lines: idx + 1, reason: "Test #{idx}", recommendation: "Fix #{idx}", priority: priority)
        expect(entry[:priority]).to eq(priority)
      end
    end
  end

  describe "integration scenarios" do
    it "handles complete workflow" do
      # Set context for work loop
      backlog.set_context(work_loop: "user_authentication", step: "implementation")

      # Add various entries during implementation
      backlog.add_entry(
        type: :style_violation,
        file: "lib/user.rb",
        lines: "45-60",
        reason: "Method exceeds 15 lines",
        recommendation: "Extract validation logic",
        priority: :medium
      )

      backlog.add_entry(
        type: :refactor_opportunity,
        file: "lib/auth_service.rb",
        lines: 120,
        reason: "Duplicated error handling code",
        recommendation: "Create shared error handler module",
        priority: :low
      )

      backlog.add_entry(
        type: :technical_debt,
        file: "lib/session.rb",
        lines: "30-40",
        reason: "Uses deprecated session storage",
        recommendation: "Migrate to new session system",
        priority: :high
      )

      # Save backlog
      backlog.save

      # Verify files created
      expect(File.exist?(File.join(temp_dir, ".aidp/future_work.yml"))).to be true
      expect(File.exist?(File.join(temp_dir, ".aidp/future_work.md"))).to be true

      # Verify summary
      summary = backlog.summary
      expect(summary[:total]).to eq(3)
      expect(summary[:files_affected]).to eq(3)

      # Filter by priority
      high_priority = backlog.filter(priority: :high)
      expect(high_priority.size).to eq(1)
      expect(high_priority.first[:file]).to eq("lib/session.rb")

      # Convert entry to work loop
      entry = backlog.entries.first
      prompt = backlog.entry_to_prompt(entry[:id])
      expect(prompt).to include("Work Loop:")
      expect(prompt).to include(entry[:file])
    end
  end
end
