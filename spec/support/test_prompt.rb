# frozen_string_literal: true

# Mock menu class for TTY::Prompt select blocks
class MockMenu
  attr_reader :choices

  def initialize
    @choices = []
  end

  def choice(label, value = nil)
    @choices << {label: label, value: value || label}
  end
end

# Test prompt class - implements TTY::Prompt interface for testing
# This provides a mock/spy implementation that records all interactions
# for testing TTY::Prompt-based classes without actual user interaction.
class TestPrompt
  attr_reader :messages, :selections, :inputs, :responses

  def initialize(responses: {})
    @responses = responses
    @messages = []
    @selections = []
    @inputs = []
  end

  def select(title, items = nil, **options, &block)
    if block
      # Handle block-style select (like TTY::Prompt)
      menu = MockMenu.new
      yield(menu)
      @selections << {title: title, items: menu.choices, options: options, block: true}
      # Priority: explicit map, then sequence array, then single value, else first menu choice
      if @responses[:select_map]
        # Exact match first
        if @responses[:select_map].key?(title)
          val = @responses[:select_map][title]
          return val.is_a?(Array) ? val.shift : val
        end
        # Fallback prefix match (handles dynamic suffixes like " (current: xyz)")
        key = @responses[:select_map].keys.find { |k| title.start_with?(k) }
        if key
          val = @responses[:select_map][key]
          return val.is_a?(Array) ? val.shift : val
        end
      end
      return @responses[:select].shift if @responses[:select].is_a?(Array)

      @responses[:select] || menu.choices.first[:value]
    else
      @selections << {title: title, items: items, options: options}
      if @responses[:select_map]
        if @responses[:select_map].key?(title)
          val = @responses[:select_map][title]
          return val.is_a?(Array) ? val.shift : val
        end
        key = @responses[:select_map].keys.find { |k| title.start_with?(k) }
        if key
          val = @responses[:select_map][key]
          return val.is_a?(Array) ? val.shift : val
        end
      end
      return @responses[:select].shift if @responses[:select].is_a?(Array)

      @responses[:select] || (items.is_a?(Hash) ? items.values.first : items.first)
    end
  end

  def multi_select(title, items = nil, **options)
    if block_given?
      menu = MockMenu.new
      yield menu
      @selections << {title: title, items: menu.choices, options: options, multi: true, block: true}
    else
      @selections << {title: title, items: items, options: options, multi: true}
    end
    if @responses[:multi_select_map]&.key?(title)
      mapped = @responses[:multi_select_map][title]
      return mapped.is_a?(Array) ? mapped : Array(mapped)
    end
    return @responses[:multi_select] if @responses[:multi_select].is_a?(Array)

    @responses[:multi_select] || []
  end

  def ask(message, **options, &block)
    @inputs << {message: message, options: options}

    # Handle multiple responses by cycling through them
    response = if @responses[:ask].is_a?(Array)
      @responses[:ask][@inputs.length - 1] || @responses[:ask].last
    else
      @responses[:ask] || ""
    end

    # If a block is provided, simulate the conversion logic
    if block
      # Create a mock question object that can handle conversion
      question_mock = Object.new
      question_mock.define_singleton_method(:convert) do |type|
        case type
        when :int
          response = response.to_i
        when :float
          response = response.to_f
        end
      end
      question_mock.define_singleton_method(:validate) do |pattern, message|
        # Skip validation for test purposes
      end
      yield(question_mock)
    end

    response
  end

  def yes?(message, **options)
    @inputs << {message: message, options: options, type: :yes}
    if @responses[:yes_map]&.key?(message)
      val = @responses[:yes_map][message]
      return val.is_a?(Array) ? val.shift : val
    end
    return @responses[:yes?].shift if @responses[:yes?].is_a?(Array)

    @responses.key?(:yes?) ? @responses[:yes?] : true
  end

  def no?(message, **options)
    @inputs << {message: message, options: options, type: :no}
    if @responses[:no_map]&.key?(message)
      val = @responses[:no_map][message]
      return val.is_a?(Array) ? val.shift : val
    end
    return @responses[:no?].shift if @responses[:no?].is_a?(Array)

    @responses.key?(:no?) ? @responses[:no?] : false
  end

  # Patterns for noisy messages that should be suppressed in test output
  SUPPRESS_PATTERNS = [
    # Work loop messages
    /🔄 Starting hybrid work loop/,
    /Flow: Deterministic/,
    /State machine:/,
    /Iteration \d+/,
    /Required checks failed/,
    /\[DIAGNOSE\]/,
    /\[NEXT_PATCH\]/,
    /\[STYLE_GUIDE\]/,
    /⚠️  Max iterations/,
    /✅ Step /,
    /📊 Fix-Forward State Summary/,
    /Total iterations:/,
    /State transitions:/,
    /All checks passed but/,
    /💡 Using tier:/,
    /Created PROMPT\.md/,
    /Created optimized PROMPT\.md/,

    # Provider/model messages
    /🔄 Provider switch:/,
    /🔄 Model switch:/,
    /🔴 Circuit breaker opened/,
    /🟢 Circuit breaker reset/,
    /❌ No providers available/,
    /❌ No models available/,
    /All providers are rate limited, unhealthy, or circuit breaker open/,
    /All models are rate limited, unhealthy, or circuit breaker open/,
    /📊 Execution Summary/,

    # Workstream execution messages
    /▶️  \[/,
    /✅ \[/,
    /❌ \[/,

    # GitHub/Issue messages
    /🏷️  Updated labels:/,
    /🏷️  Removed .* label/,
    /🏷️  Replaced .* with .* label/,
    /🧠 Generating plan/,
    /💬 Posted plan comment/,
    /💬 Posted.*comment/,
    /💬 Posted clarification request/,
    /🎉 Posted completion comment/,
    /🎉 Posted success comment/,
    /📝 Updated plan comment/,
    /📝 Processing change request/,
    /📝 Processing \d+ .* files/,
    /💾 Writing knowledge base/,

    # Checkpoint messages
    /📊 Checkpoint - Iteration/,
    /📜 Checkpoint History/,
    /Progress: \[=+\s*\]/,

    # Workstream messages
    /🔄 Reusing existing workstream:/,
    /🛠️  Starting implementation/,
    /🛠️  Running deterministic unit:/,
    /🌿 Creating workstream:/,
    /🌿 Checked out branch:/,
    /✅ Workstream created/,
    /ℹ️  Workstream .* preserved/,
    /📝 Wrote PROMPT\.md/,
    /💾 Created commit:/,
    /⬆️  Pushed branch/,
    /⬆️  Pushed changes to/,
    /ℹ️  Skipping PR creation/,
    /❌ Implementation failed/,
    /⚠️  Build failure recorded/,
    /⚠️  No recorded plan/,
    /⚠️  Completion criteria unmet/,
    /⚠️  Implementation produced no changes/,
    /ℹ️  No file changes detected/,

    # CLI/Startup messages
    /AIDP initializing\.\.\./,
    /Press Ctrl\+C to stop/,
    /✅ Harness completed successfully/,
    /All steps finished automatically/,
    /Usage: aidp \[COMMAND\]/,
    /AI Development Pipeline/,

    # Watch mode safety messages
    /⚠️  Watch mode running outside container/,
    /Consider using a containerized environment/,
    /✅ Watch mode safety checks passed/,
    /⚠️  Watch mode enabled for PUBLIC repository/,
    /Ensure you trust all contributors/,
    /⚠️  Watch mode safety checks BYPASSED/,
    /⏭️  Skipping issue.*not authorized/,

    # PR change request processor messages
    /⚠️  PR #\d+ diff too large/,
    /🔨 Implementing requested changes for PR #\d+/,
    /🧪 Running tests and linters/,
    /❌ Posted test failure comment for PR #\d+/,
    /⚠️  Unknown action:/,
    /ℹ️  No changes to commit after applying/,
    /🌿 Using worktree for PR #\d+:/,
    /🔗 Found linked issue #\d+ - verifying implementation/,
    /⚠️  Implementation incomplete; creating follow-up tasks/,
    /⚠️  Failed to create follow-up tasks:/,
    /📝 Recorded incomplete implementation status for PR #\d+/,
    /⚠️  Posted cannot-implement comment for PR #\d+/,
    /ℹ️  Posted no-changes comment for PR #\d+/,
    /⚠️  Max clarification rounds.*reached for PR #\d+/,
    /❌ Change request processing failed:/,
    /ℹ️  No authorized comments found for PR #\d+/,
    /🔄 Reusing worktree .* for issue #\d+ \(PR #\d+\)/,
    /✅ Implementation verified complete/,
    /ℹ️  PR change requests are disabled in configuration/,
    /🤔 Posted clarification request for PR #\d+/,

    # Auto processor messages
    /🤖 Starting autonomous build for issue #\d+/,
    %r{🤖 Running autonomous review/CI loop for PR #\d+},
    /🏷️  Added '.*' to PR #\d+/,
    /🏷️  Removed '.*' from (issue|PR) #\d+/,

    # Provider and circuit breaker messages
    /Context: \{[^}]*}/,
    /All providers are rate limited, unhealthy, or circuit breaker open/,

    # Git worktree messages
    /HEAD is now at/,
    /Preparing worktree/,
    %r{\?\? \.aidp/}, # Untracked .aidp directory in git status
    /fatal: not a git repository/,
    /fatal: pathspec .* did not match any files/,
    /fatal: could not create leading directories/,

    # Harness execution messages
    /⏹️  Harness (stopped|STOPPED)/,
    /Execution terminated (manually|by user)/,
    /🕒 Deterministic wait:/,
    /✅ Deterministic unit .* finished with status/,
    /❌ Deterministic unit .* failed:/,

    # Implementation verification messages
    /🔍 Verifying implementation completeness/,
    /🔍 Reviewing PR #\d+/,
    /ℹ️  Review for PR #\d+ already posted/,
    /❌ Review failed:/,

    # Error and cancellation messages
    /⚠️  Failed to create pull request:/,
    /⚠️  Failed to remove CI fix label:/,
    /Error: test error/,
    /Wizard cancelled/,
    /Configuration setup cancelled/,
    /Configuration required\. Aborting startup/,
    /Warning: .*was considered valid by email validation/,

    # Configuration messages
    /Failed to load configuration file/,
    /Failed to load provider info for/,
    /mapping values are not allowed in this context/,
    /did not find expected key while parsing/,

    # CI Fix processor messages
    /🔧 Analyzing CI failures for PR #\d+/,
    /Found \d+ failed check\(s\):/,
    /✅ CI is passing for PR #\d+/,
    /⏳ CI is still running for PR #\d+/,
    /⚠️  No specific failed checks found for PR #\d+/,
    /ℹ️  CI fix for PR #\d+ already completed/,
    /❌ CI fix failed:/,
    /🌿 Creating worktree for PR #\d+/,
    /⚠️  Posted failure comment for PR #\d+/,

    # Plan generation messages
    /🔄 Re-planning for issue #\d+/,
    /⚠️  Unable to generate plan for issue #\d+/,

    # Workflow status messages (with various message suffixes)
    # Note: Using .? after emoji to handle optional variation selectors (️)
    /⚠.? Workflow paused: .+/,
    /✓.? Workflow completed: .+/,
    /✓.? Workflow resumed: .+/,
    /✗.? Workflow stopped: .+/,
    /⚠.? Workflow cancelled: .+/,
    /⏸️  Harness PAUSED/,
    /Press 'r' to resume, 's' to stop/,
    /▶️  Harness RESUMED/,
    /Continuing execution/,

    # Execution step messages
    /🚀 Running execution step/,
    /✅ Execution step completed/,
    /🚀 Starting parallel execution of \d+ workstreams/,
    /Total: \d+.*Completed: \d+.*Failed: \d+/,
    /Total Duration:/,
    /⚠️  No active workstreams found/,

    # File operation messages
    /✓ create /,
    /✓ edit /,
    /✓ Deleted /,

    # Progress and metrics messages
    /Iteration.*Time.*LOC.*Coverage/,
    /Iter: \d+.*LOC:.*Cov:.*Qual:.*PRD:/,
    /📈 Progress Summary/,
    /Step: /,
    /Iteration: \d+/,
    /Current Metrics:/,
    /Lines of Code:/,
    /Test Coverage:/,
    /Code Quality:/,
    /PRD Task Progress:/,
    /File Count:/,
    /Trends:/,
    /Overall Status:/,
    /Quality Score:/,
    /↑ \+\d+/,
    /↓ -\d+/,
    /✓ Healthy/,
    /⚠ Warning/,

    # Interactive prompts
    /🤖 Agent needs your feedback:/,
    /📊 Overview:/,
    /Total questions:/,
    /Required:/,
    /Optional:/,
    /Question types:/,
    /Estimated time:/,
    /📝 Questions to answer:/,
    /✅ Question Completion Summary/,
    /📊 Statistics:/,
    /Answered:/,
    /Skipped:/,
    /Completion rate:/,
    /📝 Response Summary:/,
    /🚀 Continuing execution/,

    # Completion criteria messages
    /⚠️  All steps completed but some completion criteria not met:/,
    %r{❌ \d+/\d+ criteria failed:},
    /⚠️  Non-interactive mode: cannot override/,
    /Missing (artifacts|tests|coverage)/,

    # Knowledge Base messages
    /📊 Knowledge Base Summary/,
    /📁 KB Directory:/,
    /📄 Files analyzed:/,
    /🏗️  Symbols:/,
    /📦 Imports:/,
    /🔗 Calls:/,
    /📏 Metrics:/,
    /🔧 Seams:/,
    /🔥 Hotspots:/,
    /🧪 Tests:/,
    /🔄 Cycles:/,
    /🔧 Seam Types:/,
    /🔥 Top \d+ Hotspots:/,
    /\d+\. .*\(score: \d+\)/,

    # Usage and version messages
    /Usage: aidp config/,
    /Options:/,
    /--interactive/,
    /--dry-run/,
    /-h, --help/,
    /Examples:/,
    /aidp config --interactive/,
    /Aidp version/,
    /Test message/,
    /⏹️  Interrupted by user/,
    /Unknown command:/,
    /AI Dev Pipeline Status/,
    /----------------------/,
    /Analyze Mode:/,
    /Execute Mode:/,
    /Use 'aidp analyze' or 'aidp execute'/,

    # Table messages
    /The table size exceeds the currently set width/,
    /Defaulting to vertical orientation/,

    # File preview messages
    /📄 File Preview:/,
    /📊 File Info:/,
    /Size: \d+ B/,
    /Lines: \d+/,
    /Modified: \d{4}-\d{2}-\d{2}/,
    /Type: File/,
    /📝 Content Preview \(first \d+ lines\):/,
    /^\s+\d+: /, # Numbered content lines
    /\.\.\. \(\d+ more lines\)/,
    /Press Enter to continue/,
    /❌ Error reading file:/,
    /No such file or directory/,

    # File selector messages
    /No files found matching/,
    /Please try again/,
    /💡 Try: @ \(all files\)/,
    /✅ Selected:/,

    # Guided workflow messages
    /🤖 Welcome to AIDP Guided Workflow/,
    /I'll help you plan and execute your project/,
    /📋 Plan Phase/,
    /I'll ask clarifying questions/,
    /What would you like to do\?/,
    /Build a new feature for/,
    /Understand how this codebase/,
    /Improve test coverage in/,
    /Create a quick prototype for/,
    /⚠️  Provider '.*' failed \(empty response\)/,
    /attempting fallback/,
    /↩️  Switched to provider/,
    /retrying with same prompt/,
    /✅ Plan Summary/,
    /Goal: /,
    /🔍 Identifying needed steps/,
    /📝 Generating planning documents/,
    /✓ Documents generated/,

    # Review and error messages
    /⚠️  Failed to save review log:/,
    /Permission denied @ dir_s_mkdir/,

    # Background jobs messages
    /Background Jobs/,
    /No background jobs found/,
    /Start a background job with:/,
    /aidp execute --background/,
    /aidp analyze --background/,

    # Formatting
    /^────+$/,  # Separator lines (full line)
    /────+/,    # Separator lines (anywhere in message)
    /^====+$/,  # Separator lines (full line)
    /====+/,    # Separator lines (anywhere in message)
    /^━+$/,     # Box drawing separator lines
    /━+/,       # Box drawing separator lines (anywhere)
    /^-{10,}$/, # Dashed separator lines

    # Control interface messages
    /🎮 Control interface/,
    /🎮 Harness Control Menu/,
    /🎮 Control Interface/,
    /🛑 Control Interface/,
    /⏸️  HARNESS PAUSED/,
    /▶️  HARNESS RESUMED/,
    /🛑 HARNESS STOPPED/,
    /🚨 EMERGENCY STOP INITIATED/,
    /Press 'p' \+ Enter to pause/,
    /Press 'r' \+ Enter to resume/,
    /Press 's' \+ Enter to stop/,
    /Press 'h' \+ Enter/,
    /Press 'q' \+ Enter/,
    /'r' \+ Enter: Resume/,
    /'s' \+ Enter: Stop/,
    /'h' \+ Enter: Show help/,
    /'q' \+ Enter: Quit/,
    /⏸️  Pause requested/,
    /▶️  Resume requested/,
    /🛑 Stop requested/,
    /⏸️  Quick pause requested/,
    /▶️  Quick resume requested/,
    /🛑 Quick stop requested/,
    /👋 Exiting control menu/,
    /Select option \(1-8\)/,
    /1\. Start Control Interface/,
    /2\. Stop Control Interface/,
    /3\. Pause Harness/,
    /4\. Resume Harness/,
    /5\. Stop Harness/,
    /6\. Show Control Status/,
    /7\. Show Help/,
    /8\. Exit Menu/,
    /Execution has been stopped by user/,
    /Execution has been resumed/,
    /All execution will be halted immediately/,
    /This action cannot be undone/,
    /You can restart the harness from where it left off/,
    /❌ Invalid option\. Please select 1-8/,
    /❌ Invalid command\. Type 'h' for help/,
    /📖 Control Interface Help/,
    /🎮 Available Commands:/,
    /'p' or 'pause'/,
    /'r' or 'resume'/,
    /'s' or 'stop'/,
    /'h' or 'help'/,
    /'q' or 'quit'/,
    /📋 Control States:/,
    /Running  - Harness is executing normally/,
    /Paused   - Harness is paused/,
    /Stopped  - Harness has been stopped/,
    /Resumed  - Harness has been resumed/,
    /💡 Tips:/,
    /• You can pause\/resume\/stop at any time/,
    /• The harness will save its state/,
    /• You can restart from where you left off/,
    /• Use 'h' for help at any time/,
    /🎮 Control Interface Status/,
    /Enabled: (✅|❌)/,
    /Pause Requested: (⏸️|▶️)/,
    /Stop Requested: (🛑|▶️)/,
    /Resume Requested: (▶️|⏸️)/,
    /Control Thread: (🟢|🔴)/,
    /🛑 Emergency stop completed/,

    # Devcontainer messages
    /✅ Devcontainer configuration applied/,
    /🔍 Dry Run - Changes Preview/,
    /📄 Devcontainer Changes Preview/,
    /📦 Available Backups/,
    /📦 Restoring Backup/,
    /✅ Backup created:/,
    /✅ Backup restored/,
    /No existing devcontainer\.json found/,
    /Run 'aidp config --interactive'/,
    /No backups found/,
    /Features:/,
    /Ports:/,
    /Port Attributes:/,
    /Environment:/,
    /Other Changes:/,
    /No changes made \(dry run\)/,
    /File: .*devcontainer\.json/,
    /Total: \d+ backups/,
    /^\s+Created: \d{4}-\d{2}-\d{2}/,  # Indented backup creation timestamps only
    /^\s+Size: [\d.]+ [KMGB]+/,  # Indented backup size only
    /Reason: (manual_test|cli_apply)/,
    /From: devcontainer-/,
    /To: .*devcontainer\.json/,

    # Timeout and mode messages
    /🧠 Using adaptive timeout/,
    /⚡ Quick mode enabled/,
    /📋 Using default timeout/,

    # Knowledge base inspector messages
    /🔧 Seams Analysis/,
    /📌 [A-Z_]+ \(\d+ found\)/,
    /Generating import graph in/,
    /Graph written to/,
    /No seams data available/,
    /Knowledge Base Data/,
    /╔.*═.*╗/,    # Box drawing top
    /║.*║/,        # Box drawing sides
    /╚.*═.*╝/,    # Box drawing bottom
    /Row \d+:/,
    /Type: \w+/,
    /File: .+\.\w+/,
    /Line: \d+/,
    /Symbol:/,
    /Suggestion:/,

    # User interface feedback collection messages
    /📝 Quick Feedback Collection/,
    /✅ Batch feedback collected/,
    /📋 Question Summary:/,
    /❓ .+/,        # Question prompts like "❓ What is your name?" or "❓ Choose an option:"
    /📋 Context:/,
    /Urgency: (🔴|🟡|🟢)/,
    /Description: .+/,
    /Agent Output:/,
    /Agent needs user information/,
    /⚙️  User Preferences:/,
    /📖 Interactive Prompt Help/,
    /🔤 Input Types:/,
    /⌨️  Special Commands:/,
    /📁 File Selection:/,
    /✅ Validation:/,
    /  • Text: /,
    /  • Choice: /,
    /  • Confirmation: /,
    /  • File: /,
    /  • Number: /,
    /  • Email: /,
    /  • URL: /,
    /  • @: Browse and select/,
    /  • Enter: Use default/,
    /  • Ctrl\+C: Cancel/,
    /  • Type @ to browse/,
    /  • Type @search to filter/,
    /  • Select by number/,
    /  • Required fields must be filled/,
    /  • Input format is validated/,
    /  • Invalid input shows error/,
    /  • Use Tab for auto-completion/,
    /  • Arrow keys for history/,
    /  • Default values are shown/,
    /^\d+\. .+$/,   # Numbered list items like "1. What is your name?"
    /  \d+\. (📝|🔘|✅|📁|🔢|📧|🔗) .+ \((Required|Optional)\)/,  # Question summary items

    # Question display patterns (from display_numbered_question, etc.)
    /📝 Question \d+ of \d+/,
    /📋 Question Details:/,
    /📋 Context Summary:/,
    /💡 Instructions:/,
    /⚠️  Required Field:/,
    /✅ Optional Field:/,
    /⚡ Quick Answer:/,
    /📊 Progress: \[.*\] [\d.]+%/,
    /Status: (🔴|🟢)/,
    /Expected input:/,
    /Default:/,
    /(📝|🔘|✅|📁|🔢|📧|🔗) .+\?/,  # Emoji question types
    /  • Enter your text response/,
    /  • Use @ for file selection/,
    /  • Press Enter when done/,
    /  • Select from the numbered options/,
    /  • Enter the number of your choice/,
    /  • Press Enter to confirm/,
    /  • Enter 'y' or 'yes'/,
    /  • Enter 'n' or 'no'/,
    /  • Press Enter for default/,
    /  • Enter file path directly/,
    /  • File must exist and be readable/,
    /  • Enter a valid number/,
    /  • Use decimal point for decimals/,
    /  • Enter a valid email address/,
    /  • Format: (user@domain\.com|https:\/\/example\.com)/,
    /  • Enter a valid URL/,
    /  • This question must be answered/,
    /  • Cannot be left blank/,
    /  • This question can be skipped/,
    /  • Press Enter to leave blank/,
    /  • Press Enter to use default:/,
    /\[Skipped\]/,
    /^  \d+\. .+$/,     # Indented numbered responses like "  1. https://example.com"
    /🔘 Choose an option/,
    /📝 Optional comment/,
    /Available options:/,

    # UI component messages (navigation, menus, status)
    /📍 Section/,
    /^Home$/,
    /Navigation Help/,
    /Use arrow keys to navigate/,
    /Press Enter to select/,
    /Press Escape to go back/,
    /Invalid selection/,
    /📋 .*Menu$/,
    /No options available/,
    /Analyze Mode/,
    /Execute Mode/,
    /Select workflow/,
    /\d+ completed$/,

    # Status messages
    /ℹ .+ message$/,
    /✓ .+ message$/,
    /⚠ .+ message$/,
    /✗ .+ message$/,
    /^Unknown type$/,
    /ℹ Default message/,
    /Muted message/,
    /📝 Please provide feedback/,
    /Context: .+/,
    /^Name\?$/,
    /^Your age$/,
    /^What is your name\?$/,
    /^Comments\?$/,
    /^Pick a color$/,
    /^Config file$/,
    /^Do you agree$/,
    /🤖 Agent needs feedback/,

    # Spinner and progress messages
    /✅ Done \(\d+.+\)$/,
    /✅ Completed \([\d.]+s?\)$/,
    /✅ Completed successfully$/,
    /✅ Task completed$/,
    /✅ Task \d+ completed$/,
    /⏳ Loading/,
    /⏳ Processing/,
    /⏳ Task \d+ in progress/,
    /⚠️ Please check configuration/,
    /❌ Error occurred/,
    /❌ Something went wrong/,
    /❌ Task \d+ failed/,
    /Connection failed/,

    # MCP and eligibility messages (minimal - some tests verify this output)
    # Note: Many MCP messages are verified by tests via capture_output, so we don't suppress them

    # Workflow status messages
    /[✓✗⚠] Workflow (completed|resumed|cancelled|stopped|paused):/,
    /Current State: (🟢|🔴|🟡)/,
    /State Name:/,
    /Available Actions:/,
    /  (Pause|Resume|Cancel|Stop|Complete): (Yes|No)/,

    # Configuration messages
    /Created minimal configuration/,
    /Configuration setup skipped/,

    # Job monitoring messages
    /✅ Job monitoring (started|stopped)/,
    /❌ Job monitoring stopped/,
    /interval: [\d.]+s/,
    /No progress items to display/,
    /Progress: \d+% - /,
    /Status: (Completed|Running)/,

    # Frame summary messages
    /📊 Frame Summary/,
    /No frames used/,
    /Total Frames: \d+/,
    /Frame Types:/,
    /  📋 Section: \d+/,
    /Current Frame Depth:/,
    /Frames in History: \d+/,

    # Validation error messages
    /❌ Validation Error:/,
    /💡 Suggestions:/,
    /⚠️  Warnings:/,
    /  • Use format:/,
    /  • Local part is very long/,
    /  • Check for typos/,
    /Warning: .+ was considered valid by email validation/,

    # Help messages for question types
    /📖 Help for \w+ Question:/,
    /• Select from the numbered options/,
    /• Enter the number of your choice/,
    /• Or type the option text directly/,
    /• Enter any text response/,
    /• Use @ for file selection if needed/,
    /• Press Enter when done/,

    # Input error recovery
    /🚨 Input Error:/,
    /🔄 Retrying\.\.\./,
    /❌ Maximum retries exceeded/,

    # Work loop state machine output
    /^\s+(APPLY_PATCH|TEST|FAIL|DIAGNOSE|NEXT_PATCH|PASS|DONE|READY): \d+ times?$/,
    /^\s+• Prompt size: \d+ chars \| State: \w+$/,

    # Devcontainer paths and diff output
    %r{^\s+/tmp/[^/]+/\.devcontainer/devcontainer\.json$},
    /^\s+\+ [a-z]+:/,        # Config additions like "+ ghcr.io/..."
    /^\s+~ \w+:/,            # Config changes like "~ name:"
    /^\s+→ /,                # Arrow in diffs

    # Additional backup messages
    /❌ Backup not found:/,

    # GitHub label auto-creation messages
    /🏷️  GitHub Label Auto-Creation/,
    /Automatically create GitHub labels for watch mode/,
    /📦 Repository:/,
    /📝 Labels to create:/,
    /  • aidp-\w+ \([A-F0-9]+\)/,
    /⚠️  Could not determine GitHub repository/,
    /⚠️  Failed to fetch existing labels/,
    /⚠️  GitHub CLI \(gh\) not found/,
    /Ensure you're in a git repository/,
    /Visit: https:\/\/cli\.github\.com/,
    /✅ All required labels already exist/,
    /Check your GitHub authentication/,

    # Setup wizard messages
    /🧙 AIDP Setup Wizard/,
    /This wizard will help you configure AIDP/,
    /Press Enter to keep defaults/,
    /📦 Provider configuration/,
    /  • Added provider/,
    /💡 Use ↑\/↓ arrows to navigate/,
    /💡 Provider integration:/,
    /AIDP does not store API keys/,
    /Only the billing model/,
    /📋 Provider Configuration Summary/,
    /⚙️  Harness Configuration/,
    /Advanced settings for provider behavior/,
    /🧠 Thinking Tier Configuration/,
    /🔍 Discovering available models/,
    /Removed '.+' from fallback providers/,
    /⚠️  Duplicate configurations detected/,
    /Consider using different providers/,

    # Setup wizard section headers
    /💡 You can run 'aidp models discover' later to see available models/,
    /⚙️  Work loop configuration/,
    /🔍 Output filtering configuration/,
    /^\s+Reduces token consumption by filtering test\/lint output$/,
    /📊 Coverage configuration/,
    /🎯 Interactive testing configuration/,
    /🗂️  Version control configuration/,
    /📋 Commit Behavior \(applies to copilot\/interactive mode only\)/,
    /^Note: Watch mode and fully automatic daemon mode will always commit changes\.$/,
    /🌿 Branching strategy/,
    /📁 Artifact storage/,
    /📋 Non-functional requirements & preferred libraries/,
    /📝 Logging configuration/,
    /♻️  Auto-update configuration/,
    /🚀 Operational modes/,
    /🐳 Devcontainer Configuration/,

    # Setup wizard labels and status
    /^\s+✅ Created: [\w-]+$/,
    /^\s+⚠️  Failed to create: [\w-]+ - .+$/,
    /^✅ Successfully created \d+ labels?$/,
    /^⚠️  Failed to create \d+ labels?$/,
    /^\s+• [\w-]+ \([A-F0-9]+\)$/,
    /^✅ All required labels already exist!$/,

    # Setup wizard provider editing
    /^🔧 Editing provider '[^']+' \(current: .+\)$/,
    /^Updated '[^']+' → .+$/,
    /^\s+• \w+ and \w+ have identical billing type \(\w+\) and model family \(\w+\)$/,
    /^Removed '[^']+' from fallback providers$/,

    # Setup wizard NFR display
    /^Performance requirements:$/,
    /^Security requirements:$/,
    /^Reliability requirements:$/,
    /^Accessibility requirements:$/,
    /^Internationalization requirements:$/,

    # Setup wizard devcontainer status
    /^✓ Found existing devcontainer\.json$/,

    # Setup wizard configuration status
    /^📄 Configuration preview$/,
    /^Dry run mode active – configuration was NOT written\.$/,
    /^✅ Configuration saved to [\w.\/]+$/,
    /^Configuration not saved$/,
    /^📝 Found existing configuration at [\w.\/]+$/,
    /^🔍 Diff with existing configuration:$/,
    /^🎉 Setup complete!$/,
    /^Next steps:$/,

    # Configuration diff output (specific patterns only, avoid broad matches)
    /^\+ # .+$/,
    /^\+ ---$/,
    # Note: Removed broad patterns like /^\+ \w+:/, /^  \w+:/, /^- \w+:/ as they
    # can match legitimate output like "Task: Add new feature"

    # Multiline input prompts (specific labels only)
    /^(Description|Summary|Notes|Comments):$/,
    /\(Enter text; submit empty line to finish/,
    /Type 'clear' alone to remove/,

    # Planning loop warnings
    /\[WARNING\] Planning loop exceeded/,
    /Continuing with the plan information gathered/,

    # Table orientation warnings
    /The table size exceeds the currently set width/,
    /Defaulting to vertical orientation/,

    # File Selection Help (complete help block)
    /📖 File Selection Help:/,
    /^\s+@\s+- Show all files$/,
    /^\s+@\.rb\s+- Show Ruby files only$/,
    /^\s+@config\s+- Show files with 'config' in name$/,
    %r{^\s+@lib/\s+- Show files in lib directory$},
    /^\s+@spec preview\s+- Show spec files with preview option$/,
    /^\s+@\.js case\s+- Show JavaScript files \(case sensitive\)$/,
    /⌨️  Selection Commands:/,
    /^\s+1-50\s+- Select file by number$/,
    /^\s+0\s+- Cancel selection$/,
    /^\s+-1\s+- Refine search$/,
    /^\s+p\s+- Preview selected file$/,
    /^\s+h\s+- Show this help$/,
    /^\s+• Files are sorted by relevance and type$/,
    /^\s+• Use extension filters for specific file types$/,
    /^\s+• Use directory filters to limit search scope$/,
    /^\s+• Preview option shows file content before selection$/,

    # Tree-sitter analysis output
    /🔍 Starting Tree-sitter static analysis\.\.\./,
    /📁 Root: /,
    /🗂️  KB Directory: /,
    /🌐 Languages: /,
    /🧵 Threads: \d+/,
    /📄 Found \d+ files to analyze/,
    /🔄 Parsing files in parallel\.\.\./,
    /Installing Tree-sitter grammar for \w+\.\.\./,
    /Grammar for \w+ marked as available/,
    /Warning: Tree-sitter parser not found for \w+:/,
    /Failed to load a parser for \w+/,
    /From ENV\['TREE_SITTER_PARSERS'\]:/,
    /From Defaults:/,
    %r{^\s+/\.vendor/parsers$},
    %r{^\s+/\.vendor/tree-sitter-parsers$},
    %r{^\s+/vendor/parsers$},
    %r{^\s+/vendor/tree-sitter-parsers$},
    %r{^\s+/parsers$},
    %r{^\s+/tree-sitter-parsers$},
    %r{^\s+/$},
    %r{^\s+/opt/local/lib$},
    %r{^\s+/opt/lib$},
    %r{^\s+/usr/local/lib$},
    %r{^\s+/usr/lib$},
    /📄 Written \w+\.json \(\d+ entries\)/,
    /✅ Tree-sitter analysis complete!/,
    /📊 Generated KB files in /,

    # Graph output (digraph, mermaid, JSON)
    /^digraph \w+ \{$/,
    /^\s+rankdir=\w+;$/,
    /^\s+node \[shape=\w+\];$/,
    /^\s+"?\w+"? -> "?\w+"? \[label="\w+"\];$/,
    /^\}$/,
    /^graph LR$/,
    /^\s+\w+ --> \w+$/,
    /^\{$/,
    /^\s+"nodes": \[$/,
    /^\s+"edges": \[$/,
    /^\s+\{$/,
    /^\s+"id": "[^"]+",?$/,
    /^\s+"label": "[^"]+",?$/,
    /^\s+"from": "[^"]+",?$/,
    /^\s+"to": "[^"]+",?$/,
    /^\s+\},?$/,
    /^\s+\],?$/,

    # Knowledge base summary output
    /🏗️  Symbols Summary$/,
    /^Module: \d+$/,
    /^Method: \d+$/,
    /^Class: \d+$/,
    /📦 Imports Summary$/,
    /^Require: \d+$/,
    /^Require_relative: \d+$/,
    /🔥 Code Hotspots \(Top \d+\)$/,
    /^\s+Score: \d+ \(Complexity: \d+, Touches: \d+\)$/,

    # Code signing and environment-manager errors (CI environment)
    /^error: Debug: Namespace set to "\w+" \(ignored\)$/,
    /^Debug: Key file set to "[^"]+" \(ignored, using server key\)$/,
    /^Error: signing failed: Signing failed:/,
    /signing operation failed: signing server returned status \d+:/,
    /^\s*Usage:$/,
    /^\s+environment-manager code-sign \[flags\]$/,
    /^Flags:$/,
    /^\s+-h, --help\s+help for code-sign$/,
    /^fatal: failed to write commit object$/,

    # Devcontainer preview output (features, env)
    /^\s+\+ ghcr\.io\/devcontainers\/features\//,
    /^\s+\+ AIDP_\w+=\w+$/,

    # Email validation warnings and errors
    /^\s+Invalid email format$/,
    /^\s+• This is a warning$/,
    /^Warning: [\w.]+@[\w.]+\.[\w.]+ was considered valid by email validation$/,

    # Git worktree additional messages
    /^No possible source branch, inferring '--orphan'$/,
    /^Preparing worktree \(new branch '[^']+'\)$/,
    /^Switched to a new branch '[^']+'$/,
    /^fatal: invalid reference: \w+$/,

    # Bundler deprecation warnings
    /^\[DEPRECATED\] The `--path` flag is deprecated/,
    /bundler invocations, which bundler will no longer do/,
    /Instead please use `bundle config set/,
    /and stop using this flag$/,

    # RSpec/RuboCop list items
    /^\s+- RSpec$/,
    /^\s+- RuboCop$/,
    /^\s+- Continuous Integration \/ lint \/ lint$/,

    # Test output artifacts
    /^test$/,
    /^\?\? \.aidp\/$/,

    # ANSI escape sequences (terminal control codes that leak)
    /\e\[2K/,
    /\e\[1G/,
    /\[2K/,
    /\[1G/,

    # Task filing and update messages
    /❌ Updated task \w+: abandoned/,
    /✅ Updated task \w+: done/,
    /🚧 Updated task \w+: in_progress/,
    /⚠️  Task not found:/,
    /📋 Filed task: .+ \(\w+\)/,
    /📋 Task Summary \(Project-wide\):/,
    /^\s+Total: \d+$/,
    /^\s+✅ Done: \d+$/,
    /^\s+🚧 In Progress: \d+$/,
    /^\s+⏳ Pending: \d+$/,

    # Provider warnings
    /⚠️  Failed to resolve provider \w+:/,
    /⚠️  All providers unavailable or failed/,
    /⚠️  Unable to parse \w+ response/,

    # KB Inspector data display
    /^\s+io_integration: \d+$/,
    /🔥 Code Hotspots$/,
    /^No hotspots data available$/,
    /^No APIs data available$/,
    /^No cycles data available$/,
    /^No seams data available$/,
    /^Unknown KB type: \w+$/,
    /^Available types: /,
    /^Unknown graph type: \w+$/,
    /^Available types: imports, calls, cycles$/,
    %r{^\s+[\w/]+\.rb:\d+$},  # File:line references like "test.rb:5"

    # KB parsing warnings
    /^Warning: Could not parse [^:]+: /,

    # Time estimates
    /⏱️  Estimated time remaining: [\d.]+ (seconds|minutes)/,

    # File selection hints
    /^\s+• Use @ to browse and select files$/,

    # Configuration error messages (full line)
    /^Failed to load configuration file /,

    # GitHub CLI errors
    /^GitHub CLI list failed:/,

    # Harness status display sections
    /💬 USER FEEDBACK STATUS/,
    /^\s+question: \w+$/,
    /^\s+question_count: \d+$/,
    /⚡ PERFORMANCE METRICS/,
    /^\s+Uptime: \w+$/,
    /^\s+Step Duration: \w+$/,
    /^\s+Provider Switches: \d+$/,
    /^\s+Error Rate: [\d.]+%$/,
    /✅ WORK COMPLETION STATUS/,
    # Note: Removed /^\s+Status: [\w\s]+$/ - tests verify harness status output like "Status: custom"
    /^\s+Steps Completed: \d+\/\d+$/,
    /🚨 ALERTS/,
    /^\s+🟡 High error rate$/,
    /🚫 RATE LIMIT STATUS/,
    /^\s+\w+:\w+: Rate Limited$/,
    /^\s+Reset Time: [\d:]+$/,
    /^\s+Retry After: \d+s$/,
    /^\s+Quota: \d+\/\d+$/,
    /🔄 RECOVERY STATUS/,
    /^\s+provider_switch: \w+$/,
    /^\s+new_provider: \w+$/,
    /🔌 PROVIDER INFORMATION/,
    /^\s+Available Providers: .+$/,
    /^\s+Provider Health:$/,
    /^\s+\w+: healthy \([\d.]+%\)$/,
    /🔒 CIRCUIT BREAKER STATUS/,
    /^\s+🟢 \w+: closed \(failures: \d+\)$/,
    /^\s+🔴 \w+: open \(failures: \d+\)$/,
    /📊 BASIC INFORMATION/,
    /^\s+Duration: \w+$/,
    /^\s+Provider: \w+$/,
    /^\s+Model: \w+$/,
    /^\s+Update Interval: \w+$/,
    /❌ ERROR INFORMATION/,
    /^\s+Total Errors: \d+$/,
    /^\s+By Severity:$/,
    /^\s+warning: \d+$/,
    /^\s+error: \d+$/,
    /^\s+By Provider:$/,
    /^\s+\w+: \d+$/,
    /🎫 TOKEN USAGE/,
    /^\s+\w+:$/,
    /^\s+\w+: \d+ used$/,
    /^\s+Remaining: \d+$/,
    /🔄 Harness Status - Detailed/,
    /^\s+Errors: \d+ total$/,
    /🔄 Harness Status$/,
    /🔄 Test Step \| \w+ \| \w+$/,
    /🔄 AIDP HARNESS - FULL STATUS REPORT/,
    /🚫 Rate limit reached/,
    /^\s+Waiting for reset at [\d:]+$/,
    /^\s+Remaining: \d+s$/,
    /^\s+Press Ctrl\+C to cancel$/,
    /❌ Harness ERROR/,
    /^\s+Error: .+$/,
    /^\s+Check logs for details$/,
    /✅ Harness COMPLETED/,
    /^\s+All workflows finished successfully!$/,
    /🚫 Rate limit - waiting\.\.\./,
    /^\s+Resets in: \d+s$/,
    /❌ Display Error: /,
    /^\s+Continuing with status updates\.\.\.$/,

    # Workstream cleanup messages
    # Note: Removed /^No workstreams found\.$/ and /^\s+Branch deleted$/ - tests verify this output
    /^Keeping workstream$/,
    /^Deletion cancelled$/,

    # Note: MCP Server output patterns removed - tests verify that output via capture_output
    # Note: Workstream status display patterns removed - tests verify that output via capture_output

    # Additional git worktree messages
    /^Switched to a new branch '[^']+'$/,
    /^fatal: invalid reference: [\w\/-]+$/,

    # Model discovery output
    /^✓ Found \d+ models for \w+:$/,
    /^\s+Mini tier: \d+ models$/,
    /^\s+Standard tier: \d+ models$/,
    /^\s+Advanced tier: \d+ models$/,
    /^📋 Proposed tier configuration:$/,
    /^\s+- claude-[\w-]+$/,
    /^✅ Thinking tiers configured successfully$/,
    /^✅ Output filtering configured$/,
    /^⚠️  No models discovered\. Ensure provider CLIs are installed\.$/,
    /^💡 You can configure tiers manually or run 'aidp models discover' later$/,

    # AI-Generated Filter Definitions
    /^🤖 AI-Generated Filter Definitions$/,
    /^\s+Generate custom filters for your test\/lint tools \(one-time AI call\)$/,
    /^⚠️  No test or lint commands configured\. Configure them first\.$/,

    # Detected stack
    /^📚 Detected stack: \w+$/,

    # Watch Mode Configuration
    /^👀 Watch Mode Configuration$/,
    /^🔒 Watch mode safety settings$/,
    /^📝 Author allowlist \(GitHub usernames allowed to trigger watch mode\)$/,
    /^\s+Leave empty to allow all authors \(not recommended for public repos\)$/,
    /^🏷️  Watch mode label configuration$/,
    /^\s+Configure GitHub issue and PR labels that trigger watch mode actions$/,
    /^📝 PR Change Request Configuration$/,
    /^\s+Configure how AIDP handles automated PR change requests$/,

    # Question prompts (standalone)
    /^question:$/,

    # Workflow selection menu output
    /^Choose a workflow:$/,
    /^⚙️ Custom Analysis$/,
    /^⚙️ Custom Step Selection$/,
    /^🔍 Quick Overview$/,
    /^🔬 Exploration\/Experiment$/,
    /^♻️ Legacy Modernization$/,
    /^🔀 Hybrid Mode - Analyze Then Execute$/,
    /^Includes:$/,
    /^\s+• .+$/,
    /^Available analyze steps:$/,
    /^Available execute steps:$/,
    /^You can mix analyze and execute steps for a custom hybrid workflow\.$/,
    /^⚠️  No steps selected, using default workflow$/,

    # Git worktree shell output (captured from shell commands)
    /^Preparing worktree \(new branch '[^']+'\)$/,
    /^HEAD is now at [a-f0-9]+ .+$/,

    # Configuration wizard status output not caught by other patterns
    /^✓ Cleanup complete$/,
    /^\s+Upstream: .+$/,
    /^\s+Last commit: .+$/,

    # Email validation test output
    /^Warning: [\w.@-]+ was considered valid by email validation$/,

    # Test error output
    /^\s+Test error$/
  ].freeze

  def say(message, **options)
    message_str = message.to_s

    # Suppress noisy messages in test output but still record them
    @messages << {message: message, options: options, type: :say}

    # Don't print to stdout if it matches suppression patterns
    return @responses[:say] if SUPPRESS_PATTERNS.any? { |pattern| message_str.match?(pattern) }

    puts message_str
    @responses[:say]
  end

  def warn(message, **options)
    @messages << {message: message, options: options, type: :warn}
    puts message
    @responses[:warn]
  end

  def error(message, **options)
    @messages << {message: message, options: options, type: :error}
    puts message
    @responses[:error]
  end

  def ok(message, **options)
    @messages << {message: message, options: options, type: :ok}
    puts message
    @responses[:ok]
  end

  def keypress(message, **options)
    @inputs << {message: message, options: options, type: :keypress}
    @responses[:keypress] || "\n"
  end

  # Additional methods that some classes might use
  def mask(message, **options)
    @inputs << {message: message, options: options, type: :mask}
    @responses[:mask] || ""
  end

  def confirm(message, **options)
    @inputs << {message: message, options: options, type: :confirm}
    @responses.key?(:confirm) ? @responses[:confirm] : true
  end

  def expand(message, choices, **options)
    @selections << {message: message, choices: choices, options: options, type: :expand}
    @responses[:expand] || choices.first[:value]
  end

  def slider(message, **options)
    @inputs << {message: message, options: options, type: :slider}
    @responses[:slider] || (options[:default] || 5)
  end

  def enum_select(message, choices, **options)
    @selections << {message: message, choices: choices, options: options, type: :enum_select}
    @responses[:enum_select] || choices.first
  end

  # Reset all recorded interactions - useful for testing multiple interactions
  def reset!
    @messages.clear
    @selections.clear
    @inputs.clear
  end

  # Convenience methods for testing
  def last_message
    @messages.last
  end

  def last_selection
    @selections.last
  end

  def last_input
    @inputs.last
  end

  def message_count
    @messages.length
  end

  def selection_count
    @selections.length
  end

  def input_count
    @inputs.length
  end
end
