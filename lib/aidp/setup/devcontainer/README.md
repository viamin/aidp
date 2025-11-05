# Devcontainer Integration Modules

This directory contains the core modules for AIDP's devcontainer integration feature.

## Modules

### Parser (`parser.rb`)

Parse existing devcontainer.json files and extract configuration.

```ruby
parser = Aidp::Setup::Devcontainer::Parser.new("/path/to/project")

if parser.devcontainer_exists?
  config = parser.parse
  ports = parser.extract_ports
  features = parser.extract_features
  env = parser.extract_env  # Sensitive data filtered
end
```

**Tests**: 36 ✅ | **Lines**: 252

### Generator (`generator.rb`)

Generate or update devcontainer.json from wizard configuration.

```ruby
generator = Aidp::Setup::Devcontainer::Generator.new("/path/to/project")

wizard_config = {
  project_name: "My App",
  language: "ruby",
  test_framework: "rspec",
  app_type: "rails_web"
}

# Generate new or merge with existing
config = generator.generate(wizard_config, existing_config)
```

**Tests**: 46 ✅ | **Lines**: 429

### PortManager (`port_manager.rb`)

Detect required ports and generate documentation.

```ruby
port_manager = Aidp::Setup::Devcontainer::PortManager.new(wizard_config)

ports = port_manager.detect_required_ports
forward_ports = port_manager.generate_forward_ports
port_attributes = port_manager.generate_port_attributes

# Generate PORTS.md
port_manager.generate_ports_documentation("docs/PORTS.md")
```

**Tests**: 39 ✅ | **Lines**: 287

### BackupManager (`backup_manager.rb`)

Create and manage backups of devcontainer.json.

```ruby
backup_manager = Aidp::Setup::Devcontainer::BackupManager.new("/path/to/project")

# Create backup
backup_path = backup_manager.create_backup(
  ".devcontainer/devcontainer.json",
  {reason: "wizard_update"}
)

# List backups
backups = backup_manager.list_backups

# Restore
backup_manager.restore_backup(backup_path, target_path)
```

**Tests**: 38 ✅ | **Lines**: 177

## Testing

Run all tests:

```bash
bundle exec rspec spec/aidp/setup/devcontainer/
```

**Total**: 159 tests, 0 failures ✅

## Code Quality

- ✅ StandardRB compliant (0 offenses)
- ✅ LLM Style Guide adherent
- ✅ Sandi Metz guidelines followed
- ✅ Comprehensive test coverage

## Documentation

- [PRD](../../../../docs/PRD_DEVCONTAINER_INTEGRATION.md) - Product requirements
- [Phase 1 Summary](../../../../docs/devcontainer/PHASE_1_SUMMARY.md) - Module details
- [Quick Start](../../../../docs/devcontainer/QUICK_START.md) - Integration guide

## Usage in Wizard

```ruby
# In lib/aidp/setup/wizard.rb
require_relative "devcontainer/parser"
require_relative "devcontainer/generator"
require_relative "devcontainer/port_manager"
require_relative "devcontainer/backup_manager"

def configure_devcontainer
  parser = Devcontainer::Parser.new(project_dir)
  existing = parser.devcontainer_exists? ? parser.parse : nil

  # ... wizard questions ...

  generator = Devcontainer::Generator.new(project_dir)
  new_config = generator.generate(wizard_config, existing)

  # Create backup if existing
  if existing
    backup_manager = Devcontainer::BackupManager.new(project_dir)
    backup_manager.create_backup(parser.detect, {reason: "wizard_update"})
  end

  # Write devcontainer.json
  File.write(".devcontainer/devcontainer.json", JSON.pretty_generate(new_config))
end
```

## Security

All modules filter sensitive data:

- API keys, tokens, passwords
- Pattern matching for base64, hex, API key formats
- Never logs or exports secrets

## Status

**Complete**: ✅ All modules tested and production-ready
**Next**: Wizard and CLI integration
