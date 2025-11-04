# frozen_string_literal: true

# Global CWD safety: Some specs change directory to '/'
# to avoid deleting the current working directory before cleanup.
# This causes relative storage paths like '.aidp' to resolve to '/.aidp',
# triggering permission errors. After every example, if we're at '/',
# restore to the workspace root.
RSpec.configure do |config|
  config.after(:each) do
    if Dir.getwd == "/"
      workspace_root = "/workspaces/aidp"
      Dir.chdir(workspace_root) if File.directory?(workspace_root)
    end
  rescue Errno::ENOENT
    # If cwd was deleted, fallback and then restore
    begin
      Dir.chdir("/")
      Dir.chdir(workspace_root) if defined?(workspace_root) && File.directory?(workspace_root)
    rescue
      # Swallow; staying at '/' is acceptable if nothing else is available.
    end
  end
end
