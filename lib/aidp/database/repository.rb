# frozen_string_literal: true

require "json"

module Aidp
  module Database
    # Base repository class for database access
    # Provides common patterns for CRUD operations
    class Repository
      attr_reader :project_dir, :table_name

      # @param project_dir [String] Project directory path
      # @param table_name [String] Database table name
      def initialize(project_dir: Dir.pwd, table_name:)
        @project_dir = project_dir
        @table_name = table_name
      end

      protected

      # Get database connection
      def db
        Database.connection(project_dir)
      end

      # Execute a query and return all results
      #
      # @param sql [String] SQL query
      # @param params [Array] Query parameters
      # @return [Array<Hash>] Query results
      def query(sql, params = [])
        db.execute(sql, params)
      end

      # Execute a query and return first result
      #
      # @param sql [String] SQL query
      # @param params [Array] Query parameters
      # @return [Hash, nil] First result or nil
      def query_one(sql, params = [])
        db.execute(sql, params).first
      end

      # Execute a query and return single value
      #
      # @param sql [String] SQL query
      # @param params [Array] Query parameters
      # @return [Object, nil] Single value or nil
      def query_value(sql, params = [])
        db.get_first_value(sql, params)
      end

      # Execute a statement (INSERT, UPDATE, DELETE)
      #
      # @param sql [String] SQL statement
      # @param params [Array] Statement parameters
      def execute(sql, params = [])
        db.execute(sql, params)
      end

      # Execute within a transaction
      #
      # @yield Block to execute in transaction
      # @return [Object] Block result
      def transaction(&block)
        db.transaction(&block)
      end

      # Get the last inserted row ID
      #
      # @return [Integer] Last row ID
      def last_insert_row_id
        db.last_insert_row_id
      end

      # Serialize a value to JSON for storage
      #
      # @param value [Object] Value to serialize
      # @return [String, nil] JSON string or nil
      def serialize_json(value)
        return nil if value.nil?

        JSON.generate(value)
      end

      # Deserialize a JSON string from storage
      #
      # @param json_string [String, nil] JSON string
      # @return [Object, nil] Deserialized value or nil
      def deserialize_json(json_string)
        return nil if json_string.nil? || json_string.empty?

        JSON.parse(json_string, symbolize_names: true)
      rescue JSON::ParserError => e
        Aidp.log_debug("repository", "json_parse_error",
          table: table_name,
          error: e.message)
        nil
      end

      # Generate current timestamp in SQLite format
      #
      # @return [String] ISO 8601 timestamp
      def current_timestamp
        Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
      end

      # Build a simple INSERT statement
      #
      # @param columns [Array<Symbol>] Column names
      # @return [String] INSERT SQL
      def insert_sql(columns)
        placeholders = columns.map { "?" }.join(", ")
        cols = columns.join(", ")
        "INSERT INTO #{table_name} (#{cols}) VALUES (#{placeholders})"
      end

      # Build a simple UPDATE statement
      #
      # @param columns [Array<Symbol>] Column names to update
      # @param where_column [Symbol] WHERE clause column
      # @return [String] UPDATE SQL
      def update_sql(columns, where_column: :id)
        set_clause = columns.map { |c| "#{c} = ?" }.join(", ")
        "UPDATE #{table_name} SET #{set_clause} WHERE #{where_column} = ?"
      end

      # Find a record by ID
      #
      # @param id [Object] Record ID
      # @return [Hash, nil] Record or nil
      def find_by_id(id)
        query_one("SELECT * FROM #{table_name} WHERE id = ?", [id])
      end

      # Find all records matching project_dir
      #
      # @return [Array<Hash>] Records
      def find_by_project
        query("SELECT * FROM #{table_name} WHERE project_dir = ?", [project_dir])
      end

      # Delete a record by ID
      #
      # @param id [Object] Record ID
      def delete_by_id(id)
        execute("DELETE FROM #{table_name} WHERE id = ?", [id])
      end

      # Delete all records matching project_dir
      def delete_by_project
        execute("DELETE FROM #{table_name} WHERE project_dir = ?", [project_dir])
      end

      # Count records matching project_dir
      #
      # @return [Integer] Record count
      def count_by_project
        query_value(
          "SELECT COUNT(*) FROM #{table_name} WHERE project_dir = ?",
          [project_dir]
        ) || 0
      end
    end
  end
end
