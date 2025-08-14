# frozen_string_literal: true

require "erb"
require "json"
require "yaml"

module Aidp
  class ReportGenerator
    # Default report templates
    DEFAULT_TEMPLATES = {
      "analysis_summary" => "templates/COMMON/ANALYSIS_SUMMARY.md.erb",
      "repository_analysis" => "templates/ANALYZE/REPOSITORY_ANALYSIS.md.erb",
      "architecture_analysis" => "templates/ANALYZE/ARCHITECTURE_ANALYSIS.md.erb",
      "functionality_analysis" => "templates/ANALYZE/FUNCTIONALITY_ANALYSIS.md.erb",
      "static_analysis" => "templates/ANALYZE/STATIC_ANALYSIS.md.erb",
      "refactoring_recommendations" => "templates/ANALYZE/REFACTORING_RECOMMENDATIONS.md.erb"
    }.freeze

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = project_dir
      @config = config
      @output_dir = config[:output_dir] || File.join(project_dir, "docs")
      @templates_dir = config[:templates_dir] || File.join(project_dir, "templates")
    end

    # Generate comprehensive analysis report
    def generate_analysis_report(analysis_data, options = {})
      report_data = prepare_report_data(analysis_data)
      template_name = options[:template] || "analysis_summary"

      template_path = find_template(template_name)
      return nil unless template_path

      report_content = render_template(template_path, report_data)
      output_path = save_report(report_content, template_name, options)

      {
        content: report_content,
        path: output_path,
        template: template_name,
        generated_at: Time.now
      }
    end

    # Generate step-specific report
    def generate_step_report(step_name, step_data, options = {})
      report_data = prepare_step_data(step_name, step_data)
      template_name = "#{step_name}_analysis"

      template_path = find_template(template_name)
      return nil unless template_path

      report_content = render_template(template_path, report_data)
      output_path = save_report(report_content, template_name, options)

      {
        content: report_content,
        path: output_path,
        step: step_name,
        generated_at: Time.now
      }
    end

    # Generate executive summary report
    def generate_executive_summary(analysis_data, options = {})
      summary_data = prepare_executive_summary_data(analysis_data)
      template_path = find_template("executive_summary")

      return nil unless template_path

      summary_content = render_template(template_path, summary_data)
      output_path = save_report(summary_content, "executive_summary", options)

      {
        content: summary_content,
        path: output_path,
        type: "executive_summary",
        generated_at: Time.now
      }
    end

    # Generate technical report
    def generate_technical_report(analysis_data, options = {})
      technical_data = prepare_technical_report_data(analysis_data)
      template_path = find_template("technical_report")

      return nil unless template_path

      technical_content = render_template(template_path, technical_data)
      output_path = save_report(technical_content, "technical_report", options)

      {
        content: technical_content,
        path: output_path,
        type: "technical_report",
        generated_at: Time.now
      }
    end

    # Generate comparison report
    def generate_comparison_report(before_data, after_data, options = {})
      comparison_data = prepare_comparison_data(before_data, after_data)
      template_path = find_template("comparison_report")

      return nil unless template_path

      comparison_content = render_template(template_path, comparison_data)
      output_path = save_report(comparison_content, "comparison_report", options)

      {
        content: comparison_content,
        path: output_path,
        type: "comparison_report",
        generated_at: Time.now
      }
    end

    # Generate custom report from template
    def generate_custom_report(template_name, data, options = {})
      template_path = find_template(template_name)
      return nil unless template_path

      report_content = render_template(template_path, data)
      output_path = save_report(report_content, template_name, options)

      {
        content: report_content,
        path: output_path,
        template: template_name,
        generated_at: Time.now
      }
    end

    # Generate report index
    def generate_report_index(reports, options = {})
      index_data = {
        reports: reports,
        generated_at: Time.now,
        project_name: File.basename(@project_dir)
      }

      template_path = find_template("report_index")
      return nil unless template_path

      index_content = render_template(template_path, index_data)
      output_path = save_report(index_content, "report_index", options)

      {
        content: index_content,
        path: output_path,
        type: "report_index",
        generated_at: Time.now
      }
    end

    private

    def prepare_report_data(analysis_data)
      {
        project_name: File.basename(@project_dir),
        project_path: @project_dir,
        analysis_data: analysis_data,
        generated_at: Time.now,
        config: @config,
        metadata: generate_metadata(analysis_data)
      }
    end

    def prepare_step_data(step_name, step_data)
      {
        step_name: step_name,
        step_data: step_data,
        project_name: File.basename(@project_dir),
        project_path: @project_dir,
        generated_at: Time.now,
        config: @config
      }
    end

    def prepare_executive_summary_data(analysis_data)
      {
        project_name: File.basename(@project_dir),
        project_path: @project_dir,
        generated_at: Time.now,
        key_findings: extract_key_findings(analysis_data),
        recommendations: extract_recommendations(analysis_data),
        risk_assessment: assess_risks(analysis_data),
        effort_estimation: estimate_effort(analysis_data)
      }
    end

    def prepare_technical_report_data(analysis_data)
      {
        project_name: File.basename(@project_dir),
        project_path: @project_dir,
        generated_at: Time.now,
        detailed_analysis: analysis_data,
        technical_debt: calculate_technical_debt(analysis_data),
        code_quality_metrics: extract_quality_metrics(analysis_data),
        security_analysis: extract_security_analysis(analysis_data),
        performance_analysis: extract_performance_analysis(analysis_data)
      }
    end

    def prepare_comparison_data(before_data, after_data)
      {
        project_name: File.basename(@project_dir),
        project_path: @project_dir,
        generated_at: Time.now,
        before_analysis: before_data,
        after_analysis: after_data,
        improvements: calculate_improvements(before_data, after_data),
        regressions: identify_regressions(before_data, after_data),
        metrics_comparison: compare_metrics(before_data, after_data)
      }
    end

    def find_template(template_name)
      # Check for custom template first
      custom_template = File.join(@templates_dir, "#{template_name}.md.erb")
      return custom_template if File.exist?(custom_template)

      # Check default templates
      default_template = DEFAULT_TEMPLATES[template_name]
      return File.join(@project_dir, default_template) if default_template && File.exist?(File.join(@project_dir,
        default_template))

      # Check common templates
      common_template = File.join(@project_dir, "templates", "COMMON", "#{template_name}.md.erb")
      return common_template if File.exist?(common_template)

      # Check analyze templates
      analyze_template = File.join(@project_dir, "templates", "ANALYZE", "#{template_name}.md.erb")
      return analyze_template if File.exist?(analyze_template)

      nil
    end

    def render_template(template_path, data)
      template_content = File.read(template_path)
      erb = ERB.new(template_content, trim_mode: "-")
      erb.result(binding)
    end

    def save_report(content, report_type, options)
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      filename = options[:filename] || "#{report_type}_#{timestamp}.md"
      output_path = File.join(@output_dir, filename)

      # Ensure output directory exists
      FileUtils.mkdir_p(@output_dir)

      # Write report content
      File.write(output_path, content)

      output_path
    end

    def generate_metadata(analysis_data)
      {
        total_files_analyzed: count_analyzed_files(analysis_data),
        analysis_duration: calculate_analysis_duration(analysis_data),
        tools_used: extract_tools_used(analysis_data),
        languages_detected: extract_languages(analysis_data),
        frameworks_detected: extract_frameworks(analysis_data)
      }
    end

    def extract_key_findings(analysis_data)
      findings = []

      # Extract findings from different analysis types
      if analysis_data[:repository_analysis]
        findings.concat(extract_repository_findings(analysis_data[:repository_analysis]))
      end

      if analysis_data[:architecture_analysis]
        findings.concat(extract_architecture_findings(analysis_data[:architecture_analysis]))
      end

      if analysis_data[:static_analysis]
        findings.concat(extract_static_analysis_findings(analysis_data[:static_analysis]))
      end

      # Prioritize findings by severity
      findings.sort_by { |finding| finding[:severity] || "medium" }
    end

    def extract_recommendations(analysis_data)
      recommendations = []

      # Extract recommendations from different analysis types
      recommendations.concat(analysis_data[:refactoring_recommendations]) if analysis_data[:refactoring_recommendations]

      if analysis_data[:modernization_recommendations]
        recommendations.concat(analysis_data[:modernization_recommendations])
      end

      # Prioritize recommendations by impact
      recommendations.sort_by { |rec| rec[:impact] || "medium" }
    end

    def assess_risks(analysis_data)
      risks = []

      # Assess security risks
      risks.concat(assess_security_risks(analysis_data[:security_analysis])) if analysis_data[:security_analysis]

      # Assess technical debt risks
      if analysis_data[:technical_debt_analysis]
        risks.concat(assess_technical_debt_risks(analysis_data[:technical_debt_analysis]))
      end

      # Assess maintenance risks
      if analysis_data[:maintenance_analysis]
        risks.concat(assess_maintenance_risks(analysis_data[:maintenance_analysis]))
      end

      risks
    end

    def estimate_effort(analysis_data)
      effort = {
        refactoring_effort: estimate_refactoring_effort(analysis_data),
        modernization_effort: estimate_modernization_effort(analysis_data),
        testing_effort: estimate_testing_effort(analysis_data),
        documentation_effort: estimate_documentation_effort(analysis_data)
      }

      effort[:total_effort] = effort.values.sum
      effort
    end

    def calculate_technical_debt(analysis_data)
      debt = {
        code_quality_debt: calculate_code_quality_debt(analysis_data),
        architecture_debt: calculate_architecture_debt(analysis_data),
        testing_debt: calculate_testing_debt(analysis_data),
        documentation_debt: calculate_documentation_debt(analysis_data),
        security_debt: calculate_security_debt(analysis_data)
      }

      debt[:total_debt] = debt.values.sum
      debt
    end

    def extract_quality_metrics(analysis_data)
      metrics = {}

      if analysis_data[:static_analysis]
        metrics[:code_quality] = extract_code_quality_metrics(analysis_data[:static_analysis])
      end

      if analysis_data[:test_coverage]
        metrics[:test_coverage] = extract_test_coverage_metrics(analysis_data[:test_coverage])
      end

      if analysis_data[:complexity_analysis]
        metrics[:complexity] = extract_complexity_metrics(analysis_data[:complexity_analysis])
      end

      metrics
    end

    def extract_security_analysis(analysis_data)
      security = {}

      if analysis_data[:security_scan]
        security[:vulnerabilities] = analysis_data[:security_scan][:vulnerabilities] || []
        security[:risk_level] = analysis_data[:security_scan][:risk_level] || "unknown"
      end

      if analysis_data[:dependency_analysis]
        security[:dependency_vulnerabilities] = analysis_data[:dependency_analysis][:vulnerabilities] || []
      end

      security
    end

    def extract_performance_analysis(analysis_data)
      performance = {}

      if analysis_data[:performance_analysis]
        performance[:bottlenecks] = analysis_data[:performance_analysis][:bottlenecks] || []
        performance[:optimization_opportunities] = analysis_data[:performance_analysis][:optimizations] || []
      end

      performance
    end

    def calculate_improvements(before_data, after_data)
      improvements = []

      # Compare metrics
      before_metrics = extract_metrics(before_data)
      after_metrics = extract_metrics(after_data)

      after_metrics.each do |metric, value|
        before_value = before_metrics[metric]
        next unless before_value && value > before_value

        improvements << {
          metric: metric,
          improvement: value - before_value,
          percentage: ((value - before_value) / before_value * 100).round(2)
        }
      end

      improvements
    end

    def identify_regressions(before_data, after_data)
      regressions = []

      # Compare metrics
      before_metrics = extract_metrics(before_data)
      after_metrics = extract_metrics(after_data)

      after_metrics.each do |metric, value|
        before_value = before_metrics[metric]
        next unless before_value && value < before_value

        regressions << {
          metric: metric,
          regression: before_value - value,
          percentage: ((before_value - value) / before_value * 100).round(2)
        }
      end

      regressions
    end

    def compare_metrics(before_data, after_data)
      comparison = {}

      before_metrics = extract_metrics(before_data)
      after_metrics = extract_metrics(after_data)

      all_metrics = (before_metrics.keys + after_metrics.keys).uniq

      all_metrics.each do |metric|
        comparison[metric] = {
          before: before_metrics[metric],
          after: after_metrics[metric],
          change: (after_metrics[metric] && before_metrics[metric]) ? after_metrics[metric] - before_metrics[metric] : nil
        }
      end

      comparison
    end

    # Helper methods for data extraction
    def count_analyzed_files(analysis_data)
      count = 0
      analysis_data.each_value do |data|
        count += data[:files_analyzed] if data.is_a?(Hash) && data[:files_analyzed]
      end
      count
    end

    def calculate_analysis_duration(analysis_data)
      duration = 0
      analysis_data.each_value do |data|
        duration += data[:duration] if data.is_a?(Hash) && data[:duration]
      end
      duration
    end

    def extract_tools_used(analysis_data)
      tools = []
      analysis_data.each_value do |data|
        tools.concat(data[:tools_used]) if data.is_a?(Hash) && data[:tools_used]
      end
      tools.uniq
    end

    def extract_languages(analysis_data)
      languages = []
      analysis_data.each_value do |data|
        languages << data[:language] if data.is_a?(Hash) && data[:language]
      end
      languages.uniq
    end

    def extract_frameworks(analysis_data)
      frameworks = []
      analysis_data.each_value do |data|
        frameworks << data[:framework] if data.is_a?(Hash) && data[:framework]
      end
      frameworks.uniq
    end

    def extract_metrics(data)
      metrics = {}

      if data.is_a?(Hash)
        data.each do |key, value|
          if value.is_a?(Numeric)
            metrics[key] = value
          elsif value.is_a?(Hash)
            metrics.merge!(extract_metrics(value))
          end
        end
      end

      metrics
    end

    # Placeholder methods for specific analysis extractions
    def extract_repository_findings(data)
      data[:findings] || []
    end

    def extract_architecture_findings(data)
      data[:findings] || []
    end

    def extract_static_analysis_findings(data)
      data[:findings] || []
    end

    def assess_security_risks(data)
      data[:risks] || []
    end

    def assess_technical_debt_risks(data)
      data[:risks] || []
    end

    def assess_maintenance_risks(data)
      data[:risks] || []
    end

    def estimate_refactoring_effort(data)
      data[:effort] || 0
    end

    def estimate_modernization_effort(data)
      data[:effort] || 0
    end

    def estimate_testing_effort(data)
      data[:effort] || 0
    end

    def estimate_documentation_effort(data)
      data[:effort] || 0
    end

    def calculate_code_quality_debt(data)
      data[:debt] || 0
    end

    def calculate_architecture_debt(data)
      data[:debt] || 0
    end

    def calculate_testing_debt(data)
      data[:debt] || 0
    end

    def calculate_documentation_debt(data)
      data[:debt] || 0
    end

    def calculate_security_debt(data)
      data[:debt] || 0
    end

    def extract_code_quality_metrics(data)
      data[:metrics] || {}
    end

    def extract_test_coverage_metrics(data)
      data[:metrics] || {}
    end

    def extract_complexity_metrics(data)
      data[:metrics] || {}
    end
  end
end
