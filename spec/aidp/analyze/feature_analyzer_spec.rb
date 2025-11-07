# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "aidp/analyze/feature_analyzer"

RSpec.describe Aidp::FeatureAnalyzer do
  let(:project_dir) { Dir.mktmpdir }
  let(:analyzer) { described_class.new(project_dir) }

  before do
    FileUtils.mkdir_p(File.join(project_dir, "features", "payments"))
    FileUtils.mkdir_p(File.join(project_dir, "controllers", "orders"))
    FileUtils.mkdir_p(File.join(project_dir, "lib"))

    File.write(File.join(project_dir, "features", "payments", "handler.rb"), <<~RUBY)
      class PaymentsHandler
      end
    RUBY

    File.write(File.join(project_dir, "controllers", "orders", "orders_controller.rb"), <<~RUBY)
      class OrdersController
        def index; end
      end
    RUBY

    File.write(File.join(project_dir, "lib", "billing_manager.rb"), <<~RUBY)
      require "json"
      class BillingManager
        def call; end
      end
    RUBY

    File.write(File.join(project_dir, "lib", "utility.rb"), "module HelperTool; end")
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#detect_features" do
    it "discovers directory and file based features with metadata" do
      features = analyzer.detect_features

      directory_feature = features.find { |f| f[:type] == "directory" && f[:name] == "payments" }
      file_feature = features.find { |f| f[:path].end_with?("billing_manager.rb") }

      expect(directory_feature).to include(category: "core_business")
      expect(file_feature[:dependencies]).to include("json")
      expect(file_feature[:category]).to eq("core_business")
      expect(file_feature[:complexity]).to be >= 0
      expect(file_feature[:business_value]).to be_between(0, 1)
      expect(file_feature[:technical_debt]).to be_between(0, 1)
    end
  end

  describe "#get_feature_agent_recommendations" do
    it "returns priority and specialized agents" do
      feature = {
        name: "Payments API",
        category: "api",
        complexity: 6,
        coupling: 0.9,
        business_value: 0.9,
        technical_debt: 0.7
      }

      result = analyzer.get_feature_agent_recommendations(feature)

      expect(result[:primary_agent]).to eq("Architecture Analyst")
      expect(result[:specialized_agents]).to include("Test Analyst", "Architecture Analyst", "Documentation Analyst", "Refactoring Specialist")
      expect(result[:analysis_priority]).to eq("low")
    end
  end

  describe "#coordinate_feature_analysis" do
    it "builds structured plan for primary and specialized agents" do
      feature = {
        name: "OrdersController",
        category: "api",
        complexity: 0.8,
        coupling: 0.2,
        business_value: 0.9,
        technical_debt: 0.2
      }

      plan = analyzer.coordinate_feature_analysis(feature)

      expect(plan[:primary_analysis][:output_files][:primary]).to match(/orderscontroller/)
      expect(plan[:specialized_analyses]).to all(include(:focus_areas, :output_files))
      expect(plan[:coordination_notes]).to include("Feature:", "Primary Agent:")
    end
  end
end
