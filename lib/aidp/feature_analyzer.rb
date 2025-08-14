# frozen_string_literal: true

require "fileutils"

module Aidp
  class FeatureAnalyzer
    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
    end

    # Detect and categorize features in the codebase
    def detect_features
      features = []

      # Scan directories for potential features
      scan_directories_for_features(features)

      # Scan files for feature indicators
      scan_files_for_features(features)

      # Analyze feature relationships
      analyze_feature_relationships(features)

      # Categorize features
      categorize_features(features)

      features
    end

    # Get feature-specific agent recommendations
    def get_feature_agent_recommendations(feature)
      {
        feature: feature[:name],
        primary_agent: determine_primary_agent(feature),
        specialized_agents: determine_specialized_agents(feature),
        analysis_priority: determine_analysis_priority(feature)
      }
    end

    # Coordinate multi-agent analysis for a feature
    def coordinate_feature_analysis(feature)
      agents = get_feature_agent_recommendations(feature)

      {
        feature: feature[:name],
        primary_analysis: {
          agent: agents[:primary_agent],
          focus_areas: get_agent_focus_areas(agents[:primary_agent]),
          output_files: generate_output_files(feature, agents[:primary_agent])
        },
        specialized_analyses: agents[:specialized_agents].map do |agent|
          {
            agent: agent,
            focus_areas: get_agent_focus_areas(agent),
            output_files: generate_output_files(feature, agent)
          }
        end,
        coordination_notes: generate_coordination_notes(feature, agents)
      }
    end

    private

    def scan_directories_for_features(features)
      # Common feature directory patterns
      feature_patterns = [
        "features/", "modules/", "components/", "services/",
        "controllers/", "models/", "views/", "api/",
        "handlers/", "processors/", "managers/", "utils/"
      ]

      feature_patterns.each do |pattern|
        pattern_path = File.join(@project_dir, pattern)
        next unless Dir.exist?(pattern_path)

        Dir.entries(pattern_path).each do |entry|
          next if entry.start_with?(".") || entry == ".."

          feature_path = File.join(pattern_path, entry)
          next unless Dir.exist?(feature_path)

          features << {
            name: entry || "unknown",
            type: "directory",
            path: feature_path,
            category: infer_category_from_path(pattern, entry),
            complexity: estimate_complexity(feature_path)
          }
        end
      end
    end

    def scan_files_for_features(features)
      # Scan for feature indicators in files
      feature_indicators = [
        "class.*Controller", "class.*Service", "class.*Manager",
        "module.*Feature", "def.*feature", "function.*feature"
      ]

      Dir.glob(File.join(@project_dir, "**", "*.rb")).each do |file|
        next if file.include?("spec/") || file.include?("test/")

        content = File.read(file)
        feature_found = false

        feature_indicators.each do |indicator|
          next unless content.match?(/#{indicator}/i)

          feature_name = extract_feature_name(file, content, indicator)
          features << {
            name: feature_name,
            type: "file",
            path: file,
            category: infer_category_from_file(file, content),
            complexity: estimate_file_complexity(content)
          }
          feature_found = true
          break
        end

        # If no specific pattern matched, add the file as a feature using filename
        next if feature_found

        feature_name = File.basename(file, ".*").capitalize
        features << {
          name: feature_name,
          type: "file",
          path: file,
          category: infer_category_from_file(file, content),
          complexity: estimate_file_complexity(content)
        }
      end
    end

    def analyze_feature_relationships(features)
      features.each do |feature|
        feature[:dependencies] = find_feature_dependencies(feature)
        feature[:dependents] = find_feature_dependents(feature, features)
        feature[:coupling] = calculate_coupling_score(feature)
      end
    end

    def categorize_features(features)
      features.each do |feature|
        feature[:category] ||= infer_category(feature)
        feature[:priority] = calculate_priority(feature)
        feature[:business_value] = estimate_business_value(feature)
        feature[:technical_debt] = estimate_technical_debt(feature)
      end
    end

    def determine_primary_agent(feature)
      case feature[:category]
      when "core_business"
        "Functionality Analyst"
      when "api"
        "Architecture Analyst"
      when "data"
        "Functionality Analyst"
      when "ui"
        "Functionality Analyst"
      when "utility"
        "Static Analysis Expert"
      else
        "Functionality Analyst"
      end
    end

    def determine_specialized_agents(feature)
      agents = []

      # Add specialized agents based on feature characteristics
      agents << "Test Analyst" if feature[:complexity] > 5
      agents << "Architecture Analyst" if feature[:coupling] > 0.7
      agents << "Documentation Analyst" if feature[:business_value] > 0.8
      agents << "Refactoring Specialist" if feature[:technical_debt] > 0.6

      agents.uniq
    end

    def determine_analysis_priority(feature)
      # Calculate priority based on business value, complexity, and technical debt
      priority_score = (
        feature[:business_value] * 0.4 +
        feature[:complexity] * 0.3 +
        feature[:technical_debt] * 0.3
      )

      case priority_score
      when 0.8..1.0
        "high"
      when 0.5..0.8
        "medium"
      else
        "low"
      end
    end

    def get_agent_focus_areas(agent_name)
      case agent_name
      when "Functionality Analyst"
        %w[feature_mapping complexity_analysis dead_code_identification]
      when "Architecture Analyst"
        %w[dependency_analysis coupling_assessment design_patterns]
      when "Test Analyst"
        %w[test_coverage test_quality testing_gaps]
      when "Documentation Analyst"
        %w[documentation_gaps documentation_quality user_needs]
      when "Static Analysis Expert"
        %w[code_quality tool_integration best_practices]
      when "Refactoring Specialist"
        %w[technical_debt code_smells refactoring_opportunities]
      else
        ["general_analysis"]
      end
    end

    def generate_output_files(feature, agent_name)
      base_name = (feature[:name] || "unknown").downcase.gsub(/[^a-z0-9]/, "_")
      agent_suffix = agent_name.downcase.gsub(/\s+/, "_")

      {
        primary: "docs/#{base_name}_#{agent_suffix}_analysis.md",
        secondary: "docs/#{base_name}_#{agent_suffix}_details.md",
        data: "docs/#{base_name}_#{agent_suffix}_data.json"
      }
    end

    def generate_coordination_notes(feature, agents)
      notes = []

      notes << "Feature: #{feature[:name] || "unknown"} (#{feature[:category] || "unknown"})"
      notes << "Primary Agent: #{agents[:primary_agent]}"
      notes << "Specialized Agents: #{agents[:specialized_agents].join(", ")}"
      notes << "Priority: #{agents[:analysis_priority]}"
      notes << "Focus Areas: #{get_agent_focus_areas(agents[:primary_agent]).join(", ")}"

      notes.join("\n")
    end

    def infer_category_from_path(pattern, entry)
      case pattern
      when "controllers/"
        "api"
      when "models/"
        "data"
      when "views/"
        "ui"
      when "services/"
        "core_business"
      when "utils/"
        "utility"
      else
        "core_business"
      end
    end

    def infer_category_from_file(file, content)
      if content.match?(/class.*Controller/i)
        "api"
      elsif content.match?(/class.*Model/i)
        "data"
      elsif content.match?(/class.*Service/i)
        "core_business"
      elsif content.match?(/class.*Util/i)
        "utility"
      else
        "core_business"
      end
    end

    def infer_category(feature)
      # Default categorization logic
      if feature[:name]&.match?(/controller|api|endpoint/i)
        "api"
      elsif feature[:name]&.match?(/model|data|entity/i)
        "data"
      elsif feature[:name]&.match?(/view|ui|component/i)
        "ui"
      elsif feature[:name]&.match?(/util|helper|tool/i)
        "utility"
      else
        "core_business"
      end
    end

    def estimate_complexity(path)
      # Simple complexity estimation based on file count and size
      file_count = Dir.glob(File.join(path, "**", "*.rb")).count
      total_lines = Dir.glob(File.join(path, "**", "*.rb")).sum { |f| File.readlines(f).count }

      complexity = (file_count * 0.3 + total_lines / 100.0 * 0.7).clamp(0, 10)
      (complexity / 10.0).round(2)
    end

    def estimate_file_complexity(content)
      # Simple complexity estimation based on lines of code
      lines = content.lines.count
      complexity = (lines / 50.0).clamp(0, 10)
      (complexity / 10.0).round(2)
    end

    def find_feature_dependencies(feature)
      # Simplified dependency detection
      dependencies = []

      if feature[:type] == "file"
        content = File.read(feature[:path])
        # Look for require/import statements
        content.scan(/require\s+['"]([^'"]+)['"]/).each do |match|
          dependencies << match[0]
        end
      end

      dependencies
    end

    def find_feature_dependents(feature, all_features)
      # Find features that depend on this feature
      dependents = []

      all_features.each do |other_feature|
        dependents << other_feature[:name] if other_feature[:dependencies]&.include?(feature[:name])
      end

      dependents
    end

    def calculate_coupling_score(feature)
      # Calculate coupling based on dependencies and dependents
      dependency_count = feature[:dependencies]&.count || 0
      dependent_count = feature[:dependents]&.count || 0

      coupling = (dependency_count + dependent_count) / 10.0
      coupling.clamp(0, 1).round(2)
    end

    def calculate_priority(feature)
      # Calculate priority based on business value and complexity
      business_value = feature[:business_value] || 0.5
      complexity = feature[:complexity] || 0.5

      priority = (business_value * 0.7 + complexity * 0.3)
      priority.clamp(0, 1).round(2)
    end

    def estimate_business_value(feature)
      # Simple business value estimation based on category and name
      base_value = case feature[:category]
      when "core_business"
        0.9
      when "api"
        0.8
      when "data"
        0.7
      when "ui"
        0.6
      when "utility"
        0.3
      else
        0.5
      end

      # Adjust based on feature name indicators
      if feature[:name]&.match?(/user|auth|payment|order/i)
        base_value += 0.1
      elsif feature[:name]&.match?(/util|helper|tool/i)
        base_value -= 0.1
      end

      base_value.clamp(0, 1).round(2)
    end

    def estimate_technical_debt(feature)
      # Simple technical debt estimation based on complexity and coupling
      complexity = feature[:complexity] || 0.5
      coupling = feature[:coupling] || 0.5

      technical_debt = (complexity * 0.6 + coupling * 0.4)
      technical_debt.clamp(0, 1).round(2)
    end

    def extract_feature_name(file, content, indicator)
      # Extract feature name from file content
      if content.match?(/class\s+(\w+)/)
        ::Regexp.last_match(1)
      elsif content.match?(/module\s+(\w+)/)
        ::Regexp.last_match(1)
      else
        File.basename(file, ".*").capitalize
      end
    rescue
      # Fallback to filename if extraction fails
      File.basename(file, ".*").capitalize
    end
  end
end
