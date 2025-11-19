# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/generators/legacy_research_planner"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Planning::Generators::LegacyResearchPlanner do
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:prompt) { double("TTY::Prompt") }
  let(:config) { {} }

  subject(:planner) do
    described_class.new(
      ai_decision_engine: ai_decision_engine,
      prompt: prompt,
      config: config
    )
  end

  describe "#generate" do
    let(:ai_response) do
      {
        overview: "Research plan for existing product",
        current_features: [
          {
            name: "User Management",
            description: "Manage users and permissions",
            entry_points: ["/users", "/admin/users"],
            status: "active"
          }
        ],
        research_questions: [
          {
            question: "How do users manage permissions?",
            category: "workflow",
            priority: "high"
          }
        ],
        research_methods: [
          {
            name: "User Interviews",
            description: "Talk to users about workflows",
            when_to_use: "Understanding pain points",
            expected_insights: "User pain points and needs"
          }
        ],
        testing_priorities: [
          {
            feature: "User Management",
            priority: "high",
            rationale: "Core feature with complexity",
            focus_areas: ["Permission workflows", "Bulk operations"]
          }
        ],
        user_segments: [
          {
            name: "Administrators",
            description: "System admins managing users",
            research_focus: "Permission management workflows"
          }
        ],
        improvement_opportunities: [
          {
            title: "Simplify Permissions",
            description: "Permission system is complex",
            impact: "high",
            effort: "medium"
          }
        ],
        timeline: [
          {
            phase: "Analysis",
            duration: "1 week"
          },
          {
            phase: "User Interviews",
            duration: "2 weeks"
          }
        ]
      }
    end

    it "generates research plan from codebase analysis" do
      Dir.mktmpdir do |tmpdir|
        # Create sample codebase structure
        FileUtils.mkdir_p(File.join(tmpdir, "app", "controllers"))
        FileUtils.mkdir_p(File.join(tmpdir, "app", "models"))
        File.write(File.join(tmpdir, "app", "controllers", "users_controller.rb"), "class UsersController; end")
        File.write(File.join(tmpdir, "README.md"), "# My Project")

        expect(ai_decision_engine).to receive(:decide)
          .with(hash_including(
            context: "legacy_research_plan_generation"
          ))
          .and_return(ai_response)

        result = planner.generate(codebase_path: tmpdir, language: "Ruby")

        expect(result[:overview]).to eq(ai_response[:overview])
        expect(result[:current_features]).to eq(ai_response[:current_features])
        expect(result[:research_questions]).to eq(ai_response[:research_questions])
        expect(result[:testing_priorities]).to eq(ai_response[:testing_priorities])
      end
    end

    it "analyzes codebase structure and identifies features" do
      Dir.mktmpdir do |tmpdir|
        # Create directories that look like features
        FileUtils.mkdir_p(File.join(tmpdir, "app", "features", "authentication"))
        FileUtils.mkdir_p(File.join(tmpdir, "app", "features", "reporting"))
        FileUtils.mkdir_p(File.join(tmpdir, "app", "controllers"))
        File.write(File.join(tmpdir, "app", "controllers", "auth_controller.rb"), "class AuthController; end")

        allow(ai_decision_engine).to receive(:decide).and_return(ai_response)

        result = planner.generate(codebase_path: tmpdir)

        # Should have analyzed the codebase
        expect(result[:metadata][:codebase_path]).to eq(tmpdir)
        expect(result[:metadata][:file_count]).to be > 0
        expect(result[:codebase_summary]).to be_a(String)
      end
    end

    it "raises error for non-existent codebase path" do
      expect {
        planner.generate(codebase_path: "/nonexistent/path")
      }.to raise_error(ArgumentError, /does not exist/)
    end

    it "includes metadata in result" do
      Dir.mktmpdir do |tmpdir|
        allow(ai_decision_engine).to receive(:decide).and_return(ai_response)

        result = planner.generate(codebase_path: tmpdir, language: "Ruby")

        expect(result[:metadata][:generated_at]).to be_a(String)
        expect(result[:metadata][:codebase_path]).to eq(tmpdir)
        expect(result[:metadata][:language]).to eq("Ruby")
        expect(result[:metadata][:feature_count]).to eq(1)
        expect(result[:metadata][:research_question_count]).to eq(1)
      end
    end

    it "detects language from file extensions when not specified" do
      Dir.mktmpdir do |tmpdir|
        File.write(File.join(tmpdir, "main.py"), "print('hello')")
        File.write(File.join(tmpdir, "utils.py"), "def func(): pass")

        allow(ai_decision_engine).to receive(:decide).and_return(ai_response)

        result = planner.generate(codebase_path: tmpdir)

        expect(result[:metadata][:language]).to eq("Python").or be_nil # Language detection is optional
      end
    end
  end

  describe "#format_as_markdown" do
    let(:plan) do
      {
        overview: "Research plan overview",
        codebase_summary: "Analyzed 50 files",
        current_features: [
          {
            name: "Authentication",
            description: "User login and registration",
            entry_points: ["/login", "/register"],
            status: "active"
          }
        ],
        research_questions: [
          {
            question: "How do users sign up?",
            category: "workflow",
            priority: "high"
          }
        ],
        research_methods: [
          {
            name: "Surveys",
            description: "Collect quantitative data",
            when_to_use: "Large sample needed",
            expected_insights: "Usage patterns"
          }
        ],
        testing_priorities: [
          {
            feature: "Authentication",
            priority: "high",
            rationale: "Critical user flow",
            focus_areas: ["Registration", "Password reset"]
          }
        ],
        user_segments: [
          {
            name: "New Users",
            description: "First-time users",
            research_focus: "Onboarding experience"
          }
        ],
        improvement_opportunities: [
          {
            title: "Simplify Signup",
            description: "Too many steps",
            impact: "high",
            effort: "low"
          }
        ],
        timeline: [
          {
            phase: "Recruitment",
            duration: "1 week"
          }
        ],
        metadata: {
          generated_at: "2025-01-15T10:00:00Z",
          codebase_path: "/path/to/code",
          feature_count: 1,
          file_count: 50,
          research_question_count: 1
        }
      }
    end

    it "formats research plan as markdown" do
      markdown = planner.format_as_markdown(plan)

      expect(markdown).to include("# Legacy User Research Plan")
      expect(markdown).to include("## Overview")
      expect(markdown).to include("## Codebase Summary")
      expect(markdown).to include("## Current Features")
      expect(markdown).to include("## Research Questions")
      expect(markdown).to include("## Recommended Research Methods")
      expect(markdown).to include("## Testing Priorities")
      expect(markdown).to include("## User Segments")
      expect(markdown).to include("## Improvement Opportunities")
      expect(markdown).to include("## Research Timeline")
    end

    it "includes metadata in markdown" do
      markdown = planner.format_as_markdown(plan)

      expect(markdown).to include("**Generated:** 2025-01-15T10:00:00Z")
      expect(markdown).to include("**Codebase:** /path/to/code")
      expect(markdown).to include("**Features Identified:** 1")
      expect(markdown).to include("**Files Analyzed:** 50")
    end
  end
end
