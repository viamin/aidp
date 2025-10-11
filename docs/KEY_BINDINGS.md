# Key Bindings in AIDP

AIDP supports **full readline-style key combinations** for text input using Ruby's built-in **[Reline](https://github.com/ruby/reline)** library. This provides a complete Emacs-style editing experience in the guided workflow (copilot mode).

## ✅ Key Bindings Status

**In Copilot Mode (Guided Workflow)**: ✅ **FULL support** via Reline
**In Regular TTY::Prompt**: ⚠️  Limited support (basic cursor movement only)

## Supported Key Combinations

All of these work in **copilot mode** with the `EnhancedInput` class:

### Cursor Movement

| Key Combination | Action |
|----------------|--------|
| `Ctrl-A` | Move cursor to beginning of line ✅ |
| `Ctrl-E` | Move cursor to end of line ✅ |
| `Left Arrow` | Move cursor left one character ✅ |
| `Right Arrow` | Move cursor right one character ✅ |
| `Alt-B` | Move cursor left one word ✅ |
| `Alt-F` | Move cursor right one word ✅ |
| `Home` | Jump to beginning of line ✅ |
| `End` | Jump to end of line ✅ |

### Text Editing

| Key Combination | Action |
|----------------|--------|
| `Ctrl-W` | Delete word backward (before cursor) ✅ |
| `Ctrl-K` | Kill text from cursor to end of line ✅ |
| `Ctrl-U` | Kill entire line ✅ |
| `Ctrl-D` | Delete character forward (at cursor) ✅ |
| `Ctrl-H` or `Backspace` | Delete character backward (before cursor) ✅ |
| `Ctrl-T` | Transpose (swap) characters ✅ |
| `Delete` | Delete character forward (at cursor) ✅ |
| `Alt-D` | Delete word forward ✅ |

### Navigation & History

| Key Combination | Action |
|----------------|--------|
| `Up Arrow` | Previous history item ✅ |
| `Down Arrow` | Next history item ✅ |
| `Ctrl-R` | Reverse history search ✅ |

### Other

| Key Combination | Action |
|----------------|--------|
| `Ctrl-C` | Cancel/Interrupt input ✅ |
| `Ctrl-D` | End of input (when line is empty) ✅ |
| `Tab` | Auto-completion (context-dependent) ✅ |
| `Enter` | Submit input ✅ |

## Implementation

AIDP uses two different input systems:

### 1. EnhancedInput (Copilot Mode) - ✅ FULL Support

The `Aidp::CLI::EnhancedInput` class uses **Reline** for full readline editing:

```ruby
require_relative 'lib/aidp/cli/enhanced_input'

input = Aidp::CLI::EnhancedInput.new
answer = input.ask("Your goal: ")
# Ctrl-W, Ctrl-A, Ctrl-K, etc. all work! ✅
```

**When it's used:**
- Guided workflow (copilot mode) - enabled by default
- Any code that explicitly creates an `EnhancedInput` instance

### 2. TTY::Prompt (Legacy) - ⚠️ Limited Support

Standard [TTY::Prompt](https://github.com/piotrmurach/tty-prompt) provides limited editing capabilities. It detects key presses but doesn't implement full line editing behavior.

## Usage Examples

### Standard Input

```ruby
require 'tty-prompt'

prompt = TTY::Prompt.new
answer = prompt.ask("Enter your goal:")

# All key bindings work automatically!
# Try: "This is a test" then:
# - Ctrl-A (cursor jumps to beginning)
# - Ctrl-E (cursor jumps to end)
# - Ctrl-W (deletes "test")
```

### Enhanced Input with Hints

```ruby
require_relative 'lib/aidp/cli/enhanced_input'

input = Aidp::CLI::EnhancedInput.new
input.enable_hints!  # Shows helpful hint on first use
answer = input.ask("Enter text: ")
```

### Demo Script

Run the demo script to try out the key bindings interactively:

```bash
ruby examples/key_bindings_demo.rb
```

## Terminal Compatibility

These key bindings work in most modern terminals including:
- macOS Terminal
- iTerm2
- GNOME Terminal
- xterm
- Windows Terminal
- VS Code integrated terminal

**Note:** Some terminal emulators may override certain key combinations. For example, some terminals reserve `Ctrl-W` for closing tabs. Check your terminal settings if a key binding doesn't work as expected.

## Troubleshooting

### Key binding not working?

1. **Check terminal settings**: Some terminals override certain key combinations
2. **Verify TTY mode**: Ensure stdin is connected to a TTY (not a pipe or file)
3. **Test with demo**: Run `ruby examples/key_bindings_demo.rb` to verify

### Want to customize key bindings?

TTY::Reader supports custom key bindings. See the [TTY::Reader documentation](https://github.com/piotrmurach/tty-reader#3-subscribe) for details on subscribing to key events and defining custom behavior.
