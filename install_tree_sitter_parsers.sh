#!/bin/bash

# Script to install Tree-sitter parsers from Faveod/tree-sitter-parsers
# This downloads pre-built parsers for the tree_sitter gem

# Configuration
VERSION="4.10"

echo "🔧 Installing Tree-sitter parsers from Faveod/tree-sitter-parsers..."

# Get absolute path to project directory
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create parser directory (use absolute path)
PARSER_DIR="$PROJECT_DIR/.aidp/parsers"
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

# Check for unsupported platform combinations
# Faveod/tree-sitter-parsers doesn't provide Linux ARM64 builds
if [ "$OS_SUFFIX" = "linux" ] && [ "$ARCH_SUFFIX" = "arm64" ]; then
  echo ""
  echo "⚠️  Pre-built parsers are NOT available for Linux ARM64"
  echo "🔨 Building parsers from source instead..."
  echo ""

  # Check for required build tools
  if ! command -v gcc >/dev/null 2>&1; then
    echo "❌ gcc not found. Please install build-essential"
    exit 1
  fi

  # Define parsers to build with their repo URLs
  # Format: "parser_name|repo_url"
  declare -a PARSERS=(
    "ruby|https://github.com/tree-sitter/tree-sitter-ruby"
    "json|https://github.com/tree-sitter/tree-sitter-json"
    "yaml|https://github.com/ikatyang/tree-sitter-yaml"
  )

  cd "$PARSER_DIR"

  for parser_info in "${PARSERS[@]}"; do
    # Split into name and URL
    IFS='|' read -r parser repo_url <<< "$parser_info"

    echo "📦 Building tree-sitter-${parser}..."

    # Create temp directory for building
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # Clone the parser repository
    git clone --quiet --depth 1 "$repo_url" "tree-sitter-${parser}" 2>/dev/null

    if [ $? -ne 0 ]; then
      echo "   ⚠️  Could not clone from ${repo_url}, skipping..."
      cd "$PARSER_DIR"
      rm -rf "$TEMP_DIR"
      continue
    fi

    cd "tree-sitter-${parser}"

    # Build the parser
    if [ -f "src/parser.c" ]; then
      echo "   Compiling ${parser}.so..."
      gcc -shared -fPIC src/parser.c -o "${parser}.so" -I./src 2>/dev/null

      if [ $? -eq 0 ] && [ -f "${parser}.so" ]; then
        cp "${parser}.so" "$PARSER_DIR/"
        echo "   ✅ ${parser}.so built successfully"
      else
        echo "   ⚠️  Failed to build ${parser}.so"
      fi
    else
      echo "   ⚠️  No src/parser.c found for ${parser}"
    fi

    # Clean up
    cd "$PARSER_DIR"
    rm -rf "$TEMP_DIR"
  done

  echo ""
  echo "🎉 Parser build complete!"
  echo "📁 Location: $(pwd)"
  echo ""
  echo "🔍 Built parsers:"
  ls -lh *.so 2>/dev/null || echo "   No parsers built"
  echo ""
  echo "📝 Next steps:"
  echo "   1. Set TREE_SITTER_PARSERS environment variable:"
  echo "      export TREE_SITTER_PARSERS=\"$(pwd)\""
  echo ""
  exit 0
fi

# Download URL for the latest release
DOWNLOAD_URL="https://github.com/Faveod/tree-sitter-parsers/releases/download/v${VERSION}/tree-sitter-parsers-${VERSION}-${OS_SUFFIX}-${ARCH_SUFFIX}.tar.gz"

echo "📥 Downloading parsers from: $DOWNLOAD_URL"

# Download and extract
cd "$PARSER_DIR"
curl -L -f -o tree-sitter-parsers.tar.gz "$DOWNLOAD_URL"

if [ $? -eq 0 ]; then
  echo "✅ Download successful"

  # Verify file size (should be more than 100 bytes for a valid archive)
  FILE_SIZE=$(stat -c%s tree-sitter-parsers.tar.gz 2>/dev/null || stat -f%z tree-sitter-parsers.tar.gz 2>/dev/null)
  if [ "$FILE_SIZE" -lt 100 ]; then
    echo "❌ Downloaded file is too small (${FILE_SIZE} bytes), likely an error page"
    echo "📄 File content:"
    cat tree-sitter-parsers.tar.gz
    rm tree-sitter-parsers.tar.gz
    exit 1
  fi
  echo "✅ File size: ${FILE_SIZE} bytes"

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
    rm -f tree-sitter-parsers.tar.gz
    exit 1
  fi
else
  echo "❌ Failed to download parsers"
  echo "🔍 Check if the release exists: https://github.com/Faveod/tree-sitter-parsers/releases/tag/v${VERSION}"
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
