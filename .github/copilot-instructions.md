# Copilot Instructions for AIDP

## Ruby Version Context
- This project targets **Ruby 3.0+** (modern Ruby versions)
- Use modern Ruby syntax and features:
  - Endless ranges: `[1..]` instead of `[1..-1]`
  - Pattern matching where appropriate
  - Modern hash syntax
  - Keyword arguments
- Ruby 2.x compatibility is not required (EOL versions)

## Code Style Preferences
- **Exception handling philosophy**: Let bugs crash early rather than masking them with rescues
  - Use `rescue StandardError => e` over bare `rescue => e` when rescue is warranted
  - Only rescue exceptions when:
    - Cleaning up external resources (files, network connections, etc.)
    - Providing graceful degradation for optional features
    - Converting between error types at API boundaries
    - Handling expected operational failures (network timeouts, missing files)
  - **Avoid** rescuing exceptions for:
    - Programming errors (NoMethodError, ArgumentError, etc.)
    - Configuration errors that should be fixed
    - Logic errors that indicate bugs
- Prefer `File.join` and `File::SEPARATOR` for path operations over string concatenation
- Extract common patterns into helper methods rather than inline duplication
- Use double quotes for require statements and strings with interpolation
- Single quotes for static strings without interpolation

## Architecture Context
- This is a Ruby gem for AI-assisted development and code analysis
- Dependencies declared in gemspec should be assumed available (no `if defined?` checks needed)
- Tree-sitter is used for AST parsing with graceful fallbacks to regex-based parsing
- Knowledge base (KB) files are JSON-based outputs for analysis results

## Dependencies
- All gems in the gemspec are required dependencies
- Tree-sitter parsers may not be available for all languages (fallbacks needed)
- Concurrent-ruby is available for parallel processing
- TTY-table is available for formatted output

## Performance Considerations
- File processing should use parallel execution where possible
- Caching is implemented for parsed file results
- Large codebases are a primary use case

## Security
- File downloads should include integrity verification when possible
- Avoid executing arbitrary code from parsed sources
- Sanitize file paths and user inputs