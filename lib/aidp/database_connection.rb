# frozen_string_literal: true

require "pg"
require "que"
require "sequel"

module Aidp
  class DatabaseConnection
    class << self
      def initialize_mutex
        @mutex ||= Mutex.new
      end

      def establish_connection
        initialize_mutex
        @mutex.synchronize do
          # Return existing connection if already established
          return @connection if @connection && !@connection.finished?
          @connection = PG.connect(connection_params)
          @sequel_db = Sequel.connect(
            adapter: "postgres",
            host: ENV["AIDP_DB_HOST"] || "localhost",
            port: (ENV["AIDP_DB_PORT"] || 5432).to_i,
            database: ENV["AIDP_DB_NAME"] || "aidp",
            user: ENV["AIDP_DB_USER"] || ENV["USER"],
            password: ENV["AIDP_DB_PASSWORD"]
          )
          Que.connection = @sequel_db
          Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
          @connection
        end
      end

      def connection
        return @connection if @connection && !@connection.finished?
        establish_connection
      end

      def disconnect
        initialize_mutex
        @mutex.synchronize do
          return unless @connection

          # Safely disconnect in reverse order
          begin
            Que.connection = nil
          rescue => e
            # Log but don't fail on Que disconnection issues
            puts "Warning: Error setting Que.connection to nil: #{e.message}" if ENV["AIDP_DEBUG"]
          end

          @sequel_db&.disconnect
          @connection&.close
          @connection = nil
          @sequel_db = nil
        end
      end

      private

      def connection_params
        {
          host: ENV["AIDP_DB_HOST"] || "localhost",
          port: (ENV["AIDP_DB_PORT"] || 5432).to_i,
          dbname: ENV["AIDP_DB_NAME"] || "aidp",
          user: ENV["AIDP_DB_USER"] || ENV["USER"],
          password: ENV["AIDP_DB_PASSWORD"]
        }
      end
    end
  end
end
