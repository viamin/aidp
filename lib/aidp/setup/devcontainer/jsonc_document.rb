# frozen_string_literal: true

require "json"

module Aidp
  module Setup
    module Devcontainer
      # Parses and serializes JSON with comments while preserving comment blocks.
      class JsoncDocument
        attr_reader :data, :comments

        def self.parse(text)
          new(text).parse
        end

        def self.dump(data, comments: {})
          new(nil).send(:dump, data, comments)
        end

        def initialize(text)
          @text = text
          @index = 0
          @comments = {}
        end

        def parse
          root_comments = consume_comments
          store_comments([], root_comments) if root_comments.any?

          value = parse_value([])
          skip_trivia
          raise ParseError, "Unexpected trailing content" unless eof?

          @data = value
          self
        rescue ParseError => e
          raise e
        rescue => e
          raise ParseError, e.message
        end

        private

        class ParseError < StandardError; end

        def dump(data, comments)
          writer = Writer.new(data, comments)
          writer.dump
        end

        def parse_value(path)
          skip_trivia

          case current_char
          when "{"
            parse_object(path)
          when "["
            parse_array(path)
          when '"'
            parse_string
          when "t", "f", "n"
            parse_literal
          else
            parse_number
          end
        end

        def parse_object(path)
          expect("{")
          advance while whitespace?(current_char)

          result = {}
          return result if consume_if("}")

          loop do
            leading_comments = consume_comments
            key = parse_string
            skip_trivia
            expect(":")

            value_path = path + [key]
            store_comments(value_path, leading_comments) if leading_comments.any?
            result[key] = parse_value(value_path)
            trailing_comments = consume_comments
            store_comments(value_path, trailing_comments) if trailing_comments.any?

            skip_trivia
            break if consume_if("}")
            expect(",")
          end

          result
        end

        def parse_array(path)
          expect("[")
          advance while whitespace?(current_char)

          result = []
          return result if consume_if("]")

          index = 0
          loop do
            leading_comments = consume_comments
            value_path = path + [index]
            store_comments(value_path, leading_comments) if leading_comments.any?
            result << parse_value(value_path)
            trailing_comments = consume_comments
            store_comments(value_path, trailing_comments) if trailing_comments.any?

            index += 1
            skip_trivia
            break if consume_if("]")
            expect(",")
          end

          result
        end

        def parse_string
          expect('"')
          chars = +""

          until eof?
            char = current_char

            case char
            when '"'
              advance
              return chars
            when "\\"
              advance
              chars << parse_escape_sequence
            else
              chars << char
              advance
            end
          end

          raise ParseError, "Unterminated string"
        end

        def parse_escape_sequence
          raise ParseError, "Unterminated escape sequence" if eof?

          char = current_char
          advance

          case char
          when '"', "\\", "/"
            char
          when "b" then "\b"
          when "f" then "\f"
          when "n" then "\n"
          when "r" then "\r"
          when "t" then "\t"
          when "u"
            hex = read_chars(4)
            [hex.to_i(16)].pack("U")
          else
            raise ParseError, "Invalid escape sequence"
          end
        end

        def parse_literal
          return true if consume_sequence("true")
          return false if consume_sequence("false")
          return nil if consume_sequence("null")

          raise ParseError, "Invalid literal"
        end

        def parse_number
          match = remaining.match(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/)
          raise ParseError, "Invalid number" unless match

          number = match[0]
          advance_by(number.length)
          (number.include?(".") || number.match?(/[eE]/)) ? number.to_f : number.to_i
        end

        def skip_trivia
          loop do
            advance while whitespace?(current_char)

            if consume_sequence("//")
              advance while !eof? && current_char != "\n"
            elsif consume_sequence("/*")
              until eof? || consume_sequence("*/")
                advance
              end
              raise ParseError, "Unterminated block comment" if eof?
            else
              break
            end
          end
        end

        def consume_comments
          comments = []

          loop do
            advance while whitespace?(current_char)

            if consume_sequence("//")
              comment = +"//"
              until eof? || current_char == "\n"
                comment << current_char
                advance
              end
              comments << comment.rstrip
            elsif consume_sequence("/*")
              comment = +"/*"
              until eof?
                if consume_sequence("*/")
                  comment << "*/"
                  comments << comment.rstrip
                  break
                end

                comment << current_char
                advance
              end
              raise ParseError, "Unterminated block comment" if eof? && !comments.last&.end_with?("*/")
            else
              break
            end
          end

          comments
        end

        def store_comments(path, comments)
          return if comments.empty?

          key = path_key(path)
          @comments[key] ||= []
          @comments[key].concat(comments)
        end

        def path_key(path)
          path.map { |part| "#{path_prefix(part)}:#{part}" }.join("\u0000")
        end

        def path_prefix(part)
          part.instance_of?(Integer) ? "i" : "s"
        end

        def consume_if(char)
          return false unless current_char == char

          advance
          true
        end

        def expect(char)
          return if consume_if(char)

          raise ParseError, "Expected #{char}"
        end

        def consume_sequence(sequence)
          return false unless remaining.start_with?(sequence)

          advance_by(sequence.length)
          true
        end

        def read_chars(count)
          value = remaining[0, count]
          raise ParseError, "Unexpected end of input" unless value && value.length == count

          advance_by(count)
          value
        end

        def current_char
          (@text && !eof?) ? @text[@index] : nil
        end

        def remaining
          return "" if @text.nil? || eof?

          @text[@index..]
        end

        def advance
          @index += 1
        end

        def advance_by(count)
          @index += count
        end

        def eof?
          @text.nil? || @index >= @text.length
        end

        def whitespace?(char)
          char&.match?(/\s/)
        end

        # Serializes JSON while re-inserting preserved comments before values.
        class Writer
          def initialize(data, comments)
            @data = data
            @comments = comments
            @output = +""
          end

          def dump
            write_comments([], 0)
            write_value(@data, [])
            @output
          end

          private

          def write_value(value, path, indent = 0)
            case value
            when Hash
              write_object(value, path, indent)
            when Array
              write_array(value, path, indent)
            else
              @output << JSON.generate(value)
            end
          end

          def write_object(hash, path, indent)
            if hash.empty?
              @output << "{}"
              return
            end

            @output << "{\n"
            entries = hash.to_a

            entries.each_with_index do |(key, value), index|
              child_path = path + [key]
              write_comments(child_path, indent + 2)
              @output << (" " * (indent + 2))
              @output << JSON.generate(key)
              @output << ": "
              write_value(value, child_path, indent + 2)
              @output << ",\n" if index < entries.length - 1
              @output << "\n" if index == entries.length - 1
            end

            @output << (" " * indent) << "}"
          end

          def write_array(array, path, indent)
            if array.empty?
              @output << "[]"
              return
            end

            @output << "[\n"
            array.each_with_index do |value, index|
              child_path = path + [index]
              write_comments(child_path, indent + 2)
              @output << (" " * (indent + 2))
              write_value(value, child_path, indent + 2)
              @output << ",\n" if index < array.length - 1
              @output << "\n" if index == array.length - 1
            end

            @output << (" " * indent) << "]"
          end

          def write_comments(path, indent)
            comments_for(path).each do |comment|
              comment.each_line do |line|
                @output << (" " * indent) << line.rstrip << "\n"
              end
            end
          end

          def comments_for(path)
            @comments[path_key(path)] || []
          end

          def path_key(path)
            path.map { |part| "#{path_prefix(part)}:#{part}" }.join("\u0000")
          end

          def path_prefix(part)
            part.instance_of?(Integer) ? "i" : "s"
          end
        end
      end
    end
  end
end
