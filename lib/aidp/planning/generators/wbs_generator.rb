# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Generators
      # Generates Work Breakdown Structure (WBS) with phase-based decomposition
      # Breaks down projects into phases, tasks, and subtasks with dependencies
      class WBSGenerator
        DEFAULT_PHASES = [
          "Requirements",
          "Design",
          "Implementation",
          "Testing",
          "Deployment"
        ].freeze

        def initialize(phases: DEFAULT_PHASES, config: nil)
          @phases = phases
          @config = config || Aidp::Config.waterfall_config
        end

        # Generate WBS from PRD and technical design
        # @param prd [Hash] Parsed PRD document
        # @param tech_design [Hash] Parsed technical design document
        # @return [Hash] WBS structure with phases and tasks
        def generate(prd:, tech_design: nil)
          Aidp.log_debug("wbs_generator", "generate", has_prd: !prd.nil?, has_design: !tech_design.nil?)

          wbs = {
            phases: build_phases(prd, tech_design),
            metadata: {
              generated_at: Time.now.iso8601,
              phase_count: @phases.size,
              total_tasks: 0
            }
          }

          wbs[:metadata][:total_tasks] = count_total_tasks(wbs[:phases])

          Aidp.log_debug("wbs_generator", "generated", total_tasks: wbs[:metadata][:total_tasks])
          wbs
        end

        # Format WBS as markdown
        # @param wbs [Hash] WBS structure
        # @return [String] Markdown formatted WBS
        def format_as_markdown(wbs)
          Aidp.log_debug("wbs_generator", "format_as_markdown")

          output = ["# Work Breakdown Structure", ""]
          output << "Generated: #{wbs[:metadata][:generated_at]}"
          output << "Total Phases: #{wbs[:metadata][:phase_count]}"
          output << "Total Tasks: #{wbs[:metadata][:total_tasks]}"
          output << ""

          wbs[:phases].each do |phase|
            output << "## Phase: #{phase[:name]}"
            output << ""
            output << phase[:description] if phase[:description]
            output << ""

            phase[:tasks].each_with_index do |task, idx|
              output << "### #{idx + 1}. #{task[:name]}"
              output << ""
              output << task[:description] if task[:description]
              output << ""

              if task[:subtasks]&.any?
                task[:subtasks].each do |subtask|
                  output << "  - #{subtask[:name]}"
                end
                output << ""
              end

              if task[:dependencies]&.any?
                output << "**Dependencies:** #{task[:dependencies].join(", ")}"
                output << ""
              end

              if task[:effort]
                output << "**Effort:** #{task[:effort]}"
                output << ""
              end
            end
          end

          output.join("\n")
        end

        private

        # Build phase structure from documents
        def build_phases(prd, tech_design)
          Aidp.log_debug("wbs_generator", "build_phases", phase_count: @phases.size)

          @phases.map do |phase_name|
            {
              name: phase_name,
              description: phase_description(phase_name),
              tasks: build_phase_tasks(phase_name, prd, tech_design)
            }
          end
        end

        # Get description for a phase
        def phase_description(phase_name)
          descriptions = {
            "Requirements" => "Gather and document all requirements",
            "Design" => "Design system architecture and components",
            "Implementation" => "Implement features and functionality",
            "Testing" => "Test all features and fix bugs",
            "Deployment" => "Deploy to production and monitor"
          }

          descriptions[phase_name] || "Complete #{phase_name} activities"
        end

        # Build tasks for a specific phase
        # This is a simplified version - in production, would use AI to extract tasks
        def build_phase_tasks(phase_name, prd, tech_design)
          case phase_name
          when "Requirements"
            requirements_tasks(prd)
          when "Design"
            design_tasks(tech_design)
          when "Implementation"
            implementation_tasks(prd, tech_design)
          when "Testing"
            testing_tasks(prd)
          when "Deployment"
            deployment_tasks
          else
            []
          end
        end

        def requirements_tasks(prd)
          [
            {
              name: "Document functional requirements",
              description: "Extract and document all functional requirements from PRD",
              effort: "3 story points",
              dependencies: []
            },
            {
              name: "Document non-functional requirements",
              description: "Extract and document NFRs including performance, security, scalability",
              effort: "2 story points",
              dependencies: []
            }
          ]
        end

        def design_tasks(tech_design)
          [
            {
              name: "Design system architecture",
              description: "Create high-level architecture diagram and component breakdown",
              effort: "5 story points",
              dependencies: []
            },
            {
              name: "Design data models",
              description: "Define data models and database schema",
              effort: "3 story points",
              dependencies: ["Design system architecture"]
            },
            {
              name: "Design API interfaces",
              description: "Define API endpoints and contracts",
              effort: "3 story points",
              dependencies: ["Design system architecture"]
            }
          ]
        end

        def implementation_tasks(prd, tech_design)
          [
            {
              name: "Set up project infrastructure",
              description: "Initialize project, configure build tools, set up CI/CD",
              effort: "3 story points",
              dependencies: []
            },
            {
              name: "Implement core features",
              description: "Implement main functionality per PRD",
              effort: "13 story points",
              dependencies: ["Set up project infrastructure"],
              subtasks: [
                {name: "Feature module 1"},
                {name: "Feature module 2"},
                {name: "Feature module 3"}
              ]
            },
            {
              name: "Implement API layer",
              description: "Build API endpoints per design",
              effort: "8 story points",
              dependencies: ["Implement core features"]
            }
          ]
        end

        def testing_tasks(prd)
          [
            {
              name: "Write unit tests",
              description: "Achieve 85%+ code coverage with unit tests",
              effort: "8 story points",
              dependencies: []
            },
            {
              name: "Write integration tests",
              description: "Test component integration and workflows",
              effort: "5 story points",
              dependencies: ["Write unit tests"]
            },
            {
              name: "Perform UAT",
              description: "User acceptance testing against PRD success criteria",
              effort: "3 story points",
              dependencies: ["Write integration tests"]
            }
          ]
        end

        def deployment_tasks
          [
            {
              name: "Set up production environment",
              description: "Configure production infrastructure and monitoring",
              effort: "3 story points",
              dependencies: []
            },
            {
              name: "Deploy to production",
              description: "Execute deployment and verify health",
              effort: "2 story points",
              dependencies: ["Set up production environment"]
            },
            {
              name: "Monitor and stabilize",
              description: "Monitor system performance and fix production issues",
              effort: "3 story points",
              dependencies: ["Deploy to production"]
            }
          ]
        end

        def count_total_tasks(phases)
          phases.sum { |phase| phase[:tasks].size }
        end
      end
    end
  end
end
