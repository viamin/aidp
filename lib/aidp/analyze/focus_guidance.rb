# frozen_string_literal: true

require_relative "prioritizer"
require_relative "ruby_maat_integration"
require_relative "feature_analyzer"

module Aidp
  module Analyze
    class FocusGuidance
      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @prioritizer = AnalysisPrioritizer.new(project_dir)
        @code_maat = RubyMaatIntegration.new(project_dir)
        @feature_analyzer = FeatureAnalyzer.new(project_dir)
      end

      # Generate comprehensive focus area recommendations
      def generate_focus_recommendations
        # Get all analysis data
        code_maat_data = @code_maat.run_comprehensive_analysis
        features = @feature_analyzer.detect_features
        @prioritizer.generate_prioritized_recommendations

        {
          high_priority_areas: generate_high_priority_areas(code_maat_data, features),
          medium_priority_areas: generate_medium_priority_areas(code_maat_data, features),
          low_priority_areas: generate_low_priority_areas(code_maat_data, features),
          focus_strategies: generate_focus_strategies(code_maat_data, features),
          interactive_questions: generate_interactive_questions(code_maat_data, features)
        }
      end

      # Interactive focus area selection
      def interactive_focus_selection
        puts "\n🎯 Interactive Focus Area Selection"
        puts "=================================="

        recommendations = generate_focus_recommendations

        # Display high priority areas
        display_priority_areas("HIGH PRIORITY", recommendations[:high_priority_areas])

        # Display medium priority areas
        display_priority_areas("MEDIUM PRIORITY", recommendations[:medium_priority_areas])

        # Display low priority areas
        display_priority_areas("LOW PRIORITY", recommendations[:low_priority_areas])

        # Interactive selection
        selected_areas = collect_user_selections(recommendations)

        # Generate focused analysis plan
        generate_focused_plan(selected_areas, recommendations)
      end

      # Get focus areas based on Code Maat analysis
      def get_code_maat_focus_areas
        @code_maat.run_comprehensive_analysis

        focus_areas = []

        # High churn areas
        high_churn_files = @code_maat.get_high_churn_files(10)
        if high_churn_files.any?
          focus_areas << {
            type: "high_churn",
            title: "High Churn Areas",
            description: "Files with frequent changes indicating potential technical debt",
            files: high_churn_files.first(5),
            priority: "high",
            rationale: "High churn indicates areas that may need refactoring or stabilization"
          }
        end

        # Knowledge silos
        knowledge_silos = @code_maat.get_knowledge_silos
        if knowledge_silos.any?
          focus_areas << {
            type: "knowledge_silo",
            title: "Knowledge Silos",
            description: "Files with single author indicating potential knowledge concentration",
            files: knowledge_silos.first(5),
            priority: "high",
            rationale: "Knowledge silos create risk if the author leaves or becomes unavailable"
          }
        end

        # Tight coupling
        tightly_coupled = @code_maat.get_tightly_coupled_files(5)
        if tightly_coupled.any?
          focus_areas << {
            type: "tight_coupling",
            title: "Tightly Coupled Files",
            description: "Files with high coupling indicating potential architectural issues",
            couplings: tightly_coupled.first(5),
            priority: "medium",
            rationale: "Tight coupling makes the codebase harder to maintain and modify"
          }
        end

        focus_areas
      end

      # Get focus areas based on feature analysis
      def get_feature_focus_areas
        features = @feature_analyzer.detect_features

        focus_areas = []

        # Complex features
        complex_features = features.select { |f| f[:complexity] > 7 }
        if complex_features.any?
          focus_areas << {
            type: "complex_features",
            title: "Complex Features",
            description: "Features with high complexity that may need simplification",
            features: complex_features.first(5),
            priority: "high",
            rationale: "Complex features are harder to understand, test, and maintain"
          }
        end

        # Large features
        large_features = features.select { |f| f[:size]&.> 1000 }
        if large_features.any?
          focus_areas << {
            type: "large_features",
            title: "Large Features",
            description: "Features with large code size that may benefit from decomposition",
            features: large_features.first(5),
            priority: "medium",
            rationale: "Large features may violate single responsibility principle"
          }
        end

        # Features with technical debt indicators
        debt_features = features.select { |f| f[:technical_debt]&.> 5 }
        if debt_features.any?
          focus_areas << {
            type: "technical_debt",
            title: "Technical Debt Hotspots",
            description: "Features with indicators of technical debt",
            features: debt_features.first(5),
            priority: "high",
            rationale: "Technical debt accumulates and makes future development harder"
          }
        end

        focus_areas
      end

      # Generate analysis strategy recommendations
      def generate_analysis_strategies
        code_maat_data = @code_maat.run_comprehensive_analysis
        @feature_analyzer.detect_features

        strategies = []

        # Strategy based on codebase size
        total_files = code_maat_data[:churn][:total_files]
        if total_files > 100
          strategies << {
            type: "large_codebase",
            title: "Large Codebase Strategy",
            description: "Incremental analysis with focus on high-impact areas",
            approach: "Analyze in phases, starting with highest priority areas",
            estimated_effort: "2-4 weeks",
            recommendations: [
              "Start with repository analysis to establish baseline",
              "Focus on high-churn and knowledge silo areas first",
              "Use chunking for large analysis tasks",
              "Prioritize based on business impact"
            ]
          }
        end

        # Strategy based on knowledge silos
        knowledge_silos = code_maat_data[:authorship][:files_with_single_author]
        if knowledge_silos > total_files * 0.3
          strategies << {
            type: "knowledge_silos",
            title: "Knowledge Transfer Strategy",
            description: "Focus on reducing knowledge concentration risk",
            approach: "Document and share knowledge, implement pair programming",
            estimated_effort: "1-2 weeks",
            recommendations: [
              "Document knowledge silo areas thoroughly",
              "Implement pair programming for critical areas",
              "Create knowledge sharing sessions",
              "Consider job rotation for critical knowledge holders"
            ]
          }
        end

        # Strategy based on coupling
        if code_maat_data[:coupling][:average_coupling] > 5
          strategies << {
            type: "coupling_reduction",
            title: "Coupling Reduction Strategy",
            description: "Focus on reducing tight coupling between components",
            approach: "Refactor to improve modularity and reduce dependencies",
            estimated_effort: "2-3 weeks",
            recommendations: [
              "Identify coupling hotspots",
              "Refactor tightly coupled components",
              "Introduce interfaces and abstractions",
              "Implement dependency injection where appropriate"
            ]
          }
        end

        strategies
      end

      private

      def generate_high_priority_areas(code_maat_data, features)
        areas = []

        # High churn + knowledge silos
        high_churn_silos = @prioritizer.get_high_priority_targets.select { |t| t[:type] == "knowledge_silo" }
        if high_churn_silos.any?
          areas << {
            type: "critical_risk",
            title: "Critical Risk Areas",
            description: "High churn files with single authors - immediate attention required",
            items: high_churn_silos.first(3),
            impact: "high",
            effort: "medium",
            urgency: "immediate"
          }
        end

        # Tight coupling
        tight_coupling = @prioritizer.get_high_priority_targets.select { |t| t[:type] == "tight_coupling" }
        if tight_coupling.any?
          areas << {
            type: "architectural_risk",
            title: "Architectural Risk Areas",
            description: "Tightly coupled files that may cause cascading changes",
            items: tight_coupling.first(3),
            impact: "high",
            effort: "high",
            urgency: "high"
          }
        end

        areas
      end

      def generate_medium_priority_areas(code_maat_data, features)
        areas = []

        # Coordination issues
        coordination_issues = @prioritizer.get_medium_priority_targets.select { |t| t[:type] == "coordination_issue" }
        if coordination_issues.any?
          areas << {
            type: "coordination_risk",
            title: "Coordination Risk Areas",
            description: "High churn files with multiple authors - potential coordination issues",
            items: coordination_issues.first(3),
            impact: "medium",
            effort: "medium",
            urgency: "medium"
          }
        end

        # Medium churn areas
        medium_churn = @prioritizer.get_medium_priority_targets.select { |t| t[:type] == "medium_churn" }
        if medium_churn.any?
          areas << {
            type: "monitoring_areas",
            title: "Monitoring Areas",
            description: "Medium churn files that should be monitored for increasing complexity",
            items: medium_churn.first(3),
            impact: "medium",
            effort: "low",
            urgency: "low"
          }
        end

        areas
      end

      def generate_low_priority_areas(code_maat_data, features)
        areas = []

        # Stable areas
        stable_areas = @prioritizer.get_low_priority_targets.select { |t| t[:type] == "low_churn" }
        if stable_areas.any?
          areas << {
            type: "stable_areas",
            title: "Stable Areas",
            description: "Low churn files that are stable and may not need immediate attention",
            items: stable_areas.first(3),
            impact: "low",
            effort: "low",
            urgency: "none"
          }
        end

        areas
      end

      def generate_focus_strategies(code_maat_data, features)
        strategies = []

        # Risk-based strategy
        strategies << {
          type: "risk_based",
          title: "Risk-Based Focus",
          description: "Focus on areas with highest risk (knowledge silos, high churn)",
          priority_order: %w[critical_risk architectural_risk coordination_risk],
          rationale: "Address highest risks first to reduce project vulnerability"
        }

        # Impact-based strategy
        strategies << {
          type: "impact_based",
          title: "Impact-Based Focus",
          description: "Focus on areas with highest business impact",
          priority_order: %w[high_impact medium_impact low_impact],
          rationale: "Maximize business value by focusing on high-impact areas"
        }

        # Effort-based strategy
        strategies << {
          type: "effort_based",
          title: "Effort-Based Focus",
          description: "Focus on areas with lowest effort for quick wins",
          priority_order: %w[low_effort medium_effort high_effort],
          rationale: "Quick wins build momentum and demonstrate value quickly"
        }

        strategies
      end

      def generate_interactive_questions(code_maat_data, features)
        questions = []

        # Business context questions
        questions << {
          type: "business_context",
          question: "What are the most critical business functions that must be maintained?",
          purpose: "Identify business-critical areas for prioritization",
          options: ["User-facing features", "Data processing", "Integration points", "Security components"]
        }

        # Risk tolerance questions
        questions << {
          type: "risk_tolerance",
          question: "What is your tolerance for technical risk?",
          purpose: "Determine how aggressive to be with refactoring",
          options: ["Conservative - minimize risk", "Balanced - moderate risk", "Aggressive - accept higher risk"]
        }

        # Timeline questions
        questions << {
          type: "timeline",
          question: "What is your timeline for addressing technical debt?",
          purpose: "Determine analysis scope and depth",
          options: ["Immediate - critical issues only", "Short-term - 1-3 months", "Long-term - 3-12 months"]
        }

        # Resource questions
        questions << {
          type: "resources",
          question: "What resources are available for analysis and refactoring?",
          purpose: "Determine analysis approach and scope",
          options: ["Limited - focus on highest impact", "Moderate - balanced approach",
            "Extensive - comprehensive analysis"]
        }

        questions
      end

      def display_priority_areas(priority_level, areas)
        puts "\n#{priority_level} AREAS"
        puts "=" * priority_level.length

        if areas.empty?
          puts "No #{priority_level.downcase} areas identified."
          return
        end

        areas.each_with_index do |area, index|
          puts "\n#{index + 1}. #{area[:title]}"
          puts "   Description: #{area[:description]}"
          puts "   Impact: #{area[:impact].upcase} | Effort: #{area[:effort].upcase} | Urgency: #{area[:urgency].upcase}"

          next unless area[:items]&.any?

          puts "   Key items:"
          area[:items].first(3).each do |item|
            if item[:file]
              puts "     - #{item[:file]} (#{item[:changes]} changes)"
            elsif item[:file1] && item[:file2]
              puts "     - #{item[:file1]} ↔ #{item[:file2]} (#{item[:shared_changes]} shared changes)"
            end
          end
        end
      end

      def collect_user_selections(recommendations)
        puts "\n🎯 FOCUS AREA SELECTION"
        puts "======================"

        selected_areas = []

        # Collect high priority selections
        if recommendations[:high_priority_areas].any?
          puts "\nSelect HIGH PRIORITY areas to focus on (comma-separated numbers, or 'all'):"
          high_selections = get_user_input
          selected_areas.concat(parse_selections(high_selections, recommendations[:high_priority_areas]))
        end

        # Collect medium priority selections
        if recommendations[:medium_priority_areas].any?
          puts "\nSelect MEDIUM PRIORITY areas to focus on (comma-separated numbers, or 'all'):"
          medium_selections = get_user_input
          selected_areas.concat(parse_selections(medium_selections, recommendations[:medium_priority_areas]))
        end

        # Collect low priority selections
        if recommendations[:low_priority_areas].any?
          puts "\nSelect LOW PRIORITY areas to focus on (comma-separated numbers, or 'all'):"
          low_selections = get_user_input
          selected_areas.concat(parse_selections(low_selections, recommendations[:low_priority_areas]))
        end

        selected_areas
      end

      def get_user_input
        print "> "
        gets.chomp.strip
      end

      def parse_selections(input, areas)
        return [] if input.empty? || input.casecmp("none").zero?
        return areas if input.casecmp("all").zero?

        selections = []
        input.split(",").each do |num|
          index = num.strip.to_i - 1
          selections << areas[index] if index >= 0 && index < areas.length
        end

        selections
      end

      def generate_focused_plan(selected_areas, recommendations)
        puts "\n📋 FOCUSED ANALYSIS PLAN"
        puts "========================"

        if selected_areas.empty?
          puts "No focus areas selected. Running comprehensive analysis."
          return
        end

        puts "\nSelected focus areas:"
        selected_areas.each_with_index do |area, index|
          puts "#{index + 1}. #{area[:title]} (#{area[:type]})"
        end

        puts "\nRecommended analysis approach:"
        puts "1. Start with repository analysis for baseline"
        puts "2. Focus analysis on selected areas"
        puts "3. Generate targeted recommendations"
        puts "4. Create action plan for each focus area"

        # Save focus plan
        save_focus_plan(selected_areas)
      end

      def save_focus_plan(selected_areas)
        plan_file = File.join(@project_dir, "focus_analysis_plan.md")

        plan_content = <<~PLAN
          # Focus Analysis Plan

          Generated on: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}
          Project: #{File.basename(@project_dir)}

          ## Selected Focus Areas

          #{selected_areas.map.with_index { |area, i| "#{i + 1}. **#{area[:title]}** (#{area[:type]})" }.join("\n")}

          ## Analysis Strategy

          ### Phase 1: Baseline Analysis
          - Repository analysis to establish current state
          - Code Maat analysis for historical patterns
          - Feature analysis for current structure

          ### Phase 2: Focused Analysis
          #{selected_areas.map { |area| "- #{area[:title]} analysis" }.join("\n")}

          ### Phase 3: Recommendations
          - Generate targeted recommendations for each focus area
          - Create action plan with priorities and timelines
          - Define success metrics for each area

          ## Next Steps

          1. Run `aidp analyze repository` to establish baseline
          2. Run focused analysis on selected areas
          3. Review and approve analysis results
          4. Implement recommended improvements
        PLAN

        File.write(plan_file, plan_content)
        puts "\nFocus plan saved to: #{plan_file}"
      end
    end
  end
end
