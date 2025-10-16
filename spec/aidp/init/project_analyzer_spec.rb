# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Init::ProjectAnalyzer do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:project_path) { tmp_dir }
  let(:analyzer) { described_class.new(project_path) }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#analyze" do
    context "with a Rails project" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "lib"))
        FileUtils.mkdir_p(File.join(project_path, "spec"))
        FileUtils.mkdir_p(File.join(project_path, "config"))

        File.write(File.join(project_path, "lib", "sample.rb"), "class Sample; end\n")
        File.write(File.join(project_path, "spec", "sample_spec.rb"), "RSpec.describe Sample do; end\n")
        File.write(File.join(project_path, ".rubocop.yml"), "inherit_mode: merge\n")

        File.write(File.join(project_path, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "rails"
          gem "rspec"
        GEMFILE

        File.write(File.join(project_path, "config", "application.rb"), "require 'rails'\nmodule Demo; class Application < Rails::Application; end; end\n")
      end

      it "detects languages" do
        analysis = analyzer.analyze

        expect(analysis[:languages].keys).to include("Ruby")
      end

      it "detects Rails framework with high confidence and evidence" do
        analysis = analyzer.analyze
        rails_detection = analysis[:frameworks].find { |f| f[:name] == "Rails" }

        expect(rails_detection).not_to be_nil
        expect(rails_detection[:confidence]).to be >= 0.7
        expect(rails_detection[:evidence]).not_to be_empty
        expect(rails_detection[:evidence].join(" ")).to include("config/application.rb")
      end

      it "detects RSpec test framework with confidence and evidence" do
        analysis = analyzer.analyze
        rspec_detection = analysis[:test_frameworks].find { |t| t[:name] == "RSpec" }

        expect(rspec_detection).not_to be_nil
        expect(rspec_detection[:confidence]).to be >= 0.7
        expect(rspec_detection[:evidence]).not_to be_empty
      end

      it "detects RuboCop tooling with confidence and evidence" do
        analysis = analyzer.analyze
        rubocop_detection = analysis[:tooling].find { |t| t[:tool] == :rubocop }

        expect(rubocop_detection).not_to be_nil
        expect(rubocop_detection[:confidence]).to be >= 0.7
        expect(rubocop_detection[:evidence]).to include("Found config files: .rubocop.yml")
      end

      it "detects config files" do
        analysis = analyzer.analyze

        expect(analysis[:config_files]).to include(".rubocop.yml")
        expect(analysis[:config_files]).to include("Gemfile")
      end

      it "detects key directories" do
        analysis = analyzer.analyze

        expect(analysis[:key_directories]).to include("lib")
        expect(analysis[:key_directories]).to include("spec")
        expect(analysis[:key_directories]).to include("config")
      end

      it "summarises repository stats" do
        stats = analyzer.analyze[:repo_stats]
        expect(stats[:total_files]).to be > 0
        expect(stats[:total_directories]).to be > 0
      end
    end

    context "with a React project" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "src"))
        File.write(File.join(project_path, "src", "App.jsx"), "import React from 'react'; function App() { return <div>Hello</div>; }\n")
        File.write(File.join(project_path, "package.json"), <<~JSON)
          {
            "name": "demo-app",
            "dependencies": {
              "react": "^18.0.0",
              "react-dom": "^18.0.0"
            },
            "scripts": {
              "test": "jest"
            }
          }
        JSON
      end

      it "detects JavaScript language" do
        analysis = analyzer.analyze

        expect(analysis[:languages].keys).to include("JavaScript")
      end

      it "detects React framework with confidence and evidence" do
        analysis = analyzer.analyze
        react_detection = analysis[:frameworks].find { |f| f[:name] == "React" }

        expect(react_detection).not_to be_nil
        expect(react_detection[:confidence]).to be >= 0.7
        expect(react_detection[:evidence].join(" ")).to include("package.json")
        expect(react_detection[:evidence].join(" ")).to match(/react/)
      end

      it "detects Jest from package.json scripts" do
        analysis = analyzer.analyze
        jest_detection = analysis[:tooling].find { |t| t[:tool] == :jest }

        expect(jest_detection).not_to be_nil
        expect(jest_detection[:confidence]).to be > 0
        expect(jest_detection[:evidence].join(" ")).to include("package.json")
      end
    end

    context "with no framework present" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "lib"))
        File.write(File.join(project_path, "lib", "sample.rb"), "class Sample; end\n")
        File.write(File.join(project_path, "Gemfile"), "source 'https://rubygems.org'\ngem 'rake'\n")
      end

      it "returns empty frameworks array when no frameworks detected" do
        analysis = analyzer.analyze

        expect(analysis[:frameworks]).to be_empty
      end

      it "does not falsely detect frameworks from generic patterns" do
        analysis = analyzer.analyze

        # Should not detect Rails, React, Django, etc. just because Gemfile exists
        framework_names = analysis[:frameworks].map { |f| f[:name] }
        expect(framework_names).not_to include("Rails")
        expect(framework_names).not_to include("React")
        expect(framework_names).not_to include("Django")
        expect(framework_names).not_to include("Flask")
      end
    end

    context "with Django project" do
      before do
        File.write(File.join(project_path, "manage.py"), "#!/usr/bin/env python\nimport django\n")
        File.write(File.join(project_path, "requirements.txt"), "Django==4.0\npsycopg2==2.9\n")
      end

      it "detects Django with confidence and evidence" do
        analysis = analyzer.analyze
        django_detection = analysis[:frameworks].find { |f| f[:name] == "Django" }

        expect(django_detection).not_to be_nil
        expect(django_detection[:confidence]).to be >= 0.7
        expect(django_detection[:evidence]).not_to be_empty
      end
    end

    context "with ambiguous evidence" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "lib"))
        File.write(File.join(project_path, "lib", "sample.rb"), "# A sample Ruby file\n")
        # Create package.json but only mention react in comments
        File.write(File.join(project_path, "package.json"), <<~JSON)
          {
            "name": "demo-tools",
            "description": "Tools that work with react projects",
            "dependencies": {
              "lodash": "^4.0.0"
            }
          }
        JSON
      end

      it "detects React with lower confidence when only weak evidence exists" do
        analysis = analyzer.analyze
        react_detection = analysis[:frameworks].find { |f| f[:name] == "React" }

        if react_detection
          # If detected, confidence should be lower due to weak evidence
          expect(react_detection[:confidence]).to be < 0.7
        else
          # Or it might not be detected at all, which is also acceptable
          expect(react_detection).to be_nil
        end
      end
    end

    context "with explain_detection option" do
      it "accepts explain_detection option" do
        analysis = analyzer.analyze(explain_detection: true)

        expect(analysis).to have_key(:languages)
        expect(analysis).to have_key(:frameworks)
        expect(analysis).to have_key(:test_frameworks)
        expect(analysis).to have_key(:tooling)
      end
    end

    describe "confidence scoring" do
      context "with strong evidence (file + content match)" do
        before do
          FileUtils.mkdir_p(File.join(project_path, "config"))
          File.write(File.join(project_path, "config", "application.rb"), "require 'rails'\nRails.application\n")
        end

        it "assigns high confidence (>= 0.7)" do
          analysis = analyzer.analyze
          rails_detection = analysis[:frameworks].find { |f| f[:name] == "Rails" }

          expect(rails_detection[:confidence]).to be >= 0.7
        end
      end

      context "with weak evidence (file only, no content match)" do
        before do
          FileUtils.mkdir_p(File.join(project_path, "config"))
          File.write(File.join(project_path, "config", "application.rb"), "# Just a config file\n")
        end

        it "assigns lower confidence or no detection" do
          analysis = analyzer.analyze
          rails_detection = analysis[:frameworks].find { |f| f[:name] == "Rails" }

          if rails_detection
            expect(rails_detection[:confidence]).to be < 0.7
          else
            expect(rails_detection).to be_nil
          end
        end
      end
    end

    describe "sorting behavior" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "config"))
        File.write(File.join(project_path, "config", "application.rb"), "require 'rails'\nRails.application\n")
        File.write(File.join(project_path, "Gemfile"), "gem 'rails'\ngem 'sinatra'\n")
        File.write(File.join(project_path, "config.ru"), "require 'sinatra'\nrun Sinatra::Application\n")
      end

      it "sorts frameworks by confidence (descending) then name" do
        analysis = analyzer.analyze
        frameworks = analysis[:frameworks]

        # Should be sorted by confidence descending
        confidences = frameworks.map { |f| f[:confidence] }
        expect(confidences).to eq(confidences.sort.reverse)
      end
    end

    describe "test framework detection" do
      context "with RSpec via directory and dependency" do
        before do
          FileUtils.mkdir_p(File.join(project_path, "spec"))
          File.write(File.join(project_path, "Gemfile"), "gem 'rspec'\n")
          File.write(File.join(project_path, "spec", "sample_spec.rb"), "RSpec.describe 'test'\n")
        end

        it "detects RSpec with high confidence" do
          analysis = analyzer.analyze
          rspec = analysis[:test_frameworks].find { |t| t[:name] == "RSpec" }

          expect(rspec).not_to be_nil
          expect(rspec[:confidence]).to be >= 0.7
          expect(rspec[:evidence].size).to be >= 2  # Directory + dependency
        end
      end

      context "with Jest from package.json" do
        before do
          File.write(File.join(project_path, "package.json"), <<~JSON)
            {
              "devDependencies": {
                "jest": "^29.0.0"
              }
            }
          JSON
        end

        it "detects Jest test framework" do
          analysis = analyzer.analyze
          jest = analysis[:test_frameworks].find { |t| t[:name] == "Jest" }

          expect(jest).not_to be_nil
          expect(jest[:confidence]).to be > 0
        end
      end
    end

    describe "tooling detection" do
      context "with eslint config and package.json scripts" do
        before do
          File.write(File.join(project_path, ".eslintrc"), "{}\n")
          File.write(File.join(project_path, "package.json"), <<~JSON)
            {
              "scripts": {
                "lint": "eslint src/**/*.js"
              }
            }
          JSON
        end

        it "detects eslint with high confidence and multiple evidence sources" do
          analysis = analyzer.analyze
          eslint = analysis[:tooling].find { |t| t[:tool] == :eslint }

          expect(eslint).not_to be_nil
          expect(eslint[:confidence]).to be >= 0.7
          expect(eslint[:evidence].size).to be >= 2  # Config + script reference
        end
      end
    end
  end
end
