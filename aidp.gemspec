# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "aidp"
  s.version = File.read(File.expand_path("lib/aidp/version.rb", __dir__)).match(/VERSION = "([^"]+)"/)[1]
  s.summary = "AI Dev Pipeline CLI that drives prompts via Cursor/Claude/Gemini"
  s.description = "Portable CLI to run a markdown-based AI dev workflow without copying prompts into projects."
  s.authors = ["Bart Agapinan"]
  s.email = ["bart@sonic.next"]
  s.homepage = "https://github.com/viamin/ai-scaffold"
  s.license = "MIT"

  s.files = Dir.chdir(__dir__) do
    Dir["bin/*", "lib/**/*.rb", "templates/**/*", "README.md", "LICENSE"]
  end
  s.bindir = "bin"
  s.executables = ["aidp"]
  s.require_paths = ["lib"]
  s.required_ruby_version = ">= 3.0"

  s.add_runtime_dependency "thor", "~> 1.3"
  s.add_runtime_dependency "tty-prompt", "~> 0.23"

  s.add_development_dependency "rspec", "~> 3.12"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "standard", "~> 1.0"
end
