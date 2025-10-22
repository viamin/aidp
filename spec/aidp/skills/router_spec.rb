# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/skills/router"

RSpec.describe Aidp::Skills::Router do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_dir) { File.join(temp_dir, ".aidp") }
  let(:config_path) { File.join(config_dir, "aidp.yml") }

  before do
    FileUtils.mkdir_p(config_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def write_config(config)
    File.write(config_path, config.to_yaml)
  end

  describe "#initialize" do
    it "loads configuration from aidp.yml" do
      write_config({"skills" => {"routing" => {"enabled" => true}}})

      router = described_class.new(project_dir: temp_dir)

      expect(router.config).to be_a(Hash)
      expect(router.routing_enabled?).to be true
    end

    it "handles missing configuration file" do
      FileUtils.rm_f(config_path)

      router = described_class.new(project_dir: temp_dir)

      expect(router.config).to eq({})
      expect(router.routing_enabled?).to be false
    end
  end

  describe "#route_by_path" do
    context "with path rules configured" do
      before do
        write_config({
          "skills" => {
            "routing" => {
              "path_rules" => {
                "rails_expert" => ["app/controllers/**/*.rb", "app/models/**/*.rb"],
                "frontend_expert" => ["app/javascript/**/*.{js,jsx,ts,tsx}"],
                "test_expert" => "spec/**/*_spec.rb"
              }
            }
          }
        })
      end

      it "matches controller files to rails_expert" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_path("app/controllers/users_controller.rb")

        expect(skill_id).to eq("rails_expert")
      end

      it "matches model files to rails_expert" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_path("app/models/user.rb")

        expect(skill_id).to eq("rails_expert")
      end

      it "matches JavaScript files to frontend_expert" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_path("app/javascript/components/Button.jsx")

        expect(skill_id).to eq("frontend_expert")
      end

      it "matches TypeScript files to frontend_expert" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_path("app/javascript/utils/helpers.ts")

        expect(skill_id).to eq("frontend_expert")
      end

      it "matches spec files to test_expert" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_path("spec/models/user_spec.rb")

        expect(skill_id).to eq("test_expert")
      end

      it "returns nil for unmatched paths" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_path("README.md")

        expect(skill_id).to be_nil
      end
    end

    context "without path rules" do
      before do
        write_config({"skills" => {}})
      end

      it "returns nil" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_path("app/controllers/users_controller.rb")

        expect(skill_id).to be_nil
      end
    end
  end

  describe "#route_by_task" do
    context "with task rules configured" do
      before do
        write_config({
          "skills" => {
            "routing" => {
              "task_rules" => {
                "backend_developer" => ["api", "endpoint", "database", "migration"],
                "frontend_developer" => ["ui", "component", "styling", "layout"],
                "devops_engineer" => ["deploy", "docker", "kubernetes", "ci/cd"]
              }
            }
          }
        })
      end

      it "matches API tasks to backend_developer" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_task("Add a new API endpoint")

        expect(skill_id).to eq("backend_developer")
      end

      it "matches database tasks to backend_developer" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_task("Create database migration")

        expect(skill_id).to eq("backend_developer")
      end

      it "matches UI tasks to frontend_developer" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_task("Build new UI component")

        expect(skill_id).to eq("frontend_developer")
      end

      it "matches deployment tasks to devops_engineer" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_task("Deploy to Kubernetes")

        expect(skill_id).to eq("devops_engineer")
      end

      it "is case insensitive" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_task("ADD NEW API ENDPOINT")

        expect(skill_id).to eq("backend_developer")
      end

      it "returns nil for unmatched tasks" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_task("Write documentation")

        expect(skill_id).to be_nil
      end
    end

    context "without task rules" do
      before do
        write_config({"skills" => {}})
      end

      it "returns nil" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route_by_task("Add API endpoint")

        expect(skill_id).to be_nil
      end
    end
  end

  describe "#route" do
    context "with combined rules" do
      before do
        write_config({
          "skills" => {
            "routing" => {
              "combined_rules" => {
                "full_stack_expert" => {
                  "paths" => ["app/controllers/**/*.rb"],
                  "tasks" => ["api", "endpoint"]
                }
              },
              "path_rules" => {
                "rails_expert" => "app/controllers/**/*.rb"
              },
              "task_rules" => {
                "backend_developer" => ["api", "endpoint"]
              },
              "default" => "general_developer"
            }
          }
        })
      end

      it "prioritizes combined rules over path rules" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route(
          path: "app/controllers/api/users_controller.rb",
          task: "Add new API endpoint"
        )

        expect(skill_id).to eq("full_stack_expert")
      end

      it "falls back to path rules when task doesn't match" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route(
          path: "app/controllers/users_controller.rb",
          task: "Refactor code"
        )

        expect(skill_id).to eq("rails_expert")
      end

      it "falls back to task rules when path doesn't match" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route(
          path: "lib/api_client.rb",
          task: "Add new API endpoint"
        )

        expect(skill_id).to eq("backend_developer")
      end

      it "uses default when nothing matches" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route(
          path: "README.md",
          task: "Update documentation"
        )

        expect(skill_id).to eq("general_developer")
      end
    end

    context "with only path provided" do
      before do
        write_config({
          "skills" => {
            "routing" => {
              "path_rules" => {
                "rails_expert" => "app/**/*.rb"
              }
            }
          }
        })
      end

      it "routes by path" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route(path: "app/models/user.rb")

        expect(skill_id).to eq("rails_expert")
      end
    end

    context "with only task provided" do
      before do
        write_config({
          "skills" => {
            "routing" => {
              "task_rules" => {
                "backend_developer" => "api"
              }
            }
          }
        })
      end

      it "routes by task" do
        router = described_class.new(project_dir: temp_dir)

        skill_id = router.route(task: "Add API endpoint")

        expect(skill_id).to eq("backend_developer")
      end
    end
  end

  describe "#routing_enabled?" do
    it "returns true when enabled" do
      write_config({"skills" => {"routing" => {"enabled" => true}}})

      router = described_class.new(project_dir: temp_dir)

      expect(router.routing_enabled?).to be true
    end

    it "returns false when disabled" do
      write_config({"skills" => {"routing" => {"enabled" => false}}})

      router = described_class.new(project_dir: temp_dir)

      expect(router.routing_enabled?).to be false
    end

    it "returns false when not configured" do
      write_config({})

      router = described_class.new(project_dir: temp_dir)

      expect(router.routing_enabled?).to be false
    end
  end

  describe "#default_skill" do
    it "returns configured default skill" do
      write_config({"skills" => {"routing" => {"default" => "general_developer"}}})

      router = described_class.new(project_dir: temp_dir)

      expect(router.default_skill).to eq("general_developer")
    end

    it "returns nil when no default configured" do
      write_config({})

      router = described_class.new(project_dir: temp_dir)

      expect(router.default_skill).to be_nil
    end
  end

  describe "#rules" do
    it "returns all routing rules" do
      write_config({
        "skills" => {
          "routing" => {
            "path_rules" => {"skill1" => "path/**/*.rb"},
            "task_rules" => {"skill2" => ["keyword"]},
            "combined_rules" => {"skill3" => {"paths" => ["path"], "tasks" => ["task"]}}
          }
        }
      })

      router = described_class.new(project_dir: temp_dir)
      rules = router.rules

      expect(rules[:path_rules]).to eq({"skill1" => "path/**/*.rb"})
      expect(rules[:task_rules]).to eq({"skill2" => ["keyword"]})
      expect(rules[:combined_rules]).to eq({"skill3" => {"paths" => ["path"], "tasks" => ["task"]}})
    end
  end

  describe "glob pattern matching" do
    before do
      write_config({
        "skills" => {
          "routing" => {
            "path_rules" => {
              "test1" => "config/**/*.rb",
              "test2" => "lib/**/*.rb",
              "test3" => "app/{models,controllers}/**/*.rb"
            }
          }
        }
      })
    end

    it "matches config pattern" do
      router = described_class.new(project_dir: temp_dir)

      expect(router.route_by_path("config/routes.rb")).to eq("test1")
    end

    it "matches specific directory pattern" do
      router = described_class.new(project_dir: temp_dir)

      expect(router.route_by_path("lib/aidp/cli.rb")).to eq("test2")
    end

    it "matches brace expansion pattern" do
      router = described_class.new(project_dir: temp_dir)

      expect(router.route_by_path("app/models/user.rb")).to eq("test3")
      expect(router.route_by_path("app/controllers/users_controller.rb")).to eq("test3")
    end
  end
end
