# frozen_string_literal: true

require "tty-prompt"
require_relative "ruby_maat_integration"
require_relative "feature_analyzer"

module Aidp
  module Analyze
    class Prioritizer
      def initialize(project_dir = Dir.pwd, prompt: TTY::Prompt.new)
        @project_dir = project_dir
        @code_maat = Aidp::Analyze::RubyMaatIntegration.new(project_dir, prompt: prompt)
        @feature_analyzer = Aidp::Analyze::FeatureAnalyzer.new(project_dir)
      end

      # Generate prioritized analysis recommendations based on ruby-maat data
      def generate_prioritized_recommendations
        # Get ruby-maat analysis data
        code_maat_data = @code_maat.run_comprehensive_analysis

        # Get feature analysis data
        features = @feature_analyzer.detect_features

        # Generate prioritized recommendations
        {
          high_priority: generate_high_priority_recommendations(code_maat_data, features),
          medium_priority: generate_medium_priority_recommendations(code_maat_data, features),
          low_priority: generate_low_priority_recommendations(code_maat_data, features),
          focus_areas: identify_focus_areas(code_maat_data, features),
          analysis_strategy: generate_analysis_strategy(code_maat_data, features)
        }
      end

      # Get high-priority analysis targets
      def get_high_priority_targets
        @code_maat.run_comprehensive_analysis

        high_priority = []

        # High churn + single author (knowledge silos)
        high_churn_files = @code_maat.get_high_churn_files(10)
        knowledge_silos = @code_maat.get_knowledge_silos

        high_churn_files.each do |churn_file|
          silo_file = knowledge_silos.find { |s| s[:file] == churn_file[:file] }
          next unless silo_file

          high_priority << {
            type: "knowledge_silo",
            file: churn_file[:file],
            changes: churn_file[:changes],
            author: silo_file[:authors].first,
            priority_score: calculate_priority_score(churn_file, silo_file),
            recommendation: "High churn file with single author - potential knowledge silo"
          }
        end

        # Tightly coupled files
        tightly_coupled = @code_maat.get_tightly_coupled_files(5)
        tightly_coupled.each do |coupling|
          high_priority << {
            type: "tight_coupling",
            file1: coupling[:file1],
            file2: coupling[:file2],
            shared_changes: coupling[:shared_changes],
            priority_score: coupling[:shared_changes] * 2,
            recommendation: "Tightly coupled files - consider refactoring to reduce coupling"
          }
        end

        high_priority.sort_by { |item| -item[:priority_score] }
      end

      # Get medium-priority analysis targets
      def get_medium_priority_targets
        code_maat_data = @code_maat.run_comprehensive_analysis

        medium_priority = []

        # High churn + multiple authors (coordination issues)
        high_churn_files = @code_maat.get_high_churn_files(5)
        multi_author_files = code_maat_data[:authorship][:files].select { |f| f[:author_count] > 1 }

        high_churn_files.each do |churn_file|
          multi_auth_file = multi_author_files.find { |m| m[:file] == churn_file[:file] }
          next unless multi_auth_file

          medium_priority << {
            type: "coordination_issue",
            file: churn_file[:file],
            changes: churn_file[:changes],
            authors: multi_auth_file[:authors],
            priority_score: calculate_priority_score(churn_file, multi_auth_file),
            recommendation: "High churn file with multiple authors - potential coordination issues"
          }
        end

        # Medium churn files
        medium_churn_files = code_maat_data[:churn][:files].select { |f| f[:changes] > 3 && f[:changes] <= 10 }
        medium_churn_files.each do |file|
          medium_priority << {
            type: "medium_churn",
            file: file[:file],
            changes: file[:changes],
            priority_score: file[:changes],
            recommendation: "Medium churn file - monitor for increasing complexity"
          }
        end

        medium_priority.sort_by { |item| -item[:priority_score] }
      end

      # Get low-priority analysis targets
      def get_low_priority_targets
        code_maat_data = @code_maat.run_comprehensive_analysis

        low_priority = []

        # Low churn files
        low_churn_files = code_maat_data[:churn][:files].select { |f| f[:changes] <= 3 }
        low_churn_files.each do |file|
          low_priority << {
            type: "low_churn",
            file: file[:file],
            changes: file[:changes],
            priority_score: file[:changes],
            recommendation: "Low churn file - stable, may not need immediate attention"
          }
        end

        low_priority.sort_by { |item| -item[:priority_score] }
      end

      # Identify focus areas for analysis
      def identify_focus_areas
        @code_maat.run_comprehensive_analysis
        @feature_analyzer.detect_features

        focus_areas = []

        # High churn areas
        high_churn_files = @code_maat.get_high_churn_files(8)
        high_churn_areas = group_files_by_directory(high_churn_files.map { |f| f[:file] })

        high_churn_areas.each do |area, files|
          focus_areas << {
            type: "high_churn_area",
            area: area,
            files: files,
            priority: "high",
            recommendation: "High churn area - focus analysis on #{area} directory"
          }
        end

        # Knowledge silo areas
        knowledge_silos = @code_maat.get_knowledge_silos
        silo_areas = group_files_by_directory(knowledge_silos.map { |f| f[:file] })

        silo_areas.each do |area, files|
          focus_areas << {
            type: "knowledge_silo_area",
            area: area,
            files: files,
            priority: "high",
            recommendation: "Knowledge silo area - #{area} has single-author files"
          }
        end

        # Coupling hotspots
        tightly_coupled = @code_maat.get_tightly_coupled_files(3)
        coupling_areas = identify_coupling_hotspots(tightly_coupled)

        coupling_areas.each do |area, couplings|
          focus_areas << {
            type: "coupling_hotspot",
            area: area,
            couplings: couplings,
            priority: "medium",
            recommendation: "Coupling hotspot - #{area} has tightly coupled files"
          }
        end

        focus_areas
      end

      # Generate analysis strategy recommendations
      def generate_analysis_strategy
        code_maat_data = @code_maat.run_comprehensive_analysis
        @feature_analyzer.detect_features

        {
          overall_approach: determine_overall_approach(code_maat_data),
          analysis_order: determine_analysis_order(code_maat_data),
          resource_allocation: determine_resource_allocation(code_maat_data),
          risk_assessment: assess_analysis_risks(code_maat_data),
          success_metrics: define_success_metrics(code_maat_data)
        }
      end

      private

      def generate_high_priority_recommendations(code_maat_data, features)
        recommendations = []

        # Knowledge silos
        knowledge_silos = @code_maat.get_knowledge_silos
        knowledge_silos.each do |silo|
          recommendations << {
            type: "knowledge_silo",
            target: silo[:file],
            priority: "high",
            rationale: "Single author with #{silo[:changes]} changes",
            action: "Document knowledge and consider pair programming",
            effort: "medium",
            impact: "high"
          }
        end

        # Tight coupling
        tightly_coupled = @code_maat.get_tightly_coupled_files(5)
        tightly_coupled.each do |coupling|
          recommendations << {
            type: "tight_coupling",
            target: "#{coupling[:file1]} ↔ #{coupling[:file2]}",
            priority: "high",
            rationale: "#{coupling[:shared_changes]} shared changes",
            action: "Refactor to reduce coupling",
            effort: "high",
            impact: "high"
          }
        end

        recommendations
      end

      def generate_medium_priority_recommendations(code_maat_data, features)
        recommendations = []

        # High churn with multiple authors
        high_churn_multi_author = code_maat_data[:churn][:files].select do |file|
          file[:changes] > 5 &&
            (code_maat_data[:authorship][:files].find { |a| a[:file] == file[:file] }&.dig(:author_count)&.> 1)
        end

        high_churn_multi_author.each do |file|
          recommendations << {
            type: "coordination_issue",
            target: file[:file],
            priority: "medium",
            rationale: "High churn (#{file[:changes]} changes) with multiple authors",
            action: "Improve coordination and communication",
            effort: "medium",
            impact: "medium"
          }
        end

        recommendations
      end

      def generate_low_priority_recommendations(code_maat_data, features)
        recommendations = []

        # Stable files
        stable_files = code_maat_data[:churn][:files].select { |f| f[:changes] <= 2 }
        stable_files.each do |file|
          recommendations << {
            type: "stable_file",
            target: file[:file],
            priority: "low",
            rationale: "Low churn (#{file[:changes]} changes) - stable",
            action: "Monitor for changes",
            effort: "low",
            impact: "low"
          }
        end

        recommendations
      end

      def calculate_priority_score(churn_file, authorship_file)
        base_score = churn_file[:changes]

        # Adjust for authorship patterns
        if authorship_file[:author_count] == 1
          base_score *= 1.5 # Knowledge silo penalty
        elsif authorship_file[:author_count] > 3
          base_score *= 1.2 # Coordination complexity penalty
        end

        base_score
      end

      def group_files_by_directory(files)
        grouped = {}

        files.each do |file|
          dir = File.dirname(file)
          grouped[dir] ||= []
          grouped[dir] << file
        end

        grouped
      end

      def identify_coupling_hotspots(couplings)
        hotspots = {}

        couplings.each do |coupling|
          dir1 = File.dirname(coupling[:file1])
          dir2 = File.dirname(coupling[:file2])

          # Group by common directory or create cross-directory coupling
          if dir1 == dir2
            hotspots[dir1] ||= []
            hotspots[dir1] << coupling
          else
            cross_dir = "#{dir1} ↔ #{dir2}"
            hotspots[cross_dir] ||= []
            hotspots[cross_dir] << coupling
          end
        end

        hotspots
      end

      def determine_overall_approach(code_maat_data)
        total_files = code_maat_data[:churn][:total_files]
        high_churn_count = code_maat_data[:churn][:files].count { |f| f[:changes] > 10 }
        knowledge_silos = code_maat_data[:authorship][:files_with_single_author]

        if high_churn_count > total_files * 0.3
          "aggressive_refactoring"
        elsif knowledge_silos > total_files * 0.2
          "knowledge_transfer_focused"
        elsif code_maat_data[:coupling][:average_coupling] > 5
          "coupling_reduction_focused"
        else
          "incremental_improvement"
        end
      end

      def determine_analysis_order(code_maat_data)
        order = []

        # Start with highest impact areas
        order << "knowledge_silos" if code_maat_data[:authorship][:files_with_single_author] > 0

        order << "coupling_analysis" if code_maat_data[:coupling][:average_coupling] > 3

        order << "high_churn_analysis" if code_maat_data[:churn][:files].any? { |f| f[:changes] > 15 }

        order << "general_quality_analysis"
        order
      end

      def determine_resource_allocation(code_maat_data)
        total_files = code_maat_data[:churn][:total_files]

        {
          high_priority_percentage: 20,
          medium_priority_percentage: 50,
          low_priority_percentage: 30,
          estimated_effort_hours: total_files * 0.5,
          recommended_team_size: [total_files / 50, 1].max
        }
      end

      def assess_analysis_risks(code_maat_data)
        risks = []

        if code_maat_data[:authorship][:files_with_single_author] > code_maat_data[:churn][:total_files] * 0.3
          risks << {
            type: "knowledge_silo_risk",
            severity: "high",
            description: "High percentage of single-author files indicates knowledge silos",
            mitigation: "Implement knowledge sharing and documentation practices"
          }
        end

        if code_maat_data[:coupling][:average_coupling] > 8
          risks << {
            type: "coupling_risk",
            severity: "medium",
            description: "High average coupling indicates tight dependencies",
            mitigation: "Focus on reducing coupling through refactoring"
          }
        end

        risks
      end

      def define_success_metrics(code_maat_data)
        {
          knowledge_silo_reduction: "Reduce single-author files by 50%",
          coupling_reduction: "Reduce average coupling by 30%",
          churn_stabilization: "Reduce high-churn files by 25%",
          documentation_coverage: "Achieve 80% documentation coverage",
          test_coverage: "Achieve 90% test coverage"
        }
      end
    end
  end
end
