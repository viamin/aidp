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
    Dir["exe/*", "lib/**/*.rb", "templates/**/*", "README.md", "LICENSE"]
  end
  s.bindir = "exe"
  s.executables = ["aidp"]
  s.require_paths = ["lib"]
  s.required_ruby_version = ">= 3.3"

  s.add_runtime_dependency "concurrent-ruby", "~> 1.3"
  s.add_runtime_dependency "csv", "~> 3.2"
  s.add_runtime_dependency "logger", "~> 1.5"
  s.add_runtime_dependency "thor", "~> 1.3"
  s.add_runtime_dependency "tty-cursor", "~> 0.7"
  s.add_runtime_dependency "tty-screen", "~> 0.8"
  s.add_runtime_dependency "tty-reader", "~> 0.9"
  s.add_runtime_dependency "tty-box", "~> 0.7"
  s.add_runtime_dependency "tty-table", "~> 0.12"
  s.add_runtime_dependency "tty-progressbar", "~> 0.18"
  s.add_runtime_dependency "tty-spinner", "~> 0.9"
  s.add_runtime_dependency "tty-prompt", "~> 0.23"
  s.add_runtime_dependency "pastel", "~> 0.8"
  s.add_runtime_dependency "ruby_tree_sitter", "~> 2.0"
  s.add_runtime_dependency "tty-command", "~> 0.10"
  s.add_runtime_dependency "ruby_llm", "~> 1.9"
end
