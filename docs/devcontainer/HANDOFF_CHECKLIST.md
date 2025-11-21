# Devcontainer Integration - Handoff Checklist

**Issue**: #213 - Extend Interactive Wizard to Create/Enhance Devcontainers
**Status**: Phases 1 & 2 Complete (60% done)
**Next Developer**: Use this checklist to continue the work

---

## ✅ What's Complete (No Action Needed)

- [x] **Core Modules** - All 4 modules working (Parser, Generator, PortManager, BackupManager)
- [x] **CLI Module** - DevcontainerCommands class complete
- [x] **Tests** - 189 tests, all passing
- [x] **Code Quality** - StandardRB clean, LLM Style Guide compliant
- [x] **Documentation** - 5 comprehensive guides created

**Test Verification**:

```bash
bundle exec rspec spec/aidp/setup/devcontainer/ spec/aidp/cli/devcontainer_commands_spec.rb
# Should show: 189 examples, 0 failures ✅
```text

---

## 🎯 Next Steps (In Priority Order)

### Step 1: Wire CLI Commands (30 minutes)

**File**: `lib/aidp/cli.rb`

**Action**: Add devcontainer subcommand routing

**Location**: Around line 393, add:

```ruby
when "devcontainer" then run_devcontainer_command(args)
```text

**Location**: Around line 2100, add these methods:

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
```text

**Test**:

```bash
./bin/aidp devcontainer diff
./bin/aidp devcontainer apply --dry-run
./bin/aidp devcontainer list-backups
```text

**Expected**: Commands should run without errors

---

### Step 2: Add to Wizard (2-3 hours)

**File**: `lib/aidp/setup/wizard.rb`

#### 2.1: Add Requires (Top of file, ~line 10)

```ruby
require_relative "devcontainer/parser"
require_relative "devcontainer/generator"
require_relative "devcontainer/port_manager"
require_relative "devcontainer/backup_manager"
```text

#### 2.2: Add to Run Method (~line 43)

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
  configure_devcontainer  # ← ADD THIS LINE

  yaml_content = generate_yaml
  # ... rest unchanged
end
```text

#### 2.3: Add Configure Method (~line 1200)

```ruby
def configure_devcontainer
  prompt.say("\n🐳 Devcontainer Configuration")

  # Detect existing
  parser = Devcontainer::Parser.new(project_dir)
  existing_devcontainer = parser.devcontainer_exists? ? parser.parse : nil

  if existing_devcontainer
    prompt.say("✓ Found existing devcontainer.json")
  end

  # Ask if user wants to manage
  manage = prompt.yes?(
    "Would you like AIDP to manage your devcontainer configuration?",
    default: @config.dig(:devcontainer, :manage) || existing_devcontainer ? true : false
  )

  return set([:devcontainer, :manage], false) unless manage

  # Detect and show ports
  wizard_config = build_wizard_config_for_devcontainer
  port_manager = Devcontainer::PortManager.new(wizard_config)
  detected_ports = port_manager.detect_required_ports

  if detected_ports.any?
    prompt.say("\nDetected ports:")
    detected_ports.each do |port|
      prompt.say("  • #{port[:number]} - #{port[:label]}")
    end
  end

  # Ask about custom ports
  custom_ports = []
  if prompt.yes?("Add custom ports?", default: false)
    loop do
      port_num = prompt.ask("Port number (or press Enter to finish):", default: nil)
      break if port_num.nil? || port_num.empty?

      port_label = prompt.ask("Port label:", default: "Custom")
      custom_ports << {number: port_num.to_i, label: port_label}
    end
  end

  # Save config
  set([:devcontainer, :manage], true)
  set([:devcontainer, :custom_ports], custom_ports) if custom_ports.any?
  set([:devcontainer, :last_generated], Time.now.utc.iso8601)
end

def build_wizard_config_for_devcontainer
  {
    providers: @config[:providers]&.keys,
    test_framework: @config.dig(:work_loop, :test_commands)&.first&.dig(:framework),
    watch_mode: @config.dig(:work_loop, :watch, :enabled),
    app_type: detect_app_type,
    services: detect_services,
    custom_ports: @config.dig(:devcontainer, :custom_ports)
  }
end

def detect_app_type
  return "rails_web" if File.exist?(File.join(project_dir, "config", "routes.rb"))
  return "sinatra" if File.exist?(File.join(project_dir, "config.ru"))
  "cli"
end

def detect_services
  services = []
  services << "postgres" if File.exist?(File.join(project_dir, "config", "database.yml"))
  services
end
```text

#### 2.4: Generate Devcontainer After Save

Add to `save_config` method (~line 1150):

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
```text

**Test**:

```bash
./bin/aidp config --interactive
# Complete wizard
# Check that .devcontainer/devcontainer.json was created
```text

---

### Step 3: Write Integration Tests (1 hour)

**File**: `spec/aidp/cli_integration_spec.rb` (create new)

```ruby
require "spec_helper"
require "tmpdir"

RSpec.describe "Devcontainer CLI Integration" do
  let(:project_dir) { Dir.mktmpdir }

  it "shows diff when no devcontainer exists" do
    output = `./bin/aidp devcontainer diff 2>&1`
    expect(output).to include("No existing devcontainer.json found")
  end

  # Add more integration tests
end
```text

**File**: `spec/aidp/setup/wizard_devcontainer_spec.rb` (create new)

```ruby
require "spec_helper"

RSpec.describe "Wizard Devcontainer Integration" do
  # Test wizard devcontainer flow
end
```text

---

### Step 4: Update Documentation (1-2 hours)

#### 4.1: Update SETUP_WIZARD.md

**File**: `docs/SETUP_WIZARD.md`

Add section:

```markdown
## Devcontainer Configuration

The wizard can automatically generate and manage your `.devcontainer/devcontainer.json`:

- Detects existing devcontainer configuration
- Maps your wizard selections to devcontainer features
- Configures port forwarding automatically
- Creates backups before modifications

Example:
- If you select RSpec → adds Ruby feature
- If you select Playwright → adds Playwright and Chrome
- If you have a web app → configures port 3000
```text

#### 4.2: Create DEVELOPMENT_CONTAINER.md

**File**: `docs/DEVELOPMENT_CONTAINER.md`

```markdown
# Development Containers with AIDP

Guide to using AIDP's devcontainer integration...

## Quick Start
## Configuration
## Port Management
## Troubleshooting
```text

#### 4.3: Update CONFIGURATION.md

**File**: `docs/CONFIGURATION.md`

Add section:

```markdown
## Devcontainer Configuration

```yaml
devcontainer:
  manage: true
  custom_ports:
    - number: 8000
      label: "Custom Service"
```text

```text

#### 4.4: Create PORTS.md Template
**File**: `docs/PORTS.md`

Example file that gets generated by PortManager.

---

## 🧪 Testing Your Changes

### After Step 1 (CLI)
```bash
# Test CLI commands work
./bin/aidp devcontainer diff
./bin/aidp devcontainer apply --help
```text

### After Step 2 (Wizard)

```bash
# Test wizard generates devcontainer
./bin/aidp config --interactive
# Answer questions, check .devcontainer/devcontainer.json created

# Test all module tests still pass
bundle exec rspec spec/aidp/setup/devcontainer/
```text

### After Step 3 (Integration Tests)

```bash
# Run all tests including new integration tests
bundle exec rspec spec/aidp/
```text

---

## 📋 Pre-Commit Checklist

Before committing your changes:

- [ ] All tests passing (189 + new integration tests)
- [ ] StandardRB clean: `bundle exec standardrb lib/aidp/`
- [ ] CLI commands work from terminal
- [ ] Wizard generates devcontainer.json
- [ ] Backups created before modifications
- [ ] Documentation updated
- [ ] Git status clean (no unwanted files)

---

## 🐛 Common Issues & Solutions

### Issue: CLI command not found

**Solution**: Check you added the route in `lib/aidp/cli.rb` line ~393

### Issue: Wizard doesn't ask about devcontainer

**Solution**: Check you added `configure_devcontainer` to the `run` method

### Issue: Tests failing after wizard integration

**Solution**: Make sure requires are at top of wizard.rb file

### Issue: StandardRB errors

**Solution**: Run `bundle exec standardrb --fix lib/aidp/`

---

## 📞 Getting Help

- **Documentation**: Check `docs/devcontainer/QUICK_START.md`
- **Examples**: See test files for usage examples
- **Architecture**: Review `docs/devcontainer/PHASE_1_SUMMARY.md`
- **Specification**: Read `docs/PRD_DEVCONTAINER_INTEGRATION.md`

---

## 📊 Progress Tracking

| Phase | Status | Time Est. | Files Changed |
| ------- | -------- | ----------- | --------------- |
| 1. Core Modules | ✅ Complete | - | 4 modules |
| 2. CLI Commands | ✅ Complete | - | 1 module |
| 3a. Wire CLI | ⏳ Pending | 30 min | 1 file |
| 3b. Wizard Integration | ⏳ Pending | 2-3 hours | 1 file |
| 4. Integration Tests | ⏳ Pending | 1 hour | 2 files |
| 5. Documentation | ⏳ Pending | 1-2 hours | 4 files |

**Total Remaining**: ~5-7 hours

---

## ✅ Success Criteria

You'll know you're done when:

1. ✅ `./bin/aidp devcontainer diff` shows a diff
2. ✅ `./bin/aidp devcontainer apply` creates `.devcontainer/devcontainer.json`
3. ✅ `./bin/aidp config --interactive` asks about devcontainer
4. ✅ Wizard generates working devcontainer.json
5. ✅ All tests pass (189 + integration tests)
6. ✅ StandardRB clean
7. ✅ Documentation complete

---

**Last Updated**: 2025-01-04
**Status**: Ready for Steps 1-4
**All Core Code**: Production-ready ✅
