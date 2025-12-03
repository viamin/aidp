# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Watch::ImplementationVerifier do
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:project_dir) { Dir.mktmpdir }
  let(:ai_decision_engine) { instance_double(Aidp::Harness::AIDecisionEngine) }
  let(:verifier) { described_class.new(repository_client: repository_client, project_dir: project_dir, ai_decision_engine: ai_decision_engine) }

  let(:issue) do
    {
      number: 123,
      title: "Add user authentication",
      body: "Implement user login and registration features",
      comments: [
        {
          "author" => "developer",
          "body" => "Plan: 1. Create User model, 2. Add login endpoint, 3. Add registration endpoint",
          "createdAt" => "2025-01-01T00:00:00Z"
        }
      ]
    }
  end

  before do
    # Create a minimal git repo in the temp directory
    Dir.chdir(project_dir) do
      system("git init", out: File::NULL, err: File::NULL)
      system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
      system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
      system("git config commit.gpgsign false", out: File::NULL, err: File::NULL)
      system("git checkout -b main", out: File::NULL, err: File::NULL)

      # Create initial commit
      File.write("README.md", "# Test Project\n")
      system("git add .", out: File::NULL, err: File::NULL)
      system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)

      # Create a feature branch with changes
      system("git checkout -b feature-auth", out: File::NULL, err: File::NULL)
    end

    # Stub AIDecisionEngine - not needed since we pass it in constructor
    # allow(Aidp::Harness::AIDecisionEngine).to receive(:instance).and_return(ai_decision_engine)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#verify" do
    let(:working_dir) { project_dir }

    context "when implementation is complete" do
      before do
        Dir.chdir(working_dir) do
          # Add implementation files
          FileUtils.mkdir_p("app/models")
          FileUtils.mkdir_p("app/controllers")
          File.write("app/models/user.rb", "class User < ApplicationRecord\nend\n")
          File.write("app/controllers/sessions_controller.rb", "class SessionsController < ApplicationController\nend\n")
          File.write("app/controllers/registrations_controller.rb", "class RegistrationsController < ApplicationController\nend\n")
          system("git add .", out: File::NULL, err: File::NULL)
          system("git commit -m 'Add authentication'", out: File::NULL, err: File::NULL)
        end

        # Mock ZFC to return complete
        allow(ai_decision_engine).to receive(:decide).and_return(
          fully_implemented: true,
          reasoning: "All requirements have been implemented",
          missing_requirements: [],
          additional_work_needed: []
        )
      end

      it "returns verified true" do
        result = verifier.verify(issue: issue, working_dir: working_dir)

        expect(result[:verified]).to be true
        expect(result[:reason]).to eq("All requirements have been implemented")
        expect(result[:missing_items]).to be_empty
      end

      it "calls AIDecisionEngine with correct schema" do
        expect(ai_decision_engine).to receive(:decide).with(
          :implementation_verification,
          hash_including(
            context: hash_including(:prompt),
            schema: hash_including(
              type: "object",
              properties: hash_including(:fully_implemented, :reasoning)
            ),
            tier: :mini,
            cache_ttl: nil
          )
        ).and_return(
          fully_implemented: true,
          reasoning: "Complete",
          missing_requirements: [],
          additional_work_needed: []
        )

        verifier.verify(issue: issue, working_dir: working_dir)
      end
    end

    context "when implementation is incomplete" do
      before do
        Dir.chdir(working_dir) do
          # Add only partial implementation
          FileUtils.mkdir_p("app/models")
          File.write("app/models/user.rb", "class User < ApplicationRecord\nend\n")
          system("git add .", out: File::NULL, err: File::NULL)
          system("git commit -m 'Add user model only'", out: File::NULL, err: File::NULL)
        end

        # Mock ZFC to return incomplete
        allow(ai_decision_engine).to receive(:decide).and_return(
          fully_implemented: false,
          reasoning: "Missing login and registration endpoints",
          missing_requirements: ["Login endpoint", "Registration endpoint"],
          additional_work_needed: [
            "Implement SessionsController with login action",
            "Implement RegistrationsController with signup action"
          ]
        )
      end

      it "returns verified false with missing items" do
        result = verifier.verify(issue: issue, working_dir: working_dir)

        expect(result[:verified]).to be false
        expect(result[:reason]).to include("Missing login and registration endpoints")
        expect(result[:missing_items]).to include("Login endpoint", "Registration endpoint")
        expect(result[:additional_work]).to include("Implement SessionsController with login action")
      end
    end

    context "when ZFC verification fails" do
      before do
        allow(ai_decision_engine).to receive(:decide).and_raise(StandardError.new("API error"))
      end

      it "fails safe and returns not verified" do
        result = verifier.verify(issue: issue, working_dir: working_dir)

        expect(result[:verified]).to be false
        expect(result[:reason]).to include("Verification failed due to error")
        expect(result[:missing_items]).to include("Unable to verify due to technical error")
      end

      it "logs the error" do
        expect(Aidp).to receive(:log_error).with(
          "implementation_verifier",
          "zfc_verification_failed",
          hash_including(issue: 123, error: "API error")
        )

        verifier.verify(issue: issue, working_dir: working_dir)
      end
    end

    context "when no changes are present" do
      before do
        # No commits on feature branch
        allow(ai_decision_engine).to receive(:decide).and_return(
          fully_implemented: false,
          reasoning: "No code changes detected",
          missing_requirements: ["All requirements"],
          additional_work_needed: ["Implement all planned features"]
        )
      end

      it "returns not verified" do
        result = verifier.verify(issue: issue, working_dir: working_dir)

        expect(result[:verified]).to be false
      end
    end

    context "with large diffs" do
      before do
        Dir.chdir(working_dir) do
          # Create a large file that will trigger truncation
          large_content = "x" * 20_000
          File.write("large_file.txt", large_content)
          system("git add .", out: File::NULL, err: File::NULL)
          system("git commit -m 'Add large file'", out: File::NULL, err: File::NULL)
        end

        allow(ai_decision_engine).to receive(:decide).and_return(
          fully_implemented: true,
          reasoning: "Complete",
          missing_requirements: [],
          additional_work_needed: []
        )
      end

      it "truncates the diff in the prompt" do
        expect(ai_decision_engine).to receive(:decide).with(
          :implementation_verification,
          hash_including(
            context: hash_including(:prompt)
          )
        ) do |_type, args|
          expect(args[:context][:prompt]).to include("[... diff truncated")
          {
            fully_implemented: true,
            reasoning: "Complete",
            missing_requirements: [],
            additional_work_needed: []
          }
        end

        verifier.verify(issue: issue, working_dir: working_dir)
      end
    end
  end
end
