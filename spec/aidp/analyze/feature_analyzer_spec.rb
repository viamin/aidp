# frozen_string_literal: true

require "spec_helper"
require "aidp/analyze/feature_analyzer"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::FeatureAnalyzer do
  let(:temp_dir) { Dir.mktmpdir }
  let(:analyzer) { described_class.new(temp_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  describe "#initialize" do
    it "accepts a project directory" do
      expect { described_class.new(temp_dir) }.not_to raise_error
    end

    it "defaults to current directory" do
      analyzer = described_class.new
      expect(analyzer.instance_variable_get(:@project_dir)).to eq(Dir.pwd)
    end
  end

  describe "#detect_features" do
    context "with feature directories" do
      before do
        FileUtils.mkdir_p(File.join(temp_dir, "features", "authentication"))
        FileUtils.mkdir_p(File.join(temp_dir, "services", "payment"))
      end

      it "detects features from directory structure" do
        features = analyzer.detect_features
        expect(features).to be_an(Array)
      end

      it "returns feature information" do
        features = analyzer.detect_features
        expect(features.first).to have_key(:name) if features.any?
      end
    end

    context "with empty project" do
      it "returns empty array" do
        features = analyzer.detect_features
        expect(features).to eq([])
      end
    end
  end

  describe "#get_feature_agent_recommendations" do
    let(:feature) do
      {
        name: "authentication",
        type: "directory",
        category: "security",
        complexity: 5,
        coupling: 0.5,
        business_value: 0.7,
        technical_debt: 0.4
      }
    end

    it "returns agent recommendations" do
      recommendations = analyzer.get_feature_agent_recommendations(feature)
      expect(recommendations).to be_a(Hash)
      expect(recommendations).to have_key(:feature)
      expect(recommendations).to have_key(:primary_agent)
    end

    it "includes specialized agents" do
      recommendations = analyzer.get_feature_agent_recommendations(feature)
      expect(recommendations).to have_key(:specialized_agents)
    end

    it "includes analysis priority" do
      recommendations = analyzer.get_feature_agent_recommendations(feature)
      expect(recommendations).to have_key(:analysis_priority)
    end
  end

  describe "#coordinate_feature_analysis" do
    let(:feature) do
      {
        name: "authentication",
        type: "directory",
        category: "security",
        complexity: 5,
        coupling: 0.5,
        business_value: 0.7,
        technical_debt: 0.4
      }
    end

    it "coordinates multi-agent analysis" do
      analysis = analyzer.coordinate_feature_analysis(feature)
      expect(analysis).to be_a(Hash)
      expect(analysis).to have_key(:feature)
    end

    it "includes primary analysis" do
      analysis = analyzer.coordinate_feature_analysis(feature)
      expect(analysis).to have_key(:primary_analysis)
      expect(analysis[:primary_analysis]).to have_key(:agent)
    end

    it "includes specialized analyses" do
      analysis = analyzer.coordinate_feature_analysis(feature)
      expect(analysis).to have_key(:specialized_analyses)
      expect(analysis[:specialized_analyses]).to be_an(Array)
    end

    it "includes coordination notes" do
      analysis = analyzer.coordinate_feature_analysis(feature)
      expect(analysis).to have_key(:coordination_notes)
    end
  end
end
