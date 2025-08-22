# frozen_string_literal: true

require "pg"
require "que"
require "sequel"

module Aidp
  class DatabaseConnection
    class << self
      def establish_connection
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

      def connection
        @connection || establish_connection
      end

      def disconnect
        return unless @connection
        Que.connection = nil
        @sequel_db&.disconnect
        @connection&.close
        @connection = nil
        @sequel_db = nil
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
