# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::PlanProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:plan_generator) do
    instance_double(Aidp::Watch::PlanGenerator, generate: {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: ["Any performance constraints?"]
    })
  end
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, plan_generator: plan_generator) }
  let(:issue) do
    {
      number: 42,
      title: "Add search",
      body: "Please add search capability.",
      url: "https://example.com",
      comments: []
    }
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it "posts plan comment and stores metadata" do
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    expect(repository_client).to receive(:post_comment).with(42, /AIDP Plan Proposal/)
    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-plan"],
      new_labels: ["aidp-needs-input"]
    )
    processor.process(issue)

    data = state_store.plan_data(42)
    expect(data["summary"]).to eq("Implement the requested feature")
    expect(data["tasks"]).to include("Add API endpoint")
    expect(data["questions"]).to include("Any performance constraints?")
  end

  it "skips processing when plan generation fails" do
    failed_plan_generator = instance_double(Aidp::Watch::PlanGenerator, generate: nil)
    failed_processor = described_class.new(repository_client: repository_client, state_store: state_store, plan_generator: failed_plan_generator)

    # Should not post comment or update labels when plan_data is nil
    expect(repository_client).not_to receive(:post_comment)
    expect(repository_client).not_to receive(:replace_labels)

    failed_processor.process(issue)

    # State should not be updated
    expect(state_store.plan_data(42)).to be_nil
  end

  it "updates existing plan when re-planning" do
    # First plan
    state_store.record_plan(42, summary: "Initial plan", tasks: ["Task 1"], questions: [], comment_body: "body1", comment_id: "comment-123")

    # Mock the update_comment call for re-planning
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    expect(repository_client).to receive(:update_comment).with("comment-123", /AIDP Plan Proposal/)
    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-plan"],
      new_labels: ["aidp-needs-input"]
    )

    processor.process(issue)

    # Verify iteration tracking
    data = state_store.plan_data(42)
    expect(state_store.plan_iteration_count(42)).to eq(2)
    expect(data["iteration"]).to eq(2)
  end

  it "archives previous plan content when updating" do
    # First plan
    state_store.record_plan(42, summary: "Old summary", tasks: ["Old task"], questions: [], comment_body: "body1", comment_id: "comment-123")

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:replace_labels)

    expect(repository_client).to receive(:update_comment) do |_id, body|
      # Verify archived content is present
      expect(body).to include("ARCHIVED_PLAN_START")
      expect(body).to include("Previous Plan (Iteration 1)")
      expect(body).to include("Old summary")
      expect(body).to include("Old task")
      expect(body).to include("ARCHIVED_PLAN_END")
    end

    processor.process(issue)
  end

  it "finds and updates comment when comment_id is missing" do
    # Plan exists but without comment_id
    state_store.record_plan(42, summary: "Old plan", tasks: [], questions: [], comment_body: "body1")

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:replace_labels)

    # Mock finding the comment
    expect(repository_client).to receive(:find_comment).with(42, "## 🤖 AIDP Plan Proposal").and_return({id: "found-123", body: "old body"})
    expect(repository_client).to receive(:update_comment).with("found-123", /AIDP Plan Proposal/)

    processor.process(issue)

    # Verify comment_id is now stored
    data = state_store.plan_data(42)
    expect(data["comment_id"]).to eq("found-123")
  end

  it "posts new comment when existing comment cannot be found" do
    # Plan exists but comment cannot be found
    state_store.record_plan(42, summary: "Old plan", tasks: [], questions: [], comment_body: "body1")

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:replace_labels)

    expect(repository_client).to receive(:find_comment).with(42, "## 🤖 AIDP Plan Proposal").and_return(nil)
    expect(repository_client).to receive(:post_comment).with(42, /AIDP Plan Proposal/)

    processor.process(issue)
  end

  it "creates project sub-issues when triggered by aidp-project" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator, create_sub_issues: [{number: 43, title: "API slice", dependencies: []}])

    allow(project_generator).to receive(:generate).with(issue, hierarchical: true).and_return(project_plan)
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-project", "aidp-plan", "aidp-build"],
      new_labels: ["aidp-blocked"]
    )
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    expect(repository_client).not_to receive(:create_project)
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(project_generator).to have_received(:generate).with(issue, hierarchical: true)
    expect(creator).to have_received(:create_sub_issues).with(issue, project_plan[:sub_issues])
  end

  it "syncs project data from the configured PRD Gantt chart during project setup" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator,
      project_config: {prd_path: ".aidp/docs/GANTT.md", gantt_format: "mermaid", auto_sync_gantt: true}
    )
    projects_processor = instance_double(
      Aidp::Watch::ProjectsProcessor,
      ensure_project_fields: true,
      sync_from_gantt: {synced: 1, skipped: 0, critical_path: ["task-1"]},
      sync_issue_to_project: true
    )
    creator = instance_double(
      Aidp::Watch::SubIssueCreator,
      create_sub_issues: [{number: 43, title: "API slice", dependencies: []}]
    )

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(projects_processor).to have_received(:sync_from_gantt).with(
      issue_numbers_by_title: {"api slice" => 43}
    )
  end

  it "does not sync PRD gantt data during project setup when auto-sync is disabled" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator,
      project_config: {prd_path: ".aidp/docs/GANTT.md", gantt_format: "mermaid", auto_sync_gantt: false}
    )
    projects_processor = instance_double(
      Aidp::Watch::ProjectsProcessor,
      ensure_project_fields: true,
      sync_from_gantt: {synced: 0, skipped: 0, critical_path: []},
      sync_issue_to_project: true
    )
    creator = instance_double(Aidp::Watch::SubIssueCreator, create_sub_issues: [{number: 43, dependencies: []}])

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(projects_processor).not_to have_received(:sync_from_gantt)
  end

  it "moves project issues to needs-input when project resolution fails" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:find_active_project).and_raise(StandardError, "project lookup failed")

    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-project", "aidp-plan", "aidp-build"],
      new_labels: ["aidp-needs-input"]
    )

    project_processor.process(issue, trigger_label: "aidp-project")

    project_sync = state_store.project_sync_data(42)
    expect(project_sync["setup_status"]).to eq("failed")
    expect(project_sync["setup_error"]).to eq("unable to resolve a GitHub Project")
    expect(project_sync["setup_failed_at"]).not_to be_nil
  end

  it "moves project issues to needs-input when no sub-issues are created" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator, create_sub_issues: [])

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-project", "aidp-plan", "aidp-build"],
      new_labels: ["aidp-needs-input"]
    )

    project_processor.process(issue, trigger_label: "aidp-project")

    project_sync = state_store.project_sync_data(42)
    expect(project_sync["setup_status"]).to eq("failed")
    expect(project_sync["setup_error"]).to eq("unable to create project sub-issues")
  end

  it "reconciles tracked sub-issues against the regenerated plan when aidp-project is re-applied" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [
        {title: "Backend slice", tasks: ["Ship API"], dependencies: []},
        {title: "Frontend slice", tasks: ["Ship UI"], dependencies: ["Backend slice"]}
      ]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator)

    state_store.record_sub_issues(42, [43, 44])
    state_store.record_issue_dependencies(43, [])
    state_store.record_issue_dependencies(44, [])

    allow(project_generator).to receive(:generate).with(issue, hierarchical: true).and_return(project_plan)
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    allow(repository_client).to receive(:fetch_issue).with(43).and_return({number: 43, title: "Backend slice"})
    allow(repository_client).to receive(:fetch_issue).with(44).and_return({number: 44, title: "Frontend slice"})
    allow(repository_client).to receive(:update_issue)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)
    allow(creator).to receive(:create_sub_issues)
    allow(creator).to receive(:planned_sub_issue_attributes).and_return(
      {
        title: "Backend slice",
        body: "backend",
        labels: ["aidp-build"],
        assignees: [],
        dependencies: []
      },
      {
        title: "Frontend slice",
        body: "frontend",
        labels: ["aidp-blocked"],
        assignees: [],
        dependencies: ["Backend slice"]
      }
    )
    allow(repository_client).to receive(:fetch_issue).with(43).and_return({
      number: 43,
      title: "Backend slice",
      body: "backend",
      labels: ["aidp-build"],
      assignees: []
    })
    allow(repository_client).to receive(:fetch_issue).with(44).and_return({
      number: 44,
      title: "Frontend slice",
      body: "frontend",
      labels: ["aidp-blocked"],
      assignees: []
    })

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(creator).not_to have_received(:create_sub_issues)
    expect(repository_client).not_to have_received(:update_issue)
    expect(projects_processor).to have_received(:sync_issue_to_project).with(42, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:blocked])
    expect(projects_processor).to have_received(:sync_issue_to_project).with(43, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:todo])
    expect(projects_processor).to have_received(:sync_issue_to_project).with(44, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:blocked])
    expect(state_store.issue_dependencies(44)).to eq([43])
  end

  it "regenerates project sub-issues when tracked issue titles drift from the new plan" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [
        {title: "Backend slice", tasks: ["Ship API"], dependencies: []},
        {title: "Frontend slice", tasks: ["Ship UI"], dependencies: ["Backend slice"]}
      ]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator, create_sub_issues: [{number: 45, dependencies: []}, {number: 46, dependencies: [45]}])

    state_store.record_sub_issues(42, [43, 44])
    state_store.record_issue_dependencies(43, [])
    state_store.record_issue_dependencies(44, [])

    allow(project_generator).to receive(:generate).with(issue, hierarchical: true).and_return(project_plan)
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    expect(repository_client).to receive(:close_issue).with(43)
    expect(repository_client).to receive(:close_issue).with(44)
    allow(repository_client).to receive(:fetch_issue).with(43).and_return({number: 43, title: "Frontend slice"})
    allow(repository_client).to receive(:fetch_issue).with(44).and_return({number: 44, title: "Backend slice"})
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(creator).to have_received(:create_sub_issues).with(issue, project_plan[:sub_issues])
    expect(state_store.issue_dependencies(44)).to eq([])
    expect(state_store.parent_issue(43)).to be_nil
    expect(state_store.parent_issue(44)).to be_nil
  end

  it "preserves a completed tracked sub-issue when aidp-project is re-applied" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "Backend slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator)

    state_store.record_sub_issues(42, [43])
    state_store.record_issue_dependencies(43, [])

    allow(project_generator).to receive(:generate).with(issue, hierarchical: true).and_return(project_plan)
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    allow(creator).to receive(:create_sub_issues)
    allow(creator).to receive(:planned_sub_issue_attributes).and_return(
      title: "Backend slice",
      body: "backend",
      labels: ["aidp-build"],
      assignees: [],
      dependencies: []
    )
    allow(repository_client).to receive(:fetch_issue).with(43).and_return({number: 43, title: "Backend slice", state: "closed"})
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(creator).not_to have_received(:create_sub_issues)
    expect(projects_processor).to have_received(:sync_issue_to_project).with(43, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:done])
    expect(state_store.sub_issues(42)).to eq([43])
    expect(state_store.parent_issue(43)).to eq(42)
  end

  it "preserves completed tracked children while reconciling the remaining open project work" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [
        {title: "Backend slice", tasks: ["Ship API"], dependencies: []},
        {title: "Frontend slice", tasks: ["Ship UI"], dependencies: ["Backend slice"]}
      ]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator)

    state_store.record_sub_issues(42, [43, 44])
    state_store.record_issue_dependencies(43, [])
    state_store.record_issue_dependencies(44, [])

    allow(project_generator).to receive(:generate).with(issue, hierarchical: true).and_return(project_plan)
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    allow(repository_client).to receive(:close_issue)
    allow(creator).to receive(:create_sub_issues)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)
    allow(creator).to receive(:planned_sub_issue_attributes).and_return(
      {
        title: "Frontend slice",
        body: "frontend",
        labels: ["aidp-blocked"],
        assignees: [],
        dependencies: ["Backend slice"]
      }
    )
    allow(repository_client).to receive(:fetch_issue).with(43).and_return({
      number: 43,
      title: "Backend slice",
      body: "backend",
      labels: ["aidp-build"],
      assignees: [],
      state: "closed"
    })
    allow(repository_client).to receive(:fetch_issue).with(44).and_return({
      number: 44,
      title: "Frontend slice",
      body: "frontend",
      labels: ["aidp-blocked"],
      assignees: [],
      state: "open"
    })
    allow(repository_client).to receive(:update_issue)

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(creator).not_to have_received(:create_sub_issues)
    expect(repository_client).not_to have_received(:close_issue)
    expect(projects_processor).to have_received(:sync_issue_to_project).with(43, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:done])
    expect(projects_processor).to have_received(:sync_issue_to_project).with(44, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:blocked])
    expect(state_store.issue_dependencies(44)).to eq([43])
    expect(state_store.sub_issues(42)).to eq([43, 44])
  end

  it "regenerates project sub-issues when tracked hierarchy no longer matches the new plan" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [
        {title: "Backend slice", tasks: ["Ship API"], dependencies: []},
        {title: "Frontend slice", tasks: ["Ship UI"], dependencies: []}
      ]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(
      Aidp::Watch::SubIssueCreator,
      create_sub_issues: [
        {number: 45, title: "Backend slice", dependencies: []},
        {number: 46, title: "Frontend slice", dependencies: []}
      ]
    )

    state_store.record_sub_issues(42, [43])
    state_store.record_issue_dependencies(43, [])

    allow(project_generator).to receive(:generate).with(issue, hierarchical: true).and_return(project_plan)
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    expect(repository_client).to receive(:close_issue).with(43)
    allow(repository_client).to receive(:fetch_issue).with(43).and_return({number: 43, title: "Backend slice", state: "open"})
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(creator).to have_received(:create_sub_issues).with(issue, project_plan[:sub_issues])
    expect(projects_processor).to have_received(:sync_issue_to_project).with(45, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:todo])
    expect(projects_processor).to have_received(:sync_issue_to_project).with(46, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:todo])
    expect(state_store.parent_issue(43)).to be_nil
  end

  it "updates reused tracked sub-issues when the regenerated plan changes their metadata" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [
        {
          title: "Backend slice",
          description: "Fresh description",
          tasks: ["Ship API"],
          labels: ["priority-high"],
          assignees: ["octo"],
          dependencies: []
        }
      ]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator)

    state_store.record_sub_issues(42, [43])
    state_store.record_issue_dependencies(43, [])

    allow(project_generator).to receive(:generate).with(issue, hierarchical: true).and_return(project_plan)
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)
    allow(creator).to receive(:create_sub_issues)
    allow(creator).to receive(:planned_sub_issue_attributes).with(issue, project_plan[:sub_issues].first, 1).and_return(
      {
        title: "Backend slice",
        body: "new body",
        labels: ["aidp-build", "priority-high"],
        assignees: ["octo"],
        dependencies: []
      }
    )
    allow(repository_client).to receive(:fetch_issue).with(43).and_return(
      number: 43,
      title: "Backend slice",
      body: "old body",
      labels: ["aidp-build"],
      assignees: []
    )

    expect(repository_client).to receive(:update_issue).with(
      43,
      title: "Backend slice",
      body: "new body",
      labels: ["aidp-build", "priority-high"],
      assignees: ["octo"]
    )

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(creator).not_to have_received(:create_sub_issues)
    expect(state_store.sub_issues(42)).to eq([43])
  end

  it "moves project issues to needs-input when sub-issue dependency resolution fails" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: ["Missing task"]}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator)

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)
    allow(creator).to receive(:create_sub_issues).and_raise(
      Aidp::Watch::SubIssueCreator::UnresolvedDependenciesError,
      "Unable to resolve dependencies for sub-issue #43 (API slice): Missing task"
    )

    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-project", "aidp-plan", "aidp-build"],
      new_labels: ["aidp-needs-input"]
    )

    project_processor.process(issue, trigger_label: "aidp-project")

    project_sync = state_store.project_sync_data(42)
    expect(project_sync["setup_status"]).to eq("failed")
    expect(project_sync["setup_error"]).to eq("Unable to resolve dependencies for sub-issue #43 (API slice): Missing task")
  end

  it "moves project issues to needs-input when reused tracked sub-issues have duplicate normalized titles" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [
        {title: "Setup", tasks: ["Ship API"], dependencies: []},
        {title: " setup ", tasks: ["Use setup"], dependencies: ["Setup"]}
      ]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator)

    state_store.record_sub_issues(42, [43, 44])
    state_store.record_issue_dependencies(43, [])
    state_store.record_issue_dependencies(44, [])

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)
    allow(creator).to receive(:create_sub_issues)
    allow(creator).to receive(:planned_sub_issue_attributes).with(issue, project_plan[:sub_issues][0], 1).and_return(
      {
        title: "Setup",
        body: "body one",
        labels: ["aidp-build"],
        assignees: [],
        dependencies: []
      }
    )
    allow(creator).to receive(:planned_sub_issue_attributes).with(issue, project_plan[:sub_issues][1], 2).and_return(
      {
        title: " setup ",
        body: "body two",
        labels: ["aidp-blocked"],
        assignees: [],
        dependencies: ["Setup"]
      }
    )
    allow(repository_client).to receive(:fetch_issue).with(43).and_return(
      number: 43,
      title: "Setup",
      body: "body one",
      labels: ["aidp-build"],
      assignees: [],
      state: "open"
    )
    allow(repository_client).to receive(:fetch_issue).with(44).and_return(
      number: 44,
      title: " setup ",
      body: "body two",
      labels: ["aidp-blocked"],
      assignees: [],
      state: "open"
    )

    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-project", "aidp-plan", "aidp-build"],
      new_labels: ["aidp-needs-input"]
    )

    project_processor.process(issue, trigger_label: "aidp-project")

    expect(creator).not_to have_received(:create_sub_issues)

    project_sync = state_store.project_sync_data(42)
    expect(project_sync["setup_status"]).to eq("failed")
    expect(project_sync["setup_error"]).to eq("Duplicate sub-issue titles after normalization are not allowed: Setup / setup")
  end

  it "moves project issues to needs-input when project sync fails" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator, create_sub_issues: [{number: 43, dependencies: []}])

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:find_active_project).and_return({id: "PVT_1", title: "AIDP Project", url: "https://example.com/project"})
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)
    allow(projects_processor).to receive(:sync_issue_to_project).with(42, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:blocked]).and_return(true)
    allow(projects_processor).to receive(:sync_issue_to_project).with(43, status: Aidp::Watch::ProjectsProcessor::STATUS_VALUES[:todo]).and_return(false)

    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-project", "aidp-plan", "aidp-build"],
      new_labels: ["aidp-needs-input"]
    )

    project_processor.process(issue, trigger_label: "aidp-project")

    project_sync = state_store.project_sync_data(42)
    expect(project_sync["setup_status"]).to eq("failed")
    expect(project_sync["setup_error"]).to eq("unable to sync project issues to the GitHub Project")
  end

  it "routes aidp-project clarification follow-up back through the project trigger" do
    project_plan = {
      summary: "Need more detail",
      tasks: [],
      questions: ["Which API should this target?"]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:replace_labels)

    expect(repository_client).to receive(:post_comment) do |_number, body|
      expect(body).to include("remove the `aidp-needs-input` label and add the `aidp-project` label to continue")
      expect(body).not_to include("add the `aidp-build` label to continue")
    end

    project_processor.process(issue, trigger_label: "aidp-project")
  end

  it "creates a new project when no active GitHub Project exists" do
    project_plan = {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: [],
      should_create_sub_issues: true,
      sub_issues: [{title: "API slice", tasks: ["Ship API"], dependencies: []}]
    }
    project_generator = instance_double(Aidp::Watch::PlanGenerator, generate: project_plan)
    project_processor = described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      plan_generator: project_generator
    )
    projects_processor = instance_double(Aidp::Watch::ProjectsProcessor, ensure_project_fields: true, sync_issue_to_project: true)
    creator = instance_double(Aidp::Watch::SubIssueCreator, create_sub_issues: [{number: 43, dependencies: []}])

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:replace_labels)
    allow(repository_client).to receive(:find_active_project).and_return(nil)
    expect(repository_client).to receive(:create_project).with(title: "AIDP Project #42: Add search").and_return(
      {id: "PVT_2", title: "AIDP Project #42: Add search", url: "https://example.com/project/2"}
    )
    allow(Aidp::Watch::ProjectsProcessor).to receive(:new).and_return(projects_processor)
    allow(Aidp::Watch::SubIssueCreator).to receive(:new).and_return(creator)

    project_processor.process(issue, trigger_label: "aidp-project")
  end

  describe "label actor tagging" do
    it "tags the label actor in the comment when available" do
      allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return("testuser")
      allow(repository_client).to receive(:replace_labels)

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("cc @testuser")
      end

      processor.process(issue)
    end

    it "does not include tag when label actor is nil" do
      allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
      allow(repository_client).to receive(:replace_labels)

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).not_to include("cc @")
      end

      processor.process(issue)
    end

    it "includes label actor tag before issue details" do
      allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return("alice")
      allow(repository_client).to receive(:replace_labels)

      expect(repository_client).to receive(:post_comment) do |_number, body|
        lines = body.split("\n")
        tag_index = lines.index { |line| line.include?("cc @alice") }
        issue_index = lines.index { |line| line.include?("**Issue**:") }

        expect(tag_index).not_to be_nil
        expect(issue_index).not_to be_nil
        expect(tag_index).to be < issue_index
      end

      processor.process(issue)
    end
  end
end
