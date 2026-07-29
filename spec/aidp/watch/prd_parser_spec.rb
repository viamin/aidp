# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::PrdParser do
  let(:tmp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#parse" do
    it "parses Mermaid gantt tasks with dependencies and issue mappings" do
      file = File.join(tmp_dir, "GANTT.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            title Project Timeline
            dateFormat YYYY-MM-DD
            section Planning
            Define scope (#101) :task1, 2026-07-01, 2d
            Build sync (#102) :crit, task2, after task1, 3d
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse

      expect(result[:format]).to eq(:mermaid)
      expect(result[:tasks].map { |task| task[:issue_number] }).to eq([101, 102])
      expect(result[:tasks].last[:dependency_ids]).to eq(["task1"])
      expect(result[:tasks].last[:critical]).to be true
    end

    it "infers dependent Mermaid task dates from predecessor end dates" do
      file = File.join(tmp_dir, "dependent_gantt.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            title Project Timeline
            dateFormat YYYY-MM-DD
            section Planning
            Define scope (#101) :task1, 2026-07-01, 2d
            Build sync (#102) :task2, after task1, 3d
            Ship follow-up (#103) :task3, after task2, 1d
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse
      tasks = result[:tasks].each_with_object({}) do |task, memo|
        memo[task[:id]] = task
      end

      expect(tasks["task2"][:start_date]).to eq(Date.new(2026, 7, 3))
      expect(tasks["task2"][:end_date]).to eq(Date.new(2026, 7, 5))
      expect(tasks["task3"][:start_date]).to eq(Date.new(2026, 7, 6))
      expect(tasks["task3"][:end_date]).to eq(Date.new(2026, 7, 6))
    end

    it "parses Mermaid tasks with multiple predecessors" do
      file = File.join(tmp_dir, "multiple_dependencies_gantt.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            title Project Timeline
            dateFormat YYYY-MM-DD
            section Planning
            Define scope :task1, 2026-07-01, 2d
            Build sync :task2, 2026-07-01, 3d
            Ship follow-up :task3, after task1 task2, 2d
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse
      tasks = result[:tasks].each_with_object({}) do |task, memo|
        memo[task[:id]] = task
      end

      expect(tasks["task3"][:dependency_ids]).to eq(%w[task1 task2])
      expect(tasks["task3"][:start_date]).to eq(Date.new(2026, 7, 4))
      expect(tasks["task3"][:end_date]).to eq(Date.new(2026, 7, 5))
    end

    it "parses Mermaid tasks without whitespace before metadata colons" do
      file = File.join(tmp_dir, "compact_mermaid_gantt.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            title Project Timeline
            dateFormat YYYY-MM-DD
            section Planning
            Task A:a1, 2026-07-01, 2d
            Task B:b1, after a1, 1d
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse
      tasks = result[:tasks].each_with_object({}) do |task, memo|
        memo[task[:id]] = task
      end

      expect(tasks.keys).to contain_exactly("a1", "b1")
      expect(tasks["b1"][:dependency_ids]).to eq(["a1"])
      expect(tasks["b1"][:start_date]).to eq(Date.new(2026, 7, 3))
      expect(tasks["b1"][:end_date]).to eq(Date.new(2026, 7, 3))
    end

    it "parses the Mermaid gantt block when earlier Mermaid blocks use a different diagram type" do
      file = File.join(tmp_dir, "multiple_mermaid_blocks.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        flowchart TD
            A[Start] --> B[Finish]
        ```

        ```mermaid
        gantt
            section Planning
            Task A :a1, 2026-07-01, 2d
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse

      expect(result[:format]).to eq(:mermaid)
      expect(result[:tasks].map { |task| task[:id] }).to eq(["a1"])
    end

    it "rejects markdown files that do not contain a Mermaid gantt chart" do
      file = File.join(tmp_dir, "product_requirements.md")
      File.write(file, <<~MARKDOWN)
        # PRD

        Goals:
        - Expose metrics: count, status
      MARKDOWN

      expect {
        described_class.new(file_path: file).parse
      }.to raise_error(described_class::ParseError, /Unable to detect Gantt format/)
    end

    it "detects plain Mermaid gantt files by their gantt marker" do
      file = File.join(tmp_dir, "timeline.mmd")
      File.write(file, <<~MERMAID)
        gantt
            section Planning
            Task A :a1, 2026-07-01, 2d
      MERMAID

      result = described_class.new(file_path: file).parse

      expect(result[:format]).to eq(:mermaid)
      expect(result[:tasks].first[:id]).to eq("a1")
    end

    it "parses Mermaid tasks with explicit start and end dates" do
      file = File.join(tmp_dir, "explicit_end_date_gantt.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            title Project Timeline
            dateFormat YYYY-MM-DD
            section Planning
            Task A :a1, 2026-07-01, 2026-07-03
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse
      task = result[:tasks].first

      expect(task[:start_date]).to eq(Date.new(2026, 7, 1))
      expect(task[:end_date]).to eq(Date.new(2026, 7, 3))
      expect(task[:duration_days]).to eq(3)
    end

    it "assigns sequential dates to Mermaid root tasks that only specify durations" do
      file = File.join(tmp_dir, "duration_only_gantt.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            section Planning
            Define scope :task1, 2d
            Build sync :task2, after task1, 3d
            Ship follow-up :task3, 1d
        ```
      MARKDOWN

      allow(Date).to receive(:today).and_return(Date.new(2026, 7, 29))

      result = described_class.new(file_path: file).parse
      tasks = result[:tasks].each_with_object({}) do |task, memo|
        memo[task[:id]] = task
      end

      expect(tasks["task1"][:start_date]).to eq(Date.new(2026, 7, 29))
      expect(tasks["task1"][:end_date]).to eq(Date.new(2026, 7, 30))
      expect(tasks["task2"][:start_date]).to eq(Date.new(2026, 7, 31))
      expect(tasks["task2"][:end_date]).to eq(Date.new(2026, 8, 2))
      expect(tasks["task3"][:start_date]).to eq(Date.new(2026, 7, 31))
      expect(tasks["task3"][:end_date]).to eq(Date.new(2026, 7, 31))
    end

    it "uses an explicit Mermaid start date comment when present" do
      file = File.join(tmp_dir, "comment_anchored_gantt.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            %% start_date: 2026-08-10
            section Planning
            Define scope :task1, 2d
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse

      expect(result[:tasks].first[:start_date]).to eq(Date.new(2026, 8, 10))
      expect(result[:tasks].first[:end_date]).to eq(Date.new(2026, 8, 11))
    end

    it "keeps undated Mermaid root tasks in chart order when later roots have earlier explicit dates" do
      file = File.join(tmp_dir, "chart_order_root_dates_gantt.md")
      File.write(file, <<~MARKDOWN)
        ```mermaid
        gantt
            %% start_date: 2026-07-01
            section Planning
            Alpha :a, 2026-07-10, 2d
            Beta :b, 2026-07-01, 1d
            Gamma :c, 1d
        ```
      MARKDOWN

      result = described_class.new(file_path: file).parse
      tasks = result[:tasks].each_with_object({}) do |task, memo|
        memo[task[:id]] = task
      end

      expect(tasks["a"][:start_date]).to eq(Date.new(2026, 7, 10))
      expect(tasks["b"][:start_date]).to eq(Date.new(2026, 7, 1))
      expect(tasks["c"][:start_date]).to eq(Date.new(2026, 7, 12))
      expect(tasks["c"][:end_date]).to eq(Date.new(2026, 7, 12))
    end

    it "parses Microsoft Project XML tasks" do
      file = File.join(tmp_dir, "project.xml")
      File.write(file, <<~XML)
        <Project>
          <Tasks>
            <Task>
              <UID>1</UID>
              <Name>Plan work (#201)</Name>
              <Start>2026-07-01T09:00:00</Start>
              <Finish>2026-07-02T09:00:00</Finish>
              <Duration>PT16H0M0S</Duration>
            </Task>
            <Task>
              <UID>2</UID>
              <Name>Ship work (#202)</Name>
              <Duration>PT24H0M0S</Duration>
              <PredecessorLink>
                <PredecessorUID>1</PredecessorUID>
              </PredecessorLink>
            </Task>
          </Tasks>
        </Project>
      XML

      result = described_class.new(file_path: file).parse

      expect(result[:format]).to eq(:ms_project_xml)
      expect(result[:tasks].last[:dependency_ids]).to eq(["1"])
      expect(result[:tasks].map { |task| task[:issue_number] }).to eq([201, 202])
    end

    it "parses CSV gantt exports" do
      file = File.join(tmp_dir, "project.csv")
      File.write(file, <<~CSV)
        task_id,name,start_date,duration_days,dependencies,issue_number,critical
        t1,Design (#301),2026-07-01,2,,301,false
        t2,Implement (#302),2026-07-03,4,t1,302,true
      CSV

      result = described_class.new(file_path: file).parse

      expect(result[:format]).to eq(:csv)
      expect(result[:tasks].last[:dependency_ids]).to eq(["t1"])
      expect(result[:tasks].last[:critical]).to be true
    end
  end
end
