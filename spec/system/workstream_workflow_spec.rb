# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

StatusStub = Struct.new(:exitstatus)

RSpec.describe "Workstream End-to-End Workflows", :system do
  let(:temp_dir) { Dir.mktmpdir("aidp_workstream_e2e") }

  before do
    # Use fast worktree adapter for performance
    stub_worktree_for_fast_tests

    # Initialize a git repository in temp_dir
    Dir.chdir(temp_dir) do
      system("git", "init", out: File::NULL, err: File::NULL)
      system("git", "config", "user.name", "Test User", out: File::NULL, err: File::NULL)
      system("git", "config", "user.email", "test@example.com", out: File::NULL, err: File::NULL)
      system("git", "config", "commit.gpgsign", "false", out: File::NULL, err: File::NULL)

      # Create initial commit
      File.write("README.md", "# Test Project\n")
      system("git", "add", "README.md", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Initial commit", out: File::NULL, err: File::NULL)
    end
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def run_aidp(*args)
    stdout_read, stdout_write = IO.pipe
    stderr_read, stderr_write = IO.pipe
    exit_code = nil

    Dir.chdir(temp_dir) do
      original_stdout = $stdout.dup
      original_stderr = $stderr.dup
      begin
        $stdout.reopen(stdout_write)
        $stderr.reopen(stderr_write)
        stdout_write.close
        stderr_write.close
        exit_code = Aidp::CLI.run(args)
      ensure
        $stdout.reopen(original_stdout)
        $stderr.reopen(original_stderr)
        original_stdout.close
        original_stderr.close
      end
    end

    stdout = stdout_read.read
    stderr = stderr_read.read
    stdout_read.close
    stderr_read.close

    [stdout, stderr, StatusStub.new(exit_code || 0)]
  end

  describe "create workstream → list → remove workflow" do
    it "successfully creates, lists, and removes a workstream" do
      # Create workstream
      stdout, _stderr, status = run_aidp("ws", "new", "test-feature", "Add new feature")
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include("Created workstream: test-feature")
      expect(stdout).to include("Task: Add new feature")

      # Verify worktree directory exists
      worktree_path = File.join(temp_dir, ".worktrees", "test-feature")
      expect(Dir.exist?(worktree_path)).to be true

      # Verify it's a valid git worktree
      expect(File.exist?(File.join(worktree_path, ".git"))).to be true

      # List workstreams
      stdout, _stderr, status = run_aidp("ws", "list")
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include("test-feature")
      expect(stdout).to include("aidp/test-feature")

      # Check status
      stdout, _stderr, status = run_aidp("ws", "status", "test-feature")
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include("Workstream: test-feature")
      expect(stdout).to include("Task: Add new feature")
      expect(stdout).to include("Iterations: 0")
      expect(stdout).to match(/Status:\s+Active/i)

      # Remove workstream
      stdout, _stderr, status = run_aidp("ws", "rm", "test-feature", "--force")
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include("Removed workstream: test-feature")

      # Verify worktree is gone
      expect(Dir.exist?(worktree_path)).to be false
    end
  end

  describe "create multiple workstreams → list → remove workflow" do
    it "manages multiple workstreams independently" do
      # Create first workstream
      _, _stderr, status = run_aidp("ws", "new", "feature-a", "Feature A")
      expect(status.exitstatus).to eq(0)

      # Create second workstream
      _, _stderr, status = run_aidp("ws", "new", "feature-b", "Feature B")
      expect(status.exitstatus).to eq(0)

      # List all workstreams
      stdout, _stderr, status = run_aidp("ws", "list")
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include("feature-a")
      expect(stdout).to include("feature-b")

      # Verify all worktree directories exist
      expect(Dir.exist?(File.join(temp_dir, ".worktrees", "feature-a"))).to be true
      expect(Dir.exist?(File.join(temp_dir, ".worktrees", "feature-b"))).to be true

      # Remove first workstream
      run_aidp("ws", "rm", "feature-a", "--force")

      # List remaining
      stdout, _stderr, status = run_aidp("ws", "list")
      expect(status.exitstatus).to eq(0)
      expect(stdout).not_to include("feature-a")
      expect(stdout).to include("feature-b")

      # Clean up remaining workstream
      run_aidp("ws", "rm", "feature-b", "--force")
    end
  end

  describe "workstream isolation" do
    it "maintains separate file changes in each workstream" do
      # Create two workstreams
      run_aidp("ws", "new", "ws-1", "Workstream 1")
      run_aidp("ws", "new", "ws-2", "Workstream 2")

      # Make different changes in each workstream
      ws1_path = File.join(temp_dir, ".worktrees", "ws-1")
      ws2_path = File.join(temp_dir, ".worktrees", "ws-2")

      File.write(File.join(ws1_path, "file1.txt"), "Content from ws-1")
      File.write(File.join(ws2_path, "file2.txt"), "Content from ws-2")

      # Verify isolation - file1 shouldn't exist in ws-2
      expect(File.exist?(File.join(ws1_path, "file1.txt"))).to be true
      expect(File.exist?(File.join(ws2_path, "file1.txt"))).to be false

      # Verify isolation - file2 shouldn't exist in ws-1
      expect(File.exist?(File.join(ws2_path, "file2.txt"))).to be true
      expect(File.exist?(File.join(ws1_path, "file2.txt"))).to be false

      # Verify neither file exists in main project dir
      expect(File.exist?(File.join(temp_dir, "file1.txt"))).to be false
      expect(File.exist?(File.join(temp_dir, "file2.txt"))).to be false

      # Clean up
      run_aidp("ws", "rm", "ws-1", "--force")
      run_aidp("ws", "rm", "ws-2", "--force")
    end
  end

  describe "error handling" do
    it "prevents creating duplicate workstreams" do
      # Create first workstream
      _, _stderr, status = run_aidp("ws", "new", "duplicate-test")
      expect(status.exitstatus).to eq(0)

      # Try to create duplicate
      stdout, stderr, status = run_aidp("ws", "new", "duplicate-test")
      expect(status.exitstatus).to eq(0) # CLI returns 0 but shows error
      expect(stdout + stderr).to match(/already exists|WorktreeExists/)

      # Clean up
      run_aidp("ws", "rm", "duplicate-test", "--force")
    end

    it "validates slug format" do
      # Invalid slug with uppercase
      stdout, stderr, status = run_aidp("ws", "new", "Invalid-Slug")
      expect(status.exitstatus).to eq(0)
      expect(stdout + stderr).to match(/Invalid slug format|lowercase/)

      # Invalid slug with special characters
      stdout, stderr, status = run_aidp("ws", "new", "invalid_slug!")
      expect(status.exitstatus).to eq(0)
      expect(stdout + stderr).to match(/Invalid slug format|lowercase/)
    end

    it "handles missing workstream gracefully" do
      stdout, stderr, status = run_aidp("ws", "status", "non-existent")
      expect(status.exitstatus).to eq(0)
      expect(stdout + stderr).to match(/not found|Workstream not found/)
    end
  end
end
