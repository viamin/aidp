# frozen_string_literal: true

require "socket"
require_relative "process_manager"
require_relative "../execute/async_work_loop_runner"
require_relative "../concurrency"

module Aidp
  module Daemon
    # Main daemon runner for background mode execution
    # Manages work loops, watch mode, and IPC communication
    class Runner
      def initialize(project_dir, config, options = {}, process_manager: nil)
        @project_dir = project_dir
        @config = config
        @options = options
        @process_manager = process_manager || ProcessManager.new(project_dir)
        @running = false
        @work_loop_runner = nil
        @watch_runner = nil
        @ipc_server = nil
      end

      # Start daemon in background
      def start_daemon(mode: :watch)
        if @process_manager.running?
          return {success: false, message: "Daemon already running (PID: #{@process_manager.pid})"}
        end

        # Fork daemon process
        daemon_pid = fork do
          Process.daemon(true)
          @process_manager.write_pid
          run_daemon(mode)
        end

        Process.detach(daemon_pid)

        # Wait for daemon to start (check if it's running)
        begin
          Aidp::Concurrency::Wait.until(timeout: 5, interval: 0.1) do
            @process_manager.running?
          end

          {
            success: true,
            message: "Daemon started in #{mode} mode",
            pid: daemon_pid,
            log_file: @process_manager.log_file_path
          }
        rescue Aidp::Concurrency::TimeoutError
          {success: false, message: "Failed to start daemon (timeout)"}
        end
      end

      # Attach to running daemon (restore REPL)
      def attach
        unless @process_manager.running?
          return {success: false, message: "No daemon running"}
        end

        unless @process_manager.socket_exists?
          return {success: false, message: "Daemon socket not available"}
        end

        {
          success: true,
          message: "Attached to daemon",
          pid: @process_manager.pid,
          activity: Aidp.logger.info("activity", "summary")
        }
      end

      # Run daemon main loop (called in forked process)
      def run_daemon(mode)
        Aidp.logger.info("daemon_lifecycle", "Daemon started", mode: mode, pid: Process.pid)
        @running = true

        # Set up signal handlers
        setup_signal_handlers

        # Start IPC server
        start_ipc_server

        # Run appropriate mode
        case mode
        when :watch
          run_watch_mode
        when :work_loop
          run_work_loop_mode
        else
          Aidp.logger.error("daemon_error", "Unknown mode: #{mode}")
        end
      rescue => e
        Aidp.logger.error("daemon_error", "Fatal error: #{e.message}", backtrace: e.backtrace.first(5).join("\n"))
      ensure
        cleanup
      end

      private

      def setup_signal_handlers
        Signal.trap("TERM") do
          Aidp.logger.info("daemon_lifecycle", "SIGTERM received, shutting down gracefully")
          @running = false
        end

        Signal.trap("INT") do
          Aidp.logger.info("daemon_lifecycle", "SIGINT received, shutting down gracefully")
          @running = false
        end
      end

      def start_ipc_server
        # Create Unix socket for IPC
        @ipc_server = UNIXServer.new(@process_manager.socket_path)

        Thread.new do
          while @running
            begin
              client = @ipc_server.accept_nonblock
              handle_ipc_client(client)
            rescue IO::WaitReadable
              IO.select([@ipc_server], nil, nil, 1)
            rescue => e
              Aidp.logger.error("ipc_error", "IPC server error: #{e.message}")
            end
          end
        end
      rescue => e
        Aidp.logger.error("ipc_error", "Failed to start IPC server: #{e.message}")
      end

      def handle_ipc_client(client)
        command = client.gets&.strip
        return unless command

        response = case command
        when "status"
          status_response
        when "stop"
          stop_response
        when "attach"
          attach_response
        else
          {error: "Unknown command: #{command}"}
        end

        client.puts(response.to_json)
        client.close
      rescue => e
        Aidp.logger.error("ipc_error", "Error handling client: #{e.message}")
        begin
          client.close
        rescue
          nil
        end
      end

      def status_response
        {
          status: "running",
          pid: Process.pid,
          mode: @watch_runner ? "watch" : "work_loop",
          uptime: Time.now.to_i
        }
      end

      def stop_response
        @running = false
        {status: "stopping"}
      end

      def attach_response
        {
          status: "attached",
          activity: Aidp.logger.info("activity", "summary")
        }
      end

      def run_watch_mode
        Aidp.logger.info("watch_mode", "Starting watch mode")

        # Initialize watch runner
        require_relative "../watch/runner"
        @watch_runner = Aidp::Watch::Runner.new(@project_dir, @config, @options)

        while @running
          begin
            @watch_runner.run_cycle
            Aidp.logger.info("watch_mode", "Watch cycle completed")
            sleep(@options[:interval] || 60)
          rescue => e
            Aidp.logger.error("watch_error", "Watch cycle error: #{e.message}")
            sleep 30
          end
        end

        Aidp.logger.info("watch_mode", "Watch mode stopped")
      end

      def run_work_loop_mode
        Aidp.logger.info("daemon_lifecycle", "Starting work loop mode")

        while @running
          Aidp.logger.debug("heartbeat", "Daemon running")
          sleep 10
        end

        Aidp.logger.info("daemon_lifecycle", "Work loop mode stopped")
      end

      def cleanup
        Aidp.logger.info("daemon_lifecycle", "Daemon cleanup started")

        # Stop work loop if running
        @work_loop_runner&.cancel(save_checkpoint: true)

        # Stop watch runner if running
        @watch_runner = nil

        # Close IPC server
        @ipc_server&.close
        @process_manager.remove_socket

        # Remove PID file
        @process_manager.remove_pid

        Aidp.logger.info("daemon_lifecycle", "Daemon stopped cleanly")
      end
    end
  end
end
