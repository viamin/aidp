# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Enhanced question validation with proper error handling
      class QuestionValidator
        class ValidationError < StandardError; end
        class InvalidInputError < ValidationError; end
        class FormatError < ValidationError; end
        class RequiredFieldError < ValidationError; end

        VALIDATION_RULES = {
          email: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
          url: /\Ahttps?:\/\/[\w\-]+(\.[\w\-]+)+([\w\-\.,@?^=%&:\/~\+#]*[\w\-\@?^=%&\/~\+#])?\z/i,
          phone: /\A[\+]?[1-9][\d\s\-\(\)]{7,15}\z/,
          number: /\A-?\d+(\.\d+)?\z/,
          integer: /\A-?\d+\z/,
          float: /\A-?\d+\.\d+\z/,
          boolean: /\A(true|false|yes|no|y|n|1|0)\z/i
        }.freeze

        def initialize(ui_components = {})
          @formatter = ui_components[:formatter] || ValidationFormatter.new
          @error_handler = ui_components[:error_handler] || ErrorHandler.new
        end

        def validate(response, question)
          validation_result = perform_validation(response, question)
          handle_validation_result(validation_result, question)
          validation_result
        end

        def validate_required(response, question)
          return true unless question[:required]

          if response.nil? || response.to_s.strip.empty?
            raise RequiredFieldError, "This field is required"
          end

          true
        end

        def validate_format(response, question)
          return true unless question[:format]

          format_rule = question[:format]
          if format_rule.is_a?(String) && VALIDATION_RULES.key?(format_rule.to_sym)
            regex = VALIDATION_RULES[format_rule.to_sym]
            unless response.to_s.match?(regex)
              raise FormatError, "Invalid #{format_rule} format"
            end
          elsif format_rule.is_a?(Regexp)
            unless response.to_s.match?(format_rule)
              raise FormatError, "Input does not match required format"
            end
          end

          true
        end

        def validate_options(response, question)
          return true unless question[:options]

          unless question[:options].include?(response)
            raise InvalidInputError, "Response must be one of: #{question[:options].join(', ')}"
          end

          true
        end

        def validate_range(response, question)
          return true unless question[:range]

          range = question[:range]
          numeric_response = parse_numeric_response(response)

          if range[:min] && numeric_response < range[:min]
            raise InvalidInputError, "Value must be at least #{range[:min]}"
          end

          if range[:max] && numeric_response > range[:max]
            raise InvalidInputError, "Value must be at most #{range[:max]}"
          end

          true
        end

        def validate_length(response, question)
          return true unless question[:length]

          length = question[:length]
          response_length = response.to_s.length

          if length[:min] && response_length < length[:min]
            raise InvalidInputError, "Response must be at least #{length[:min]} characters"
          end

          if length[:max] && response_length > length[:max]
            raise InvalidInputError, "Response must be at most #{length[:max]} characters"
          end

          true
        end

        def validate_custom(response, question)
          return true unless question[:custom_validator]

          validator = question[:custom_validator]
          if validator.respond_to?(:call)
            result = validator.call(response)
            unless result == true
              error_message = result.is_a?(String) ? result : "Custom validation failed"
              raise ValidationError, error_message
            end
          end

          true
        end

        private

        def perform_validation(response, question)
          validation_result = {
            valid: true,
            errors: [],
            warnings: [],
            response: response
          }

          begin
            validate_required(response, question)
            validate_format(response, question)
            validate_options(response, question)
            validate_range(response, question)
            validate_length(response, question)
            validate_custom(response, question)
          rescue ValidationError => e
            validation_result[:valid] = false
            validation_result[:errors] << e.message
          end

          validation_result
        end

        def handle_validation_result(validation_result, question)
          unless validation_result[:valid]
            display_validation_errors(validation_result[:errors], question)
          end
        end

        def display_validation_errors(errors, question)
          @formatter.display_validation_errors(errors, question)
        end

        def parse_numeric_response(response)
          case response
          when Numeric
            response
          when String
            if response.include?('.')
              response.to_f
            else
              response.to_i
            end
          else
            raise InvalidInputError, "Cannot parse numeric value from: #{response}"
          end
        end
      end

      # Formats validation display
      class ValidationFormatter
        def display_validation_errors(errors, question)
          CLI::UI.puts(CLI::UI.fmt("{{red:❌ Validation Errors:}}"))
          errors.each do |error|
            CLI::UI.puts(CLI::UI.fmt("  {{red:• #{error}}}"))
          end

          if question[:help_text]
            CLI::UI.puts(CLI::UI.fmt("{{blue:💡 Help: #{question[:help_text]}}}"))
          end

          if question[:examples]
            CLI::UI.puts(CLI::UI.fmt("{{dim:Examples: #{question[:examples].join(', ')}}}"))
          end
        end

        def format_validation_success
          CLI::UI.fmt("{{green:✅ Validation passed}}")
        end

        def format_validation_error(error_message)
          CLI::UI.fmt("{{red:❌ #{error_message}}}")
        end

        def format_validation_warning(warning_message)
          CLI::UI.fmt("{{yellow:⚠️ #{warning_message}}}")
        end

        def format_required_indicator(required)
          if required
            CLI::UI.fmt("{{red:* Required}}")
          else
            CLI::UI.fmt("{{dim:Optional}}")
          end
        end

        def format_format_requirement(format_rule)
          case format_rule
          when 'email'
            CLI::UI.fmt("{{dim:Format: email address}}")
          when 'url'
            CLI::UI.fmt("{{dim:Format: URL}}")
          when 'phone'
            CLI::UI.fmt("{{dim:Format: phone number}}")
          when 'number'
            CLI::UI.fmt("{{dim:Format: number}}")
          when 'integer'
            CLI::UI.fmt("{{dim:Format: integer}}")
          when 'float'
            CLI::UI.fmt("{{dim:Format: decimal number}}")
          when 'boolean'
            CLI::UI.fmt("{{dim:Format: true/false}}")
          else
            CLI::UI.fmt("{{dim:Format: #{format_rule}}}")
          end
        end

        def format_range_requirement(range)
          if range[:min] && range[:max]
            CLI::UI.fmt("{{dim:Range: #{range[:min]} - #{range[:max]}}}")
          elsif range[:min]
            CLI::UI.fmt("{{dim:Minimum: #{range[:min]}}}")
          elsif range[:max]
            CLI::UI.fmt("{{dim:Maximum: #{range[:max]}}}")
          end
        end

        def format_length_requirement(length)
          if length[:min] && length[:max]
            CLI::UI.fmt("{{dim:Length: #{length[:min]} - #{length[:max]} characters}}")
          elsif length[:min]
            CLI::UI.fmt("{{dim:Minimum length: #{length[:min]} characters}}")
          elsif length[:max]
            CLI::UI.fmt("{{dim:Maximum length: #{length[:max]} characters}}")
          end
        end
      end
    end
  end
end
