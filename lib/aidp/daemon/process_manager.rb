# frozen_string_literal: true

require "fileutils"

module Aidp
  module Daemon
    # Manages daemon process lifecycle: start, stop, status, attach
    # Handles PID file management and process communication
    class ProcessManager
      DAEMON_DIR = ".aidp/daemon"
      PID_FILE = "#{DAEMON_DIR}/aidp.pid"
      SOCKET_FILE = "#{DAEMON_DIR}/aidp.sock"
      LOG_FILE = "#{DAEMON_DIR}/daemon.log"

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @pid_file_path = File.join(@project_dir, PID_FILE)
        @socket_path = File.join(@project_dir, SOCKET_FILE)
        @log_path = File.join(@project_dir, LOG_FILE)
        ensure_daemon_dir
      end

      # Check if daemon is running
      def running?
        return false unless File.exist?(@pid_file_path)

        pid = read_pid
        return false unless pid

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        # Process doesn't exist
        cleanup_stale_files
        false
      rescue Errno::EPERM
        # Process exists but we don't have permission
        true
      end

      # Get daemon PID
      def pid
        return nil unless running?
        read_pid
      end

      # Get daemon status summary
      def status
        if running?
          {
            running: true,
            pid: pid,
            socket: File.exist?(@socket_path),
            log_file: @log_path
          }
        else
          {
            running: false,
            pid: nil,
            socket: false,
            log_file: @log_path
          }
        end
      end

      # Write PID file for daemon
      def write_pid(daemon_pid = Process.pid)
        File.write(@pid_file_path, daemon_pid.to_s)
      end

      # Remove PID file
      def remove_pid
        File.delete(@pid_file_path) if File.exist?(@pid_file_path)
      end

      # Stop daemon gracefully
      def stop(timeout: 30)
        return {success: false, message: "Daemon not running"} unless running?

        daemon_pid = pid
        Process.kill("TERM", daemon_pid)

        # Wait for process to exit
        timeout.times do
          sleep 1
          unless process_exists?(daemon_pid)
            cleanup_stale_files
            return {success: true, message: "Daemon stopped gracefully"}
          end
        end

        # Force kill if still running
        Process.kill("KILL", daemon_pid)
        cleanup_stale_files
        {success: true, message: "Daemon force-killed after timeout"}
      rescue Errno::ESRCH
        cleanup_stale_files
        {success: true, message: "Daemon already stopped"}
      rescue => e
        {success: false, message: "Error stopping daemon: #{e.message}"}
      end

      # Get socket path for IPC
      attr_reader :socket_path

      # Check if socket exists
      def socket_exists?
        File.exist?(@socket_path)
      end

      # Remove socket file
      def remove_socket
        File.delete(@socket_path) if File.exist?(@socket_path)
      end

      # Get log file path
      def log_file_path
        @log_path
      end

      private

      def ensure_daemon_dir
        daemon_dir = File.join(@project_dir, DAEMON_DIR)
        FileUtils.mkdir_p(daemon_dir) unless Dir.exist?(daemon_dir)
      end

      def read_pid
        return nil unless File.exist?(@pid_file_path)
        File.read(@pid_file_path).strip.to_i
      end

      def process_exists?(daemon_pid)
        Process.kill(0, daemon_pid)
        true
      rescue Errno::ESRCH
        false
      end

      def cleanup_stale_files
        remove_pid
        remove_socket
      end
    end
  end
end
