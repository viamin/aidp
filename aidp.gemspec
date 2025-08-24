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

  s.add_runtime_dependency "colorize", "~> 1.1"
  s.add_runtime_dependency "concurrent-ruby", "~> 1.2"
  s.add_runtime_dependency "csv", "~> 3.2"
  s.add_runtime_dependency "logger", "~> 1.5"
  s.add_runtime_dependency "pg", "~> 1.5"
  s.add_runtime_dependency "que", "~> 2.4"
  s.add_runtime_dependency "sequel", "~> 5.77"
  s.add_runtime_dependency "thor", "~> 1.3"
  s.add_runtime_dependency "tty-box", "~> 0.7"
  s.add_runtime_dependency "tty-cursor", "~> 0.7"
  s.add_runtime_dependency "tty-progressbar", "~> 0.18"
  s.add_runtime_dependency "tty-prompt", "~> 0.23"
  s.add_runtime_dependency "tty-screen", "~> 0.8"
  s.add_runtime_dependency "tty-spinner", "~> 0.9"
  s.add_runtime_dependency "tty-table", "~> 0.12"
end
