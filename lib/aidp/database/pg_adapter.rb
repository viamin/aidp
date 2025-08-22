# frozen_string_literal: true

module Aidp
  module Database
    class PgAdapter
      def initialize(connection)
        @connection = connection
      end

      def execute(sql, params = [])
        result = @connection.exec_params(sql, params)
        result.to_a.map { |row| row.transform_keys(&:to_sym) }
      end

      def in_transaction?
        @connection.transaction_status != PG::PQTRANS_IDLE
      end

      def checkout
        yield self
      end

      def after_commit
        yield
      end

      def server_version
        @connection.server_version
      end

      def transaction_status
        @connection.transaction_status
      end

      def transaction
        @connection.transaction do
          yield
        end
      end

      def quote_table_name(name)
        "\"#{name}\""
      end

      def quote_identifier(name)
        "\"#{name}\""
      end

      def quote_string(string)
        "'#{string.gsub("'", "''")}'"
      end

      def quote_date(date)
        date.strftime("%Y-%m-%d")
      end

      def quote_time(time)
        time.strftime("%Y-%m-%d %H:%M:%S.%6N %z")
      end

      # Additional methods required by Que
      def async_connection
        self
      end

      def wait_for_notify(timeout = nil)
        @connection.wait_for_notify(timeout)
      end

      def listen(channel)
        @connection.exec("LISTEN #{quote_identifier(channel)}")
      end

      def unlisten(channel)
        @connection.exec("UNLISTEN #{quote_identifier(channel)}")
      end

      def unlisten_all
        @connection.exec("UNLISTEN *")
      end

      def notifications
        @connection.notifications
      end

      def reset
        @connection.reset
      end

      def type_map_for_queries
        @connection.type_map_for_queries
      end

      def type_map_for_results
        @connection.type_map_for_results
      end

      # Additional methods for Que compatibility
      def adapter_name
        "pg"
      end

      def active?
        @connection.status == PG::CONNECTION_OK
      end

      def disconnect!
        @connection.close
      end

      def reconnect!
        @connection.reset
      end

      def raw_connection
        @connection
      end

      def schema_search_path
        execute("SHOW search_path")[0][:search_path]
      end

      def schema_search_path=(path)
        execute("SET search_path TO #{path}")
      end

      def table_exists?(name)
        execute(<<~SQL, [name]).any?
          SELECT 1
          FROM pg_tables
          WHERE tablename = $1
        SQL
      end

      def advisory_lock(id)
        execute("SELECT pg_advisory_lock($1)", [id])
      end

      def advisory_unlock(id)
        execute("SELECT pg_advisory_unlock($1)", [id])
      end

      def advisory_unlock_all
        execute("SELECT pg_advisory_unlock_all()")
      end
    end
  end
end
