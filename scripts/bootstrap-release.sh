#!/bin/bash

# Bootstrap script for release-please
# This creates an initial release so release-please can work properly

set -e

echo "🚀 Bootstrapping initial release for release-please..."

# Check if we're on main branch
if [[ $(git branch --show-current) != "main" ]]; then
    echo "❌ Error: Must be on main branch"
    exit 1
fi

# Check if there are any existing tags
if git tag | grep -q "v"; then
    echo "❌ Error: Release tags already exist. Remove them first if you want to re-bootstrap."
    exit 1
fi

# Create initial v0.1.0 tag
echo "📦 Creating initial v0.1.0 tag..."
git tag -a v0.1.0 -m "Initial release"

# Push the tag
echo "📤 Pushing tag to remote..."
git push origin v0.1.0

echo "✅ Bootstrap complete! release-please should now work properly."
echo ""
echo "Next steps:"
echo "1. Make changes with conventional commit messages (feat:, fix:, etc.)"
echo "2. Push to main"
echo "3. release-please will create a PR for the next version"
