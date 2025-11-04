# Devcontainer Integration - Quick Start Guide

**For Developers**: This guide helps you understand and extend the devcontainer integration feature.

---

## 🎯 What's Complete

### Core Modules (100% Working)

All modules are **tested, working, and ready to use**:

1. **DevcontainerParser** - Parse existing devcontainer.json
2. **DevcontainerGenerator** - Generate/update devcontainer.json
3. **PortManager** - Detect ports and create documentation
4. **BackupManager** - Backup/restore devcontainer files
5. **DevcontainerCommands** - CLI interface (diff, apply, restore)

### Test Status

```bash
bundle exec rspec spec/aidp/setup/devcontainer/ spec/aidp/cli/devcontainer_commands_spec.rb
# 189 examples, 0 failures ✅
```

---

## 🚀 Quick Usage Examples

### Parse Existing Devcontainer

```ruby
require_relative "lib/aidp/setup/devcontainer/parser"

parser = Aidp::Setup::Devcontainer::Parser.new("/path/to/project")

if parser.devcontainer_exists?
  config = parser.parse
  ports = parser.extract_ports
  # => [{number: 3000, label: "Application", protocol: "http"}, ...]

  features = parser.extract_features
  # => ["ghcr.io/devcontainers/features/ruby:1", ...]

  env = parser.extract_env  # Sensitive data filtered
  # => {"AIDP_LOG_LEVEL" => "info"}
end
```

### Generate New Devcontainer

```ruby
require_relative "lib/aidp/setup/devcontainer/generator"

generator = Aidp::Setup::Devcontainer::Generator.new("/path/to/project")

wizard_config = {
  project_name: "My App",
  language: "ruby",
  test_framework: "rspec",
  app_type: "rails_web",
  watch_mode: true
}

# Generate from scratch
new_config = generator.generate(wizard_config)

# Merge with existing
merged_config = generator.generate(wizard_config, existing_config)
```

### Detect Required Ports

```ruby
require_relative "lib/aidp/setup/devcontainer/port_manager"

port_manager = Aidp::Setup::Devcontainer::PortManager.new(wizard_config)

# Detect all ports
ports = port_manager.detect_required_ports
# => [{number: 3000, label: "Application", auto_open: true}, ...]

# Generate for devcontainer.json
forward_ports = port_manager.generate_forward_ports
# => [3000, 7681, 5432]

port_attributes = port_manager.generate_port_attributes
# => {"3000" => {"label" => "Application", "onAutoForward" => "notify"}}

# Generate PORTS.md
port_manager.generate_ports_documentation("docs/PORTS.md")
```

### Backup & Restore

```ruby
require_relative "lib/aidp/setup/devcontainer/backup_manager"

backup_manager = Aidp::Setup::Devcontainer::BackupManager.new("/path/to/project")

# Create backup
backup_path = backup_manager.create_backup(
  ".devcontainer/devcontainer.json",
  {reason: "before_update", version: "0.21.0"}
)

# List backups
backups = backup_manager.list_backups
# => [{path: "...", filename: "...", created_at: ..., metadata: {...}}, ...]

# Restore
backup_manager.restore_backup(backup_path, ".devcontainer/devcontainer.json")

# Cleanup old backups (keep 10 most recent)
backup_manager.cleanup_old_backups(10)
```

### CLI Commands

```ruby
require_relative "lib/aidp/cli/devcontainer_commands"

commands = Aidp::CLI::DevcontainerCommands.new(project_dir: Dir.pwd)

# Show diff
commands.diff

# Apply config
commands.apply(force: true)

# List backups
commands.list_backups

# Restore backup
commands.restore("1", force: true)
```

---

## 📋 What's Left to Do

### Priority 1: Wire CLI Commands

**File**: `lib/aidp/cli.rb`

Add to the CLI router (around line 393):

```ruby
when "devcontainer" then run_devcontainer_command(args)
```

Add the method (around line 2100+):

```ruby
def run_devcontainer_command(args)
  require_relative "cli/devcontainer_commands"

  subcommand = args.shift
  commands = CLI::DevcontainerCommands.new(project_dir: @project_dir)

  case subcommand
  when "diff"
    commands.diff
  when "apply"
    options = parse_devcontainer_apply_options(args)
    commands.apply(options)
  when "list-backups", "backups"
    commands.list_backups
  when "restore"
    backup = args.shift
    options = parse_devcontainer_restore_options(args)
    commands.restore(backup, options)
  else
    puts "Usage: aidp devcontainer <diff|apply|list-backups|restore>"
    false
  end
end

def parse_devcontainer_apply_options(args)
  options = {}
  while (arg = args.shift)
    case arg
    when "--dry-run"
      options[:dry_run] = true
    when "--force"
      options[:force] = true
    when "--no-backup"
      options[:backup] = false
    end
  end
  options
end

def parse_devcontainer_restore_options(args)
  options = {}
  while (arg = args.shift)
    case arg
    when "--force"
      options[:force] = true
    when "--no-backup"
      options[:no_backup] = true
    end
  end
  options
end
```

**Test it**:

```bash
./bin/aidp devcontainer diff
./bin/aidp devcontainer apply --dry-run
./bin/aidp devcontainer list-backups
```

---

### Priority 2: Add to Wizard

**File**: `lib/aidp/setup/wizard.rb`

**Step 1**: Add to requires (top of file):

```ruby
require_relative "devcontainer/parser"
require_relative "devcontainer/generator"
require_relative "devcontainer/port_manager"
require_relative "devcontainer/backup_manager"
```

**Step 2**: Add to `run` method (around line 43):

```ruby
def run
  display_welcome
  normalize_existing_model_families!
  return @saved if skip_wizard?

  configure_providers
  configure_work_loop
  configure_branching
  configure_artifacts
  configure_nfrs
  configure_logging
  configure_modes
  configure_devcontainer  # ← ADD THIS

  yaml_content = generate_yaml
  # ... rest of method
end
```

**Step 3**: Add the configure method (around line 1200+):

```ruby
def configure_devcontainer
  prompt.say("\n🐳 Devcontainer Configuration")

  # Detect existing devcontainer
  parser = Devcontainer::Parser.new(project_dir)
  existing_devcontainer = parser.devcontainer_exists? ? parser.parse : nil

  if existing_devcontainer
    prompt.say("✓ Found existing devcontainer.json")
  end

  # Ask if user wants to manage devcontainer
  manage = prompt.yes?(
    "Would you like AIDP to manage your devcontainer configuration?",
    default: @config.dig(:devcontainer, :manage) || existing_devcontainer ? true : false
  )

  return set([:devcontainer, :manage], false) unless manage

  # Detect ports from other config
  wizard_config = build_wizard_config_for_devcontainer
  port_manager = Devcontainer::PortManager.new(wizard_config)
  detected_ports = port_manager.detect_required_ports

  # Show detected ports
  if detected_ports.any?
    prompt.say("\nDetected ports:")
    detected_ports.each do |port|
      prompt.say("  • #{port[:number]} - #{port[:label]}")
    end
  end

  # Ask about additional ports
  add_custom = prompt.yes?("Add custom ports?", default: false)
  custom_ports = []

  if add_custom
    loop do
      port_num = prompt.ask("Port number (or press Enter to finish):", default: nil)
      break if port_num.nil? || port_num.empty?

      port_label = prompt.ask("Port label:", default: "Custom")
      custom_ports << {number: port_num.to_i, label: port_label}
    end
  end

  # Detect features from config
  features = detect_devcontainer_features

  # Save config
  set([:devcontainer, :manage], true)
  set([:devcontainer, :custom_ports], custom_ports) if custom_ports.any?
  set([:devcontainer, :features], features) if features.any?
  set([:devcontainer, :last_generated], Time.now.utc.iso8601)
end

def build_wizard_config_for_devcontainer
  {
    providers: @config[:providers]&.keys,
    test_framework: @config.dig(:work_loop, :test_commands)&.first&.dig(:framework),
    watch_mode: @config.dig(:work_loop, :watch, :enabled),
    app_type: detect_app_type,
    services: detect_services
  }
end

def detect_devcontainer_features
  features = []

  # GitHub CLI for any provider
  features << "ghcr.io/devcontainers/features/github-cli:1" if @config[:providers]&.any?

  # Ruby for RSpec
  if @config.dig(:work_loop, :test_commands)&.any? { |t| t[:framework] == "rspec" }
    features << "ghcr.io/devcontainers/features/ruby:1"
  end

  features
end

def detect_app_type
  # Simple heuristic based on project
  return "rails_web" if File.exist?(File.join(project_dir, "config", "routes.rb"))
  return "sinatra" if File.exist?(File.join(project_dir, "config.ru"))
  "cli"
end

def detect_services
  services = []
  services << "postgres" if File.exist?(File.join(project_dir, "config", "database.yml"))
  services
end
```

**Step 4**: Generate devcontainer.json after save (in `save_config` method):

```ruby
def save_config(yaml_content)
  File.write(config_path, yaml_content)

  # Generate devcontainer if managed
  if @config.dig(:devcontainer, :manage)
    generate_devcontainer_file
  end
end

def generate_devcontainer_file
  wizard_config = build_wizard_config_for_devcontainer
  wizard_config[:custom_ports] = @config.dig(:devcontainer, :custom_ports)

  parser = Devcontainer::Parser.new(project_dir)
  existing = parser.devcontainer_exists? ? parser.parse : nil

  generator = Devcontainer::Generator.new(project_dir, @config)
  new_config = generator.generate(wizard_config, existing)

  # Create backup if existing
  if existing
    backup_manager = Devcontainer::BackupManager.new(project_dir)
    backup_manager.create_backup(
      parser.detect,
      {reason: "wizard_update", timestamp: Time.now.utc.iso8601}
    )
  end

  # Write devcontainer.json
  devcontainer_path = File.join(project_dir, ".devcontainer", "devcontainer.json")
  FileUtils.mkdir_p(File.dirname(devcontainer_path))
  File.write(devcontainer_path, JSON.pretty_generate(new_config))

  prompt.ok("✅ Generated #{devcontainer_path}")
end
```

---

## 🧪 Testing Your Changes

### Run All Devcontainer Tests

```bash
bundle exec rspec spec/aidp/setup/devcontainer/ spec/aidp/cli/devcontainer_commands_spec.rb
```

### Test CLI Commands

```bash
# Show diff
./bin/aidp devcontainer diff

# Apply with dry run
./bin/aidp devcontainer apply --dry-run

# List backups
./bin/aidp devcontainer list-backups

# Restore
./bin/aidp devcontainer restore 1 --force
```

### Test Wizard Integration

```bash
./bin/aidp config --interactive
# Answer questions
# Check that .devcontainer/devcontainer.json is created
```

---

## 📚 Module Reference

### DevcontainerParser

**Location**: `lib/aidp/setup/devcontainer/parser.rb`
**Tests**: `spec/aidp/setup/devcontainer/parser_spec.rb` (36 tests)

**Key Methods**:

- `devcontainer_exists?` - Check if devcontainer.json exists
- `detect` - Find devcontainer path
- `parse` - Parse JSON and load config
- `extract_ports` - Get port configurations
- `extract_features` - Get features list
- `extract_env` - Get env vars (filtered)
- `to_h` - Get complete config as hash

### DevcontainerGenerator

**Location**: `lib/aidp/setup/devcontainer/generator.rb`
**Tests**: `spec/aidp/setup/devcontainer/generator_spec.rb` (46 tests)

**Key Methods**:

- `generate(wizard_config, existing = nil)` - Generate config
- `merge_with_existing(new, old)` - Merge configs
- `build_features_list(config)` - Map wizard → features
- `build_post_commands(config)` - Generate post-create commands

**Preserved Fields** (during merge):

- `remoteUser`, `workspaceFolder`, `mounts`, `runArgs`, etc.

### PortManager

**Location**: `lib/aidp/setup/devcontainer/port_manager.rb`
**Tests**: `spec/aidp/setup/devcontainer/port_manager_spec.rb` (39 tests)

**Key Methods**:

- `detect_required_ports` - Detect all ports
- `generate_forward_ports` - Get array of port numbers
- `generate_port_attributes` - Get port attributes hash
- `generate_ports_documentation(path)` - Create PORTS.md

**Standard Ports**:

- 3000: Web app
- 7681: Remote terminal (watch mode)
- 9222: Playwright debug
- 5432: PostgreSQL
- 6379: Redis
- 3306: MySQL

### BackupManager

**Location**: `lib/aidp/setup/devcontainer/backup_manager.rb`
**Tests**: `spec/aidp/setup/devcontainer/backup_manager_spec.rb` (38 tests)

**Key Methods**:

- `create_backup(path, metadata = {})` - Create backup
- `list_backups` - List all backups (sorted newest first)
- `restore_backup(backup, target, options)` - Restore
- `cleanup_old_backups(keep = 10)` - Delete old backups
- `latest_backup` - Get most recent

**Backup Location**: `.aidp/backups/devcontainer/`
**Format**: `devcontainer-YYYYMMDD_HHMMSS.json`

### DevcontainerCommands

**Location**: `lib/aidp/cli/devcontainer_commands.rb`
**Tests**: `spec/aidp/cli/devcontainer_commands_spec.rb` (30 tests)

**Key Methods**:

- `diff(options = {})` - Show diff
- `apply(options = {})` - Apply config
- `list_backups` - List backups
- `restore(index_or_path, options = {})` - Restore

**Options**:

- `dry_run`: Preview only
- `force`: Skip confirmation
- `backup`: Create backup (default true)
- `no_backup`: Skip backup creation

---

## 🔧 Troubleshooting

### Tests Failing?

```bash
# Run with backtrace
bundle exec rspec spec/aidp/setup/devcontainer/ --backtrace

# Run specific test
bundle exec rspec spec/aidp/setup/devcontainer/parser_spec.rb:25
```

### StandardRB Issues?

```bash
# Check
bundle exec standardrb lib/aidp/setup/devcontainer/ lib/aidp/cli/devcontainer_commands.rb

# Auto-fix
bundle exec standardrb --fix lib/aidp/setup/devcontainer/
```

### CLI Not Working?

1. Check that devcontainer_commands.rb uses `class CLI` (not `module CLI`)
2. Verify requires are correct
3. Check that main CLI routes to `run_devcontainer_command`

---

## 📖 Additional Documentation

- **PRD**: `docs/PRD_DEVCONTAINER_INTEGRATION.md` (complete specification)
- **Phase 1 Summary**: `docs/devcontainer/PHASE_1_SUMMARY.md` (module details)
- **Session Summary**: `docs/devcontainer/SESSION_SUMMARY.md` (overall progress)

---

## ✅ Verification Checklist

Before committing:

- [ ] All 189 tests passing
- [ ] StandardRB clean
- [ ] CLI commands working from command line
- [ ] Wizard generates devcontainer.json
- [ ] Backups created before modifications
- [ ] Documentation updated

---

**Questions?** Check the comprehensive docs or review the test files for usage examples.

**Status**: Core modules complete and tested. Ready for wizard and CLI integration.
