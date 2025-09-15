# frozen_string_literal: true

require_relative "lib/aidp/version"

Gem::Specification.new do |s|
  s.name = "aidp"
  s.version = Aidp::VERSION
  s.summary = "A CLI for AI-driven software development, from analysis to execution."
  s.description = "The AI-Dev-Pipeline (AIDP) CLI provides a powerful, markdown-driven workflow for software development. It supports in-depth project analysis to understand existing codebases and an execution mode to systematically implement new features."
  s.authors = ["Bart Agapinan"]
  s.email = ["bart@sonic.next"]
  s.homepage = "https://github.com/viamin/aidp"
  s.license = "MIT"

  s.files = Dir.chdir(__dir__) do
    Dir["bin/*", "lib/**/*.rb", "templates/**/*", "README.md", "LICENSE"]
  end
  s.bindir = "bin"
  s.executables = ["aidp"]
  s.require_paths = ["lib"]
  s.required_ruby_version = ">= 3.0"

  s.add_runtime_dependency "async-job", "~> 0.11"
  s.add_runtime_dependency "cli-ui", "~> 1.0"
  s.add_runtime_dependency "colorize", "~> 1.1"
  s.add_runtime_dependency "csv", "~> 3.2"
  s.add_runtime_dependency "logger", "~> 1.5"
  s.add_runtime_dependency "thor", "~> 1.3"
  # TTY gems removed - replaced with CLI UI components
  s.add_runtime_dependency "ruby_tree_sitter", "~> 2.0"
end
