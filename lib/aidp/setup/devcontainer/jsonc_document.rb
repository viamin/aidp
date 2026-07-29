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
          store_comments([], root_comments, position: :leading) if root_comments.any?

          value = parse_value([])
          trailing_comments = consume_comments
          store_comments([], trailing_comments, position: :trailing) if trailing_comments.any?
          skip_whitespace
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
            value = parse_value(value_path)
            inline_comments = consume_inline_comments
            trailing_comments = consume_comments
            store_comments(value_path, leading_comments, position: :leading, value: value)
            store_comments(value_path, inline_comments, position: :inline, value: value)
            store_comments(value_path, trailing_comments, position: :trailing, value: value)
            result[key] = value

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
            value = parse_value(value_path)
            inline_comments = consume_inline_comments
            trailing_comments = consume_comments
            store_comments(value_path, leading_comments, position: :leading, value: value)
            store_comments(value_path, inline_comments, position: :inline, value: value)
            store_comments(value_path, trailing_comments, position: :trailing, value: value)
            result << value

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
            skip_whitespace

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

        def skip_whitespace
          advance while whitespace?(current_char)
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

        def consume_inline_comments
          start_index = @index
          advance while horizontal_whitespace?(current_char)

          return [] unless remaining.start_with?("//", "/*")

          comments = consume_comments
          return comments if comments.any?

          @index = start_index
          []
        end

        def store_comments(path, comments, position:, value: nil)
          return if comments.empty?

          append_comments(comment_key(path, position), comments)
          store_array_value_comments(path, value, comments, position)
        end

        def path_key(path)
          path.map { |part| "#{path_prefix(part)}:#{part}" }.join("\u0000")
        end

        def path_prefix(part)
          part.instance_of?(Integer) ? "i" : "s"
        end

        def append_comments(key, comments)
          @comments[key] ||= []
          @comments[key].concat(comments)
        end

        def comment_key(path, position)
          "#{path_key(path)}\u0000c:#{position}"
        end

        def store_array_value_comments(path, value, comments, position)
          return unless path.last.instance_of?(Integer)

          append_comments(array_value_key(path[0...-1], value, position), comments)
        end

        def array_value_key(path, value, position)
          "#{path_key(path)}\u0000a:#{JSON.generate(value)}\u0000c:#{position}"
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

        def horizontal_whitespace?(char)
          char == " " || char == "\t"
        end

        # Serializes JSON while re-inserting preserved comments before values.
        class Writer
          def initialize(data, comments)
            @data = data
            @comments = comments
            @output = +""
            @array_comment_offsets = Hash.new(0)
          end

          def dump
            write_comments([], 0, position: :leading)
            write_value(@data, [])
            write_root_trailing_comments
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
              write_comments(child_path, indent + 2, position: :leading)
              @output << (" " * (indent + 2))
              @output << JSON.generate(key)
              @output << ": "
              write_value(value, child_path, indent + 2)
              write_inline_comments(child_path)
              @output << "," if index < entries.length - 1
              @output << "\n"
              write_comments(child_path, indent + 2, position: :trailing)
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
              write_comments(child_path, indent + 2, position: :leading)
              @output << (" " * (indent + 2))
              write_value(value, child_path, indent + 2)
              write_inline_comments(child_path)
              @output << "," if index < array.length - 1
              @output << "\n"
              write_comments(child_path, indent + 2, position: :trailing)
            end

            @output << (" " * indent) << "]"
          end

          def write_comments(path, indent, position:)
            comments_for(path, position).each do |comment|
              comment.each_line do |line|
                @output << (" " * indent) << line.rstrip << "\n"
              end
            end
          end

          def write_inline_comments(path)
            comments_for(path, :inline).each do |comment|
              @output << " " << comment
            end
          end

          def write_root_trailing_comments
            trailing_comments = comments_for([], :trailing)
            return if trailing_comments.empty?

            @output << "\n"
            write_comments([], 0, position: :trailing)
          end

          def comments_for(path, position)
            return array_comments_for(path, position) if path.last.instance_of?(Integer)

            @comments[comment_key(path, position)] || []
          end

          def path_key(path)
            path.map { |part| "#{path_prefix(part)}:#{part}" }.join("\u0000")
          end

          def path_prefix(part)
            part.instance_of?(Integer) ? "i" : "s"
          end

          def comment_key(path, position)
            "#{path_key(path)}\u0000c:#{position}"
          end

          def array_comments_for(path, position)
            parent_path = path[0...-1]
            array = @data.dig(*parent_path)
            return [] unless array.is_a?(Array)

            key = array_value_key(parent_path, array[path.last], position)
            comments = @comments[key]
            return [] if comments.nil? || comments.empty?

            offset = @array_comment_offsets[key]
            return [] if offset >= comments.length

            @array_comment_offsets[key] += 1
            [comments[offset]]
          end

          def array_value_key(path, value, position)
            "#{path_key(path)}\u0000a:#{JSON.generate(value)}\u0000c:#{position}"
          end
        end
      end
    end
  end
end
