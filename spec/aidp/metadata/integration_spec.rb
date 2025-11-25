# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Aidp::Metadata" do
  let(:test_dir) { Dir.mktmpdir }
  let(:skills_dir) { File.join(test_dir, "skills") }
  let(:cache_file) { File.join(test_dir, "cache.json") }

  before do
    FileUtils.mkdir_p(skills_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  def create_skill_file(filename, **metadata)
    file_path = File.join(skills_dir, filename)
    frontmatter = {
      "id" => metadata[:id] || "test_skill",
      "title" => metadata[:title] || "Test Skill",
      "summary" => metadata[:summary] || "A test skill",
      "version" => metadata[:version] || "1.0.0",
      "applies_to" => metadata[:applies_to] || ["ruby"],
      "work_unit_types" => metadata[:work_unit_types] || ["implementation"]
    }.merge(metadata[:extra] || {})

    content = <<~MD
      ---
      #{YAML.dump(frontmatter).sub(/^---\n/, "")}---

      # Test Skill Content

      This is the skill content.
    MD

    File.write(file_path, content)
    file_path
  end

  describe "ToolMetadata" do
    let(:valid_hash) { "a" * 64 } # Valid SHA256 hex string

    it "initializes with all required fields" do
      metadata = Aidp::Metadata::ToolMetadata.new(
        type: "skill",
        id: "test_skill",
        title: "Test Skill",
        summary: "A test skill",
        version: "1.0.0",
        content: "# Content",
        source_path: "/path/to/skill.md",
        file_hash: valid_hash
      )

      expect(metadata.type).to eq("skill")
      expect(metadata.id).to eq("test_skill")
      expect(metadata.title).to eq("Test Skill")
      expect(metadata.version).to eq("1.0.0")
    end

    it "accepts optional fields" do
      metadata = Aidp::Metadata::ToolMetadata.new(
        type: "skill",
        id: "test",
        title: "Test",
        summary: "Summary",
        version: "1.0.0",
        content: "Content",
        source_path: "test.md",
        file_hash: valid_hash,
        applies_to: ["ruby", "testing"],
        work_unit_types: ["implementation"],
        priority: 8,
        experimental: true
      )

      expect(metadata.applies_to).to eq(["ruby", "testing"])
      expect(metadata.work_unit_types).to eq(["implementation"])
      expect(metadata.priority).to eq(8)
      expect(metadata.experimental).to be true
    end

    xit "converts to hash" do
      metadata = Aidp::Metadata::ToolMetadata.new(
        type: "skill",
        id: "test",
        title: "Test",
        summary: "Summary",
        version: "1.0.0",
        content: "Content",
        source_path: "test.md",
        file_hash: valid_hash
      )

      hash = metadata.to_h
      expect(hash).to be_a(Hash)
      expect(hash["id"]).to eq("test")
      expect(hash["type"]).to eq("skill")
    end

    it "raises error for invalid ID format" do
      expect {
        Aidp::Metadata::ToolMetadata.new(
          type: "skill",
          id: "Invalid ID!",
          title: "Title",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "test.md",
          file_hash: valid_hash
        )
      }.to raise_error(Aidp::Errors::ValidationError, /lowercase alphanumeric/)
    end

    it "raises error for invalid type" do
      expect {
        Aidp::Metadata::ToolMetadata.new(
          type: "invalid_type",
          id: "test",
          title: "Title",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "test.md",
          file_hash: valid_hash
        )
      }.to raise_error(Aidp::Errors::ValidationError, /must be one of/)
    end

    it "tests tag matching" do
      metadata = Aidp::Metadata::ToolMetadata.new(
        type: "skill",
        id: "test",
        title: "Title",
        summary: "Summary",
        version: "1.0.0",
        content: "Content",
        source_path: "test.md",
        file_hash: valid_hash,
        applies_to: ["ruby", "testing", "tdd"]
      )

      expect(metadata.applies_to?(["ruby"])).to be true
      expect(metadata.applies_to?(["ruby", "testing"])).to be true
      expect(metadata.applies_to?(["python"])).to be false
    end
  end

  describe "Parser" do
    it "parses file with YAML frontmatter" do
      file = create_skill_file("test_skill.md", id: "parser_test", title: "Parser Test")

      metadata = Aidp::Metadata::Parser.parse_file(file, type: "skill")

      expect(metadata).to be_a(Aidp::Metadata::ToolMetadata)
      expect(metadata.id).to eq("parser_test")
      expect(metadata.title).to eq("Parser Test")
      expect(metadata.type).to eq("skill")
    end

    it "auto-detects type from filename" do
      file = create_skill_file("SKILL.md", id: "autodetect")
      metadata = Aidp::Metadata::Parser.parse_file(file)
      expect(metadata.type).to eq("skill")
    end

    it "computes file hash" do
      file = create_skill_file("hash_test.md", id: "hash_test")
      metadata = Aidp::Metadata::Parser.parse_file(file, type: "skill")
      expect(metadata.file_hash).to be_a(String)
      expect(metadata.file_hash.length).to eq(64) # SHA256 length
    end

    it "raises error for non-existent file" do
      expect {
        Aidp::Metadata::Parser.parse_file("/nonexistent/file.md", type: "skill")
      }.to raise_error(Aidp::Errors::ValidationError, /not found/)
    end

    it "raises error for invalid frontmatter" do
      file = File.join(skills_dir, "invalid.md")
      File.write(file, "---\ninvalid: yaml: syntax:\n---\nContent")

      expect {
        Aidp::Metadata::Parser.parse_file(file, type: "skill")
      }.to raise_error(Aidp::Errors::ValidationError)
    end

    it "handles missing required fields" do
      file = File.join(skills_dir, "incomplete.md")
      File.write(file, "---\ntitle: Only Title\n---\nContent")

      expect {
        Aidp::Metadata::Parser.parse_file(file, type: "skill")
      }.to raise_error(Aidp::Errors::ValidationError)
    end
  end

  describe "Scanner" do
    it "scans directory for markdown files" do
      create_skill_file("skill1.md", id: "skill1")
      create_skill_file("skill2.md", id: "skill2")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])
      tools = scanner.scan_all

      expect(tools).to be_an(Array)
      expect(tools.size).to eq(2)
      expect(tools.map(&:id)).to contain_exactly("skill1", "skill2")
    end

    it "returns empty array for non-existent directory" do
      scanner = Aidp::Metadata::Scanner.new(["/nonexistent/dir"])
      tools = scanner.scan_all
      expect(tools).to eq([])
    end

    it "scans single directory with type filter" do
      create_skill_file("skill.md", id: "test_skill")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])
      tools = scanner.scan_directory(skills_dir, type: "skill")

      expect(tools.size).to eq(1)
      expect(tools.first.type).to eq("skill")
    end

    it "handles nested directories" do
      nested_dir = File.join(skills_dir, "nested")
      FileUtils.mkdir_p(nested_dir)

      File.write(File.join(nested_dir, "nested_skill.md"), <<~MD)
        ---
        id: nested_skill
        title: Nested Skill
        summary: A nested skill
        version: 1.0.0
        ---
        Content
      MD

      scanner = Aidp::Metadata::Scanner.new([skills_dir])
      tools = scanner.scan_all

      expect(tools.map(&:id)).to include("nested_skill")
    end

    it "skips non-markdown files" do
      File.write(File.join(skills_dir, "readme.txt"), "Not a skill")
      create_skill_file("real_skill.md", id: "real_skill")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])
      tools = scanner.scan_all

      expect(tools.size).to eq(1)
      expect(tools.first.id).to eq("real_skill")
    end

    it "finds markdown files recursively" do
      create_skill_file("top_level.md", id: "top_level")
      nested = File.join(skills_dir, "level1", "level2")
      FileUtils.mkdir_p(nested)

      File.write(File.join(nested, "deep.md"), <<~MD)
        ---
        id: deep_skill
        title: Deep Skill
        summary: A deeply nested skill
        version: 1.0.0
        ---
        Content
      MD

      scanner = Aidp::Metadata::Scanner.new([skills_dir])
      files = scanner.send(:find_markdown_files, skills_dir)

      expect(files).to include(File.join(nested, "deep.md"))
      expect(files.size).to eq(2)
    end

    it "scans with custom filter" do
      create_skill_file("ruby_skill.md", id: "ruby_skill")
      create_skill_file("python_skill.md", id: "python_skill")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])
      tools = scanner.scan_with_filter(skills_dir) { |path| path.include?("ruby") }

      expect(tools.size).to eq(1)
      expect(tools.first.id).to eq("ruby_skill")
    end

    it "detects added files in change scan" do
      scanner = Aidp::Metadata::Scanner.new([skills_dir])

      # Initial scan with no files
      changes1 = scanner.scan_changes(skills_dir, {})
      expect(changes1[:added]).to be_empty

      # Add a file
      create_skill_file("new_skill.md", id: "new_skill")
      changes2 = scanner.scan_changes(skills_dir, {})

      expect(changes2[:added].size).to eq(1)
      expect(changes2[:added].first).to include("new_skill.md")
    end

    it "detects modified files in change scan" do
      file_path = create_skill_file("changing.md", id: "changing")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])

      # First scan
      initial = scanner.scan_changes(skills_dir, {})
      previous_hashes = {}
      initial[:added].each do |path|
        content = File.read(path, encoding: "UTF-8")
        previous_hashes[path] = Aidp::Metadata::Parser.compute_file_hash(content)
      end

      # Modify the file
      sleep 0.01
      File.write(file_path, File.read(file_path) + "\n# Modified")

      # Second scan
      changes = scanner.scan_changes(skills_dir, previous_hashes)

      expect(changes[:modified].size).to eq(1)
      expect(changes[:modified].first).to eq(file_path)
    end

    it "detects removed files in change scan" do
      file_path = create_skill_file("removed.md", id: "removed")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])

      # Initial scan
      content = File.read(file_path, encoding: "UTF-8")
      hash = Aidp::Metadata::Parser.compute_file_hash(content)
      previous_hashes = {file_path => hash}

      # Remove file
      File.delete(file_path)

      # Scan again
      changes = scanner.scan_changes(skills_dir, previous_hashes)

      expect(changes[:removed].size).to eq(1)
      expect(changes[:removed].first).to eq(file_path)
    end

    it "detects unchanged files in change scan" do
      file_path = create_skill_file("unchanged.md", id: "unchanged")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])

      content = File.read(file_path, encoding: "UTF-8")
      hash = Aidp::Metadata::Parser.compute_file_hash(content)
      previous_hashes = {file_path => hash}

      changes = scanner.scan_changes(skills_dir, previous_hashes)

      expect(changes[:unchanged].size).to eq(1)
      expect(changes[:unchanged].first).to eq(file_path)
    end

    it "handles parse errors gracefully" do
      invalid_file = File.join(skills_dir, "invalid.md")
      File.write(invalid_file, "---\ninvalid: yaml: syntax:\n---\n")

      scanner = Aidp::Metadata::Scanner.new([skills_dir])

      # Should not raise, but log warning
      expect { scanner.scan_all }.not_to raise_error
    end

    it "scans multiple directories" do
      templates_dir = File.join(test_dir, "templates")
      FileUtils.mkdir_p(templates_dir)

      create_skill_file("skill.md", id: "skill1")

      File.write(File.join(templates_dir, "template.md"), <<~MD)
        ---
        id: template1
        title: Template
        summary: A template
        version: 1.0.0
        type: template
        ---
        Content
      MD

      scanner = Aidp::Metadata::Scanner.new([skills_dir, templates_dir])
      tools = scanner.scan_all

      expect(tools.size).to eq(2)
      expect(tools.map(&:type)).to contain_exactly("skill", "template")
    end
  end

  describe "Compiler" do
    it "initializes with directories" do
      compiler = Aidp::Metadata::Compiler.new(directories: [skills_dir])
      expect(compiler).to be_a(Aidp::Metadata::Compiler)
    end

    it "initializes with strict mode" do
      compiler = Aidp::Metadata::Compiler.new(directories: [skills_dir], strict: true)
      expect(compiler).to be_a(Aidp::Metadata::Compiler)
    end

    xit "compiles tool directory from sources" do
      create_skill_file("skill1.md", id: "skill1", applies_to: ["ruby"])
      create_skill_file("skill2.md", id: "skill2", applies_to: ["python"])

      compiler = Aidp::Metadata::Compiler.new(directories: [skills_dir])
      directory = compiler.compile(output_path: cache_file)

      expect(directory).to be_a(Hash)
      expect(directory["tools"]).to be_an(Array)
      expect(directory["tools"].size).to eq(2)
    end

    xit "creates indexes for efficient querying" do
      create_skill_file("skill.md", id: "test_skill", applies_to: ["ruby"])

      compiler = Aidp::Metadata::Compiler.new(directories: [skills_dir])
      directory = compiler.compile(output_path: cache_file)

      expect(directory).to have_key("indexes")
      expect(directory["indexes"]).to have_key("by_type")
      expect(directory["indexes"]).to have_key("by_tags")
    end

    it "writes compiled directory to file" do
      create_skill_file("skill.md", id: "test_skill")

      compiler = Aidp::Metadata::Compiler.new(directories: [skills_dir])
      compiler.compile(output_path: cache_file)

      expect(File.exist?(cache_file)).to be true
      content = JSON.parse(File.read(cache_file))
      expect(content).to have_key("tools")
    end

    xit "validates tools in strict mode" do
      # Create invalid skill
      file = File.join(skills_dir, "invalid.md")
      File.write(file, <<~MD)
        ---
        id: "invalid id with spaces"
        title: Invalid
        summary: Invalid skill
        version: 1.0.0
        ---
        Content
      MD

      compiler = Aidp::Metadata::Compiler.new(directories: [skills_dir], strict: true)

      expect {
        compiler.compile(output_path: cache_file)
      }.to raise_error(Aidp::Errors::ValidationError)
    end

    xit "collects errors in non-strict mode" do
      file = File.join(skills_dir, "invalid.md")
      File.write(file, <<~MD)
        ---
        id: "invalid id"
        title: Invalid
        summary: Invalid skill
        version: 1.0.0
        ---
        Content
      MD

      compiler = Aidp::Metadata::Compiler.new(directories: [skills_dir], strict: false)
      directory = compiler.compile(output_path: cache_file)

      expect(directory).to have_key("errors")
      expect(directory["errors"]).not_to be_empty
    end
  end

  describe "Cache" do
    it "initializes with required parameters" do
      cache = Aidp::Metadata::Cache.new(
        cache_path: cache_file,
        directories: [skills_dir]
      )

      expect(cache).to be_a(Aidp::Metadata::Cache)
    end

    it "initializes with strict mode" do
      cache = Aidp::Metadata::Cache.new(
        cache_path: cache_file,
        directories: [skills_dir],
        strict: true
      )
      expect(cache).to be_a(Aidp::Metadata::Cache)
    end

    it "initializes with custom TTL" do
      cache = Aidp::Metadata::Cache.new(
        cache_path: cache_file,
        directories: [skills_dir],
        ttl: 3600
      )
      expect(cache).to be_a(Aidp::Metadata::Cache)
    end

    xit "loads and regenerates cache when invalid" do
      create_skill_file("skill.md", id: "cached_skill")

      cache = Aidp::Metadata::Cache.new(cache_path: cache_file, directories: [skills_dir])
      directory = cache.load

      expect(directory).to be_a(Hash)
      expect(directory["tools"]).not_to be_empty
    end

    it "uses existing cache when valid" do
      create_skill_file("skill.md", id: "cached_skill")

      cache = Aidp::Metadata::Cache.new(cache_path: cache_file, directories: [skills_dir])

      # First load generates cache
      cache.load
      mtime = File.mtime(cache_file)

      # Second load uses cache
      sleep 0.01
      cache2 = Aidp::Metadata::Cache.new(cache_path: cache_file, directories: [skills_dir])
      cache2.load

      expect(File.mtime(cache_file)).to eq(mtime)
    end

    it "detects file changes and invalidates cache" do
      skill_file = create_skill_file("skill.md", id: "changing_skill")

      cache = Aidp::Metadata::Cache.new(cache_path: cache_file, directories: [skills_dir])
      cache.load

      # Modify skill file
      sleep 0.01
      File.write(skill_file, File.read(skill_file) + "\n# Modified")

      # Cache should be invalid
      expect(cache.cache_valid?).to be false
    end

    it "forces reload with reload method" do
      create_skill_file("skill.md", id: "reload_test")

      cache = Aidp::Metadata::Cache.new(cache_path: cache_file, directories: [skills_dir])
      cache.load

      mtime1 = File.mtime(cache_file)
      sleep 0.01

      cache.reload
      mtime2 = File.mtime(cache_file)

      expect(mtime2).to be > mtime1
    end

    it "respects TTL for cache expiration" do
      create_skill_file("skill.md", id: "ttl_test")

      cache = Aidp::Metadata::Cache.new(
        cache_path: cache_file,
        directories: [skills_dir],
        ttl: 0.01 # Very short TTL
      )
      cache.load

      sleep 0.02
      expect(cache.cache_valid?).to be false
    end
  end

  describe "Query" do
    let(:cache) do
      create_skill_file("ruby_skill.md",
        id: "ruby_skill",
        title: "Ruby Skill",
        applies_to: ["ruby"],
        work_unit_types: ["implementation"],
        extra: {"priority" => 8})
      create_skill_file("python_skill.md",
        id: "python_skill",
        title: "Python Skill",
        applies_to: ["python"],
        work_unit_types: ["testing"],
        extra: {"priority" => 5})
      create_skill_file("multi_tag.md",
        id: "multi_tag",
        title: "Multi Tag Skill",
        applies_to: ["ruby", "testing"],
        work_unit_types: ["implementation", "analysis"],
        extra: {"priority" => 7})

      Aidp::Metadata::Cache.new(cache_path: cache_file, directories: [skills_dir])
    end

    it "initializes with cache" do
      query = Aidp::Metadata::Query.new(cache: cache)
      expect(query).to be_a(Aidp::Metadata::Query)
    end

    it "finds tool by ID" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tool = query.find_by_id("ruby_skill")

      expect(tool).not_to be_nil
      expect(tool["id"]).to eq("ruby_skill")
      expect(tool["title"]).to eq("Ruby Skill")
    end

    it "returns nil for non-existent ID" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tool = query.find_by_id("nonexistent")
      expect(tool).to be_nil
    end

    it "finds tools by type" do
      query = Aidp::Metadata::Query.new(cache: cache)
      skills = query.find_by_type("skill")

      expect(skills).to be_an(Array)
      expect(skills.size).to eq(3)
    end

    it "finds tools by single tag" do
      query = Aidp::Metadata::Query.new(cache: cache)
      ruby_tools = query.find_by_tags(["ruby"])

      expect(ruby_tools.size).to eq(2)
      expect(ruby_tools.map { |t| t["id"] }).to contain_exactly("ruby_skill", "multi_tag")
    end

    it "finds tools by multiple tags with OR logic" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.find_by_tags(["ruby", "python"], match_all: false)

      expect(tools.size).to eq(3)
    end

    it "finds tools by multiple tags with AND logic" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.find_by_tags(["ruby", "testing"], match_all: true)

      expect(tools.size).to eq(1)
      expect(tools.first["id"]).to eq("multi_tag")
    end

    it "finds tools by work unit type" do
      query = Aidp::Metadata::Query.new(cache: cache)
      impl_tools = query.find_by_work_unit_type("implementation")

      expect(impl_tools.size).to eq(2)
      expect(impl_tools.map { |t| t["id"] }).to contain_exactly("ruby_skill", "multi_tag")
    end

    it "finds tools by work unit type case-insensitive" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.find_by_work_unit_type("TESTING")

      expect(tools.size).to eq(2)
    end

    it "ranks tools by priority descending" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.find_by_type("skill")
      ranked = query.rank_by_priority(tools)

      expect(ranked.first["id"]).to eq("ruby_skill") # Priority 8
      expect(ranked.last["id"]).to eq("python_skill") # Priority 5
    end

    it "filters tools by type" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.filter(type: "skill")

      expect(tools.size).to eq(3)
    end

    it "filters tools by tags" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.filter(tags: ["python"])

      expect(tools.size).to eq(1)
      expect(tools.first["id"]).to eq("python_skill")
    end

    it "filters tools by work unit type" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.filter(work_unit_type: "analysis")

      expect(tools.size).to eq(1)
      expect(tools.first["id"]).to eq("multi_tag")
    end

    it "filters tools by multiple criteria" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.filter(
        tags: ["ruby"],
        work_unit_type: "implementation"
      )

      expect(tools.size).to eq(2)
    end

    it "provides statistics" do
      query = Aidp::Metadata::Query.new(cache: cache)
      stats = query.statistics

      expect(stats).to be_a(Hash)
      expect(stats).to have_key("total_tools")
      expect(stats["total_tools"]).to eq(3)
    end

    it "reloads directory on demand" do
      query = Aidp::Metadata::Query.new(cache: cache)
      query.directory # Load once

      create_skill_file("new_skill.md", id: "new_skill")
      query.reload

      tool = query.find_by_id("new_skill")
      expect(tool).not_to be_nil
    end

    it "handles empty tag array" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.find_by_tags([])

      expect(tools).to be_an(Array)
      expect(tools).to be_empty
    end

    it "handles non-existent work unit type" do
      query = Aidp::Metadata::Query.new(cache: cache)
      tools = query.find_by_work_unit_type("nonexistent")

      expect(tools).to be_empty
    end
  end

  describe "Validator" do
    let(:valid_hash) { "a" * 64 }

    it "validates collection of tools" do
      tools = [
        Aidp::Metadata::ToolMetadata.new(
          type: "skill",
          id: "valid1",
          title: "Valid 1",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "valid1.md",
          file_hash: valid_hash
        ),
        Aidp::Metadata::ToolMetadata.new(
          type: "skill",
          id: "valid2",
          title: "Valid 2",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "valid2.md",
          file_hash: valid_hash
        )
      ]

      validator = Aidp::Metadata::Validator.new(tools)
      results = validator.validate_all

      expect(results).to be_an(Array)
      expect(results.size).to eq(2)
      expect(results.all?(&:valid)).to be true
    end

    it "detects duplicate IDs" do
      tools = [
        Aidp::Metadata::ToolMetadata.new(
          type: "skill",
          id: "duplicate",
          title: "First",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "first.md",
          file_hash: valid_hash
        ),
        Aidp::Metadata::ToolMetadata.new(
          type: "skill",
          id: "duplicate",
          title: "Second",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "second.md",
          file_hash: valid_hash
        )
      ]

      validator = Aidp::Metadata::Validator.new(tools)
      results = validator.validate_all

      expect(results.any? { |r| r.errors.any? { |e| e.include?("duplicate") } }).to be true
    end

    it "detects invalid dependencies" do
      tools = [
        Aidp::Metadata::ToolMetadata.new(
          type: "skill",
          id: "dependent",
          title: "Dependent",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "dep.md",
          file_hash: valid_hash,
          dependencies: ["nonexistent_skill"]
        )
      ]

      validator = Aidp::Metadata::Validator.new(tools)
      results = validator.validate_all

      expect(results.first.errors).not_to be_empty
    end

    xit "validates version format" do
      invalid_tool = Aidp::Metadata::ToolMetadata.new(
        type: "skill",
        id: "invalid_version",
        title: "Invalid Version",
        summary: "Summary",
        version: "not-a-version",
        content: "Content",
        source_path: "test.md",
        file_hash: valid_hash
      )

      validator = Aidp::Metadata::Validator.new([invalid_tool])
      results = validator.validate_all

      expect(results.first.warnings).not_to be_empty
    end

    it "produces validation summary" do
      tools = [
        Aidp::Metadata::ToolMetadata.new(
          type: "skill",
          id: "valid",
          title: "Valid",
          summary: "Summary",
          version: "1.0.0",
          content: "Content",
          source_path: "valid.md",
          file_hash: valid_hash
        )
      ]

      validator = Aidp::Metadata::Validator.new(tools)
      results = validator.validate_all

      expect(results.first).to respond_to(:tool_id)
      expect(results.first).to respond_to(:file_path)
      expect(results.first).to respond_to(:valid)
      expect(results.first).to respond_to(:errors)
      expect(results.first).to respond_to(:warnings)
    end
  end
end
