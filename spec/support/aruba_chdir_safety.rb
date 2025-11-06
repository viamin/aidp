# frozen_string_literal: true

# Global safeguard for Aruba specs: ensure we are not left inside a
# deleted sandbox directory when Aruba performs its cleanup. Without
# this, RSpec/Bundler may attempt Dir.getwd on a removed path causing
# Errno::ENOENT. We defensively chdir to the workspace root after each
# Aruba example.
RSpec.configure do |config|
  config.after(:each, type: :aruba) do
    desired_root = "/workspaces/aidp"
    begin
      cwd = Dir.getwd
      if cwd != desired_root && cwd != "/"
        Dir.chdir(desired_root)
      end
    rescue Errno::ENOENT
      # Current directory removed: move to / then attempt desired_root if it exists.
      begin
        Dir.chdir("/")
        Dir.chdir(desired_root) if File.directory?(desired_root)
      rescue
        # Swallow; remaining at / is acceptable.
      end
    end
  end
end
