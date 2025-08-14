# Contributing to AI Dev Pipeline (aidp)

## Development Setup

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec standardrb

# Auto-fix linting issues
bundle exec standardrb --fix
```

## Conventional Commits

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automated releases via release-please.

### Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code (white-space, formatting, etc)
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `perf`: A code change that improves performance
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to the build process or auxiliary tools

### Examples

```bash
# New feature
git commit -m "feat: add questions file reading functionality"

# Bug fix
git commit -m "fix: resolve stdin nil error in cursor provider tests"

# Documentation
git commit -m "docs: update README with new workflow instructions"

# Refactor
git commit -m "refactor: extract questions file logic to separate method"

# Breaking change
git commit -m "feat!: change CLI command from 'run' to 'execute'

BREAKING CHANGE: The 'run' command has been renamed to 'execute' for clarity."
```

### Release Process

1. **Make changes** with conventional commit messages
2. **Push to main** - release-please will create a PR for the next version
3. **Review and merge** the release PR
4. **Tag is created** automatically when the PR is merged

### Bootstrap Release

If this is a new repository without any releases, run:

```bash
./scripts/bootstrap-release.sh
```

This creates an initial v0.1.0 release so release-please can work properly.

## Questions?

If you have questions about the development process, please open an issue or reach out to the maintainers.
