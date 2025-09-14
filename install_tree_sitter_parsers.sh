#!/bin/bash

# Script to install Tree-sitter parsers from Faveod/tree-sitter-parsers
# This downloads pre-built parsers for the tree_sitter gem

# Configuration
VERSION="4.9"

echo "🔧 Installing Tree-sitter parsers from Faveod/tree-sitter-parsers..."

# Create parser directory
PARSER_DIR=".aidp/parsers"
mkdir -p "$PARSER_DIR"

# Detect system architecture
ARCH=$(uname -m)
OS=$(uname -s)

echo "📋 System: $OS $ARCH"

# Map architecture to download format
case "$ARCH" in
  "x86_64")
    ARCH_SUFFIX="x64"
    ;;
  "arm64"|"aarch64")
    ARCH_SUFFIX="arm64"
    ;;
  *)
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# Map OS to download format
case "$OS" in
  "Darwin")
    OS_SUFFIX="macos"
    ;;
  "Linux")
    OS_SUFFIX="linux"
    ;;
  *)
    echo "❌ Unsupported OS: $OS"
    exit 1
    ;;
esac

# Download URL for the latest release
DOWNLOAD_URL="https://github.com/Faveod/tree-sitter-parsers/releases/download/v${VERSION}/tree-sitter-parsers-${VERSION}-${OS_SUFFIX}-${ARCH_SUFFIX}.tar.gz"

echo "📥 Downloading parsers from: $DOWNLOAD_URL"

# Download and extract
cd "$PARSER_DIR"
curl -L -o tree-sitter-parsers.tar.gz "$DOWNLOAD_URL"

if [ $? -eq 0 ]; then
  echo "✅ Download successful"

  # Extract the archive
  tar -xzf tree-sitter-parsers.tar.gz

  if [ $? -eq 0 ]; then
    echo "✅ Extraction successful"

    # Move files from subdirectory to current directory
    if [ -d "tree-sitter-parsers" ]; then
      mv tree-sitter-parsers/* .
      rmdir tree-sitter-parsers
    fi

    # List what was extracted
    echo "📁 Extracted files:"
    ls -la

    # Clean up the archive
    rm tree-sitter-parsers.tar.gz

    echo ""
    echo "🎉 Tree-sitter parsers installed successfully!"
    echo "📁 Location: $(pwd)"
    echo ""
    echo "🔍 Available parsers:"
    find . -name "*.so" -o -name "*.dylib" | head -10

  else
    echo "❌ Failed to extract archive"
    exit 1
  fi
else
  echo "❌ Failed to download parsers"
  exit 1
fi

echo ""
echo "📝 Next steps:"
echo "   1. Set TREE_SITTER_PARSERS environment variable:"
echo "      export TREE_SITTER_PARSERS=\"$(pwd)\""
echo ""
echo "   2. Test the installation:"
echo "      bundle exec rspec spec/aidp/analysis/tree_sitter_scan_spec.rb"
echo ""
echo "   3. To make the environment variable permanent, add to your shell profile:"
echo "      echo 'export TREE_SITTER_PARSERS=\"$(pwd)\"' >> ~/.zshrc"
