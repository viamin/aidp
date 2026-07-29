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
