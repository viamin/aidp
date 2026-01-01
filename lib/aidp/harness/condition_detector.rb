# frozen_string_literal: true

require "time"

module Aidp
  module Harness
    # Detects run conditions (rate limits, user feedback, completion, errors)
    class ConditionDetector
      # Expose patterns for testability
      attr_reader :rate_limit_patterns, :user_feedback_patterns, :question_patterns, :reset_time_patterns

      def initialize
        # Enhanced rate limit patterns for different providers
        @rate_limit_patterns = {
          # Common patterns
          common: [
            /rate limit/i,
            /too many requests/i,
            /quota exceeded/i,
            /429/i,
            /rate.{0,20}exceeded/i,
            /throttled/i,
            /limit.{0,20}exceeded/i,
            /session limit/i
          ],
          # Anthropic/Claude specific
          anthropic: [
            /rate limit exceeded/i,
            /too many requests/i,
            /quota.{0,20}exceeded/i,
            /anthropic.{0,20}rate.{0,20}limit/i,
            /session limit reached/i
          ],
          # OpenAI specific
          openai: [
            /rate limit exceeded/i,
            /requests per minute/i,
            /tokens per minute/i,
            /openai.{0,20}rate.{0,20}limit/i
          ],
          # Google/Gemini specific
          google: [
            /quota exceeded/i,
            /rate limit exceeded/i,
            /google.{0,20}api.{0,20}limit/i,
            /gemini.{0,20}rate.{0,20}limit/i
          ],
          # Cursor specific
          cursor: [
            /cursor.{0,20}rate.{0,20}limit/i,
            /package.{0,20}limit/i,
            /usage.{0,20}limit/i
          ]
        }

        # Enhanced user feedback patterns
        @user_feedback_patterns = {
          # Direct requests for input
          direct_requests: [
            /please provide/i,
            /can you provide/i,
            /could you provide/i,
            /i need.{0,20}input/i,
            /i require.{0,20}input/i,
            /please give me/i,
            /can you give me/i
          ],
          # Clarification requests
          clarification: [
            /can you clarify/i,
            /could you clarify/i,
            /please clarify/i,
            /i need clarification/i,
            /can you explain/i,
            /could you explain/i
          ],
          # Choice/decision requests
          choices: [
            /what would you like/i,
            /what do you prefer/i,
            /which.{0,20}would you prefer/i,
            /which.{0,20}do you want/i,
            /do you want/i,
            /should i/i,
            /would you like/i,
            /which option/i,
            /choose between/i,
            /select.{0,20}from/i
          ],
          # Confirmation requests
          confirmation: [
            /is this correct/i,
            /does this look right/i,
            /should i proceed/i,
            /can i continue/i,
            /is this what you want/i,
            /confirm.{0,20}this/i,
            /approve.{0,20}this/i
          ],
          # File/input requests
          file_requests: [
            /please upload/i,
            /can you upload/i,
            /i need.{0,20}file/i,
            /please provide.{0,20}file/i,
            /attach.{0,20}file/i,
            /send.{0,20}file/i
          ],
          # Specific information requests
          information: [
            /what is.{0,20}name/i,
            /what is.{0,20}email/i,
            /what is.{0,20}url/i,
            /what is.{0,20}path/i,
            /enter.{0,20}name/i,
            /enter.{0,20}email/i,
            /enter.{0,20}url/i,
            /enter.{0,20}path/i
          ]
        }

        # Enhanced question patterns
        @question_patterns = [
          # Numbered questions
          /^\d+\.\s+(.+)\?/,
          /^(\d+)\)\s+(.+)\?/,
          /^(\d+\.\s+.+)\?$/m,
          # Bullet point questions
          /^[-*]\s+(.+)\?/,
          # Lettered questions
          /^[a-z]\)\s+(.+)\?/i,
          /^[A-Z]\)\s+(.+)\?/,
          # Questions with colons
          /^(\d+):\s+(.+)\?/,
          # Questions in quotes
          /"([^"]+\?)"/,
          /'([^']+\?)'/
        ]

        # Context patterns that indicate user interaction is needed
        @context_patterns = [
          /waiting for.{0,20}input/i,
          /awaiting.{0,20}response/i,
          /need.{0,20}feedback/i,
          /require.{0,20}confirmation/i,
          /pending.{0,20}approval/i,
          /user.{0,20}interaction.{0,20}required/i,
          /manual.{0,20}intervention/i
        ]

        # Rate limit reset time patterns
        @reset_time_patterns = [
          /reset(?:s)?\s+in\s+(\d+)\s+seconds/i,
          /retry\s+after\s+(\d+)\s+seconds/i,
          /wait[^\d]*(\d+)[^\d]*seconds/i,
          /(\d+)\s+seconds\s+until\s+reset/i,
          /reset.{0,20}at.{0,20}(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/i,
          /retry.{0,20}after.{0,20}(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/i
        ]
      end

      # Check if result indicates rate limiting
      def is_rate_limited?(result, provider = nil)
        return false unless result.is_a?(Hash)

        # Check HTTP status codes
        if result[:status_code] == 429 || result[:http_status] == 429
          return true
        end

        # Get all text content to check
        text_content = [
          result[:error],
          result[:message],
          result[:output],
          result[:response],
          result[:body]
        ].compact.join(" ").strip

        return nil if text_content.empty?

        {
          provider: provider,
          detected_at: Time.now,
          reset_time: extract_reset_time(text_content),
          retry_after: extract_retry_after(text_content),
          limit_type: detect_limit_type(text_content, provider),
          message: text_content
        }

        return false if text_content.empty?

        # Check provider-specific patterns first
        if provider && @rate_limit_patterns[provider.to_sym]
          return true if @rate_limit_patterns[provider.to_sym].any? { |pattern| text_content.match?(pattern) }
        end

        # Check common patterns
        @rate_limit_patterns[:common].any? { |pattern| text_content.match?(pattern) }
      end

      # Extract rate limit information from result
      def extract_rate_limit_info(result, provider = nil)
        return nil unless is_rate_limited?(result, provider)

        text_content = [
          result[:error],
          result[:message],
          result[:output],
          result[:response],
          result[:body]
        ].compact.join(" ")

        {
          provider: provider,
          detected_at: Time.now,
          reset_time: extract_reset_time(text_content),
          retry_after: extract_retry_after(text_content),
          limit_type: detect_limit_type(text_content, provider),
          message: text_content
        }
      end

      # Extract reset time from rate limit message
      def extract_reset_time(text_content)
        # Handle expressions like "resets 4am" or "reset at 4:30pm"
        time_of_day_match = text_content.match(/reset(?:s)?(?:\s+at)?\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)/i)
        if time_of_day_match
          hour = time_of_day_match[1].to_i
          minute = time_of_day_match[2] ? time_of_day_match[2].to_i : 0
          meridiem = time_of_day_match[3].downcase

          hour %= 12
          hour += 12 if meridiem == "pm"

          now = Time.now
          reset_time = Time.new(now.year, now.month, now.day, hour, minute, 0, now.utc_offset)
          reset_time += 86_400 if reset_time <= now
          return reset_time
        end

        @reset_time_patterns.each do |pattern|
          match = text_content.match(pattern)
          next unless match

          if match[1].match?(/^\d+$/)
            # Seconds from now
            return Time.now + match[1].to_i
          else
            # Specific timestamp
            begin
              parsed_time = Time.parse(match[1])
              return parsed_time if parsed_time
            rescue ArgumentError
              nil
            end
          end
        end

        # Default to 60 seconds if no specific time found
        Time.now + 60
      end

      # Extract retry-after value
      def extract_retry_after(text_content)
        # Look for retry-after header or similar
        retry_patterns = [
          /retry\s+after\s+(\d{1,6})/i,
          /wait\s+(\d{1,6})\s+seconds/i,
          /(\d{1,6})\s+seconds\s+until/i
        ]

        retry_patterns.each do |pattern|
          match = text_content.match(pattern)
          return match[1].to_i if match
        end

        # Default retry time
        60
      end

      # Detect the type of rate limit
      def detect_limit_type(text_content, provider)
        return "session_limit" if text_content.match?(/session limit/i)

        case provider&.to_s&.downcase
        when "anthropic", "claude"
          if text_content.match?(/requests per minute/i)
            "requests_per_minute"
          elsif text_content.match?(/tokens per minute/i)
            "tokens_per_minute"
          else
            "general_rate_limit"
          end
        when "openai"
          if text_content.match?(/requests per minute/i)
            "requests_per_minute"
          elsif text_content.match?(/tokens per minute/i)
            "tokens_per_minute"
          else
            "general_rate_limit"
          end
        when "google", "gemini"
          if text_content.match?(/quota exceeded/i)
            "quota_exceeded"
          else
            "general_rate_limit"
          end
        when "cursor"
          if text_content.match?(/package\s+limit/i)
            "package_limit"
          elsif text_content.match?(/usage\s+limit/i)
            "usage_limit"
          else
            "general_rate_limit"
          end
        else
          "general_rate_limit"
        end
      end

      # Check if result needs user feedback
      def needs_user_feedback?(result)
        return false unless result.is_a?(Hash)

        # Get all text content to check
        text_content = [
          result[:output],
          result[:message],
          result[:response],
          result[:body]
        ].compact.join(" ")

        return false if text_content.empty?

        # Check for context patterns first
        return true if @context_patterns.any? { |pattern| text_content.match?(pattern) }

        # Check for any user feedback patterns
        @user_feedback_patterns.values.flatten.any? { |pattern| text_content.match?(pattern) }
      end

      # Get detailed user feedback information
      def extract_user_feedback_info(result)
        return nil unless needs_user_feedback?(result)

        # Get all text content to analyze
        text_content = [
          result[:output],
          result[:message],
          result[:response],
          result[:body]
        ].compact.join(" ")

        {
          detected_at: Time.now,
          feedback_type: detect_feedback_type(text_content),
          questions: extract_questions(result),
          context: extract_context(text_content),
          urgency: detect_urgency(text_content),
          input_type: detect_input_type(text_content)
        }
      end

      # Detect the type of feedback needed
      def detect_feedback_type(text_content)
        @user_feedback_patterns.each do |type, patterns|
          if patterns.any? { |pattern| text_content.match?(pattern) }
            return type.to_s
          end
        end

        "general"
      end

      # Extract context information
      def extract_context(text_content)
        context_matches = []
        @context_patterns.each do |pattern|
          matches = text_content.scan(pattern)
          context_matches.concat(matches)
        end
        context_matches.uniq
      end

      # Detect urgency level
      def detect_urgency(text_content)
        urgent_patterns = [
          /urgent/i,
          /asap/i,
          /immediately/i,
          /right now/i,
          /critical/i,
          /important/i
        ]

        low_urgency_patterns = [
          /when you have time/i,
          /when convenient/i,
          /at your convenience/i,
          /when possible/i,
          /no rush/i,
          /take your time/i
        ]

        if urgent_patterns.any? { |pattern| text_content.match?(pattern) }
          "high"
        elsif low_urgency_patterns.any? { |pattern| text_content.match?(pattern) }
          "low"
        elsif text_content.match?(/please/i) || text_content.match?(/can you/i)
          "medium"
        else
          "low"
        end
      end

      # Detect the type of input expected
      def detect_input_type(text_content)
        if text_content.match?(/file/i) || text_content.match?(/upload/i) || text_content.match?(/attach/i)
          "file"
        elsif text_content.match?(/email/i)
          "email"
        elsif text_content.match?(/url/i) || text_content.match?(/link/i)
          "url"
        elsif text_content.match?(/path/i) || text_content.match?(/directory/i)
          "path"
        elsif text_content.match?(/number/i) || text_content.match?(/\d+/) ||
            text_content.match?(/how many/i) || text_content.match?(/how much/i) ||
            text_content.match?(/count/i) || text_content.match?(/quantity/i) ||
            text_content.match?(/amount/i)
          "number"
        elsif text_content.match?(/yes/i) || text_content.match?(/no/i) || text_content.match?(/confirm/i) ||
            text_content.match?(/should i/i) || text_content.match?(/can i/i) || text_content.match?(/may i/i) ||
            text_content.match?(/proceed/i) || text_content.match?(/continue/i) || text_content.match?(/approve/i)
          "boolean"
        else
          "text"
        end
      end

      # Extract questions from result output
      def extract_questions(result)
        return [] unless result.is_a?(Hash)

        # Get all text content to analyze
        text_content = [
          result[:output],
          result[:message],
          result[:response],
          result[:body]
        ].compact.join(" ")

        return [] if text_content.empty?

        questions = []

        # Extract structured questions using patterns
        @question_patterns.each do |pattern|
          matches = text_content.scan(pattern)
          matches.each do |match|
            if match.is_a?(Array)
              if match.length == 2
                # Pattern with two capture groups (number and question)
                number = match[0]
                question = match[1]
                next if number.nil? || question.nil?

                questions << {
                  number: number,
                  question: question.strip,
                  type: detect_question_type(question),
                  input_type: detect_input_type(question)
                }
              elsif match.length == 1
                # Pattern with one capture group (just question)
                question = match[0]
                next if question.nil?

                questions << {
                  question: question.strip,
                  type: detect_question_type(question),
                  input_type: detect_input_type(question)
                }
              end
            else
              # Single capture group
              next if match.nil?

              questions << {
                question: match.strip,
                type: detect_question_type(match),
                input_type: detect_input_type(match)
              }
            end
          end
        end

        # If no structured questions found, look for general questions
        if questions.empty?
          general_questions = text_content.scan(/([^.!?]{1,500}\?)/)
          general_questions.each_with_index do |match, index|
            question_text = match[0].strip
            next if question_text.length < 10 # Skip very short questions

            questions << {
              number: index + 1,
              question: question_text,
              type: detect_question_type(question_text),
              input_type: detect_input_type(question_text)
            }
          end
        end

        # Remove duplicates and clean up
        questions.uniq { |q| q[:question] }
      end

      # Detect the type of question
      def detect_question_type(question_text)
        question_lower = question_text.downcase

        if question_lower.match?(/what.{0,20}name/i) || question_lower.match?(/what.{0,20}email/i)
          "information"
        elsif question_lower.match?(/which.{0,20}prefer/i) || question_lower.match?(/which.{0,20}want/i)
          "choice"
        elsif question_lower.match?(/should.{0,20}i/i) || question_lower.match?(/can.{0,20}i/i)
          "permission"
        elsif question_lower.match?(/is.{0,20}correct/i) || question_lower.match?(/does.{0,20}look/i)
          "confirmation"
        elsif question_lower.match?(/can.{0,20}you/i) || question_lower.match?(/could.{0,20}you/i)
          "request"
        elsif question_lower.match?(/how.{0,20}many/i) || question_lower.match?(/how.{0,20}much/i)
          "quantity"
        elsif question_lower.match?(/when/i)
          "time"
        elsif question_lower.match?(/where/i)
          "location"
        elsif question_lower.match?(/why/i)
          "explanation"
        else
          "general"
        end
      end

      # Check if work is complete
      def is_work_complete?(result, progress)
        return false unless result.is_a?(Hash)

        # Check if all steps are completed
        if progress&.completed_steps && progress.total_steps &&
            progress.completed_steps.size == progress.total_steps
          return true
        end

        # Get all text content to analyze
        text_content = [
          result[:output],
          result[:message],
          result[:response],
          result[:body]
        ].compact.join(" ")

        return false if text_content.empty?

        # Check for completion indicators
        completion_info = extract_completion_info(result, progress)
        completion_info[:is_complete]
      end

      # Extract comprehensive completion information
      def extract_completion_info(result, progress)
        # Get all text content to analyze
        text_content = [
          result[:output],
          result[:message],
          result[:response],
          result[:body]
        ].compact.join(" ")

        completion_info = {
          is_complete: false,
          completion_type: nil,
          confidence: 0.0,
          indicators: [],
          progress_status: nil,
          next_actions: []
        }

        # Check progress-based completion
        if progress&.completed_steps && progress.total_steps &&
            progress.completed_steps.size == progress.total_steps
          completion_info[:is_complete] = true
          completion_info[:completion_type] = "all_steps_completed"
          completion_info[:confidence] = 1.0
          completion_info[:progress_status] = "all_steps_completed"
          return completion_info
        end

        # Check for explicit completion indicators
        explicit_completion = detect_explicit_completion(text_content)
        if explicit_completion[:found]
          completion_info[:is_complete] = true
          completion_info[:completion_type] = explicit_completion[:type]
          completion_info[:confidence] = explicit_completion[:confidence]
          completion_info[:indicators] = explicit_completion[:indicators]
          return completion_info
        end

        # Check for implicit completion indicators
        implicit_completion = detect_implicit_completion(text_content, progress)
        if implicit_completion[:found]
          completion_info[:is_complete] = true
          completion_info[:completion_type] = implicit_completion[:type]
          completion_info[:confidence] = implicit_completion[:confidence]
          completion_info[:indicators] = implicit_completion[:indicators]
          return completion_info
        end

        # If no completion indicators found, check for partial completion
        partial_completion = detect_partial_completion(text_content, progress)
        completion_info[:progress_status] = partial_completion[:status]
        completion_info[:next_actions] = partial_completion[:next_actions]

        # Only consider work complete if we have explicit or implicit completion indicators
        completion_info[:is_complete] = false

        completion_info
      end

      # Detect explicit completion indicators
      def detect_explicit_completion(text_content)
        completion_patterns = {
          # High confidence completion indicators
          high_confidence: [
            /all steps completed/i,
            /workflow complete/i,
            /analysis complete/i,
            /execution finished/i,
            /task completed/i,
            /all done/i,
            /finished successfully/i,
            /completed successfully/i,
            /workflow finished/i,
            /analysis finished/i,
            /execution completed/i
          ],
          # Medium confidence completion indicators
          medium_confidence: [
            /complete/i,
            /finished/i,
            /done/i,
            /success/i,
            /ready/i,
            /final/i
          ],
          # Low confidence completion indicators
          low_confidence: [
            /end/i,
            /stop/i,
            /close/i,
            /finalize/i
          ]
        }

        found_indicators = []
        max_confidence = 0.0
        completion_type = nil

        completion_patterns.each do |confidence_level, patterns|
          patterns.each do |pattern|
            if text_content.match?(pattern)
              found_indicators << pattern.source
              case confidence_level
              when :high_confidence
                if max_confidence < 0.9
                  max_confidence = 0.9
                  completion_type = "explicit_high_confidence"
                end
              when :medium_confidence
                if max_confidence < 0.7
                  max_confidence = 0.7
                  completion_type = "explicit_medium_confidence"
                end
              when :low_confidence
                if max_confidence < 0.5
                  max_confidence = 0.5
                  completion_type = "explicit_low_confidence"
                end
              end
            end
          end
        end

        {
          found: max_confidence > 0.0,
          type: completion_type,
          confidence: max_confidence,
          indicators: found_indicators
        }
      end

      # Detect implicit completion indicators
      def detect_implicit_completion(text_content, progress)
        # Check for summary or conclusion patterns
        summary_patterns = [
          /summary/i,
          /conclusion/i,
          /overview/i,
          /results/i,
          /findings/i,
          /recommendations/i,
          /next steps/i
        ]

        # Check for deliverable patterns
        deliverable_patterns = [
          /report generated/i,
          /document created/i,
          /file created/i,
          /output generated/i,
          /result saved/i,
          /analysis saved/i
        ]

        # Check for status patterns
        status_patterns = [
          /status: complete/i,
          /status: finished/i,
          /status: done/i,
          /phase.{0,20}complete/i,
          /stage.{0,20}complete/i
        ]

        found_indicators = []
        max_confidence = 0.0
        completion_type = nil

        # Check summary patterns
        if summary_patterns.any? { |pattern| text_content.match?(pattern) }
          found_indicators << "summary_patterns"
          max_confidence = [max_confidence, 0.8].max
          completion_type = "implicit_summary"
        end

        # Check deliverable patterns
        if deliverable_patterns.any? { |pattern| text_content.match?(pattern) }
          found_indicators << "deliverable_patterns"
          max_confidence = [max_confidence, 0.8].max
          completion_type = "implicit_deliverable"
        end

        # Check status patterns
        if status_patterns.any? { |pattern| text_content.match?(pattern) }
          found_indicators << "status_patterns"
          max_confidence = [max_confidence, 0.7].max
          completion_type = "implicit_status"
        end

        # Check for progress completion
        if progress && progress.completed_steps.size > 0
          completion_ratio = progress.completed_steps.size.to_f / progress.total_steps
          if completion_ratio >= 0.8 # 80% or more complete
            found_indicators << "high_progress_ratio"
            max_confidence = [max_confidence, 0.6].max
            completion_type = "implicit_high_progress"
          end
        end

        {
          found: max_confidence > 0.0,
          type: completion_type,
          confidence: max_confidence,
          indicators: found_indicators
        }
      end

      # Detect partial completion and next actions
      def detect_partial_completion(text_content, progress)
        next_actions = []
        status = "in_progress"

        # Check for next action indicators
        next_action_patterns = [
          /next step/i,
          /next action/i,
          /continue with/i,
          /proceed to/i,
          /move to/i,
          /now\s+will/i,
          /next\s+will/i
        ]

        if next_action_patterns.any? { |pattern| text_content.match?(pattern) }
          status = "has_next_actions"
          next_actions << "continue_execution"
        end

        # Check for waiting patterns
        waiting_patterns = [
          /waiting for/i,
          /pending/i,
          /awaiting/i,
          /need\s+input/i,
          /require\s+input/i
        ]

        if waiting_patterns.any? { |pattern| text_content.match?(pattern) }
          status = "waiting_for_input"
          next_actions << "collect_user_input"
        end

        # Check for error patterns
        error_patterns = [
          /error/i,
          /failed/i,
          /issue/i,
          /problem/i,
          /exception/i
        ]

        if error_patterns.any? { |pattern| text_content.match?(pattern) }
          status = "has_errors"
          next_actions << "handle_errors"
        end

        # Check progress status only if no specific status was detected from text
        if status == "in_progress" && progress
          completion_ratio = progress.completed_steps.size.to_f / progress.total_steps
          if completion_ratio >= 0.8
            status = "near_completion"
            next_actions << "continue_to_completion"
          elsif completion_ratio >= 0.5
            status = "half_complete"
            next_actions << "continue_execution"
          elsif completion_ratio >= 0.2
            status = "early_stage"
            next_actions << "continue_execution"
          else
            status = "just_started"
            next_actions << "continue_execution"
          end
        end

        {
          status: status,
          next_actions: next_actions
        }
      end

      # Classify error type with comprehensive analysis
      def classify_error(error)
        return :unknown unless error.is_a?(StandardError)

        error_info = extract_error_info(error)
        error_info[:type]
      end

      # Extract comprehensive error information
      def extract_error_info(error)
        return {type: :unknown, severity: :low, recoverable: true} unless error.is_a?(StandardError)

        error_message = error.message.downcase
        error_class = error.class.name.downcase

        # Get error classification
        error_type = classify_error_type(error_message, error_class)
        severity = determine_error_severity(error_type, error_message)
        recoverable = determine_recoverability(error_type, error_message)
        retry_strategy = determine_retry_strategy(error_type, error_message)

        {
          type: error_type,
          severity: severity,
          recoverable: recoverable,
          retry_strategy: retry_strategy,
          message: error.message,
          class: error.class.name,
          backtrace: error.backtrace&.first(5)
        }
      end

      # Classify error type based on message and class
      def classify_error_type(error_message, error_class)
        # Network and connectivity errors
        if error_message.match?(/timeout/i) || error_class.include?("timeout")
          :timeout
        elsif error_message.match?(/connection/i) || error_message.match?(/network/i) ||
            error_class.include?("connection") || error_class.include?("network")
          :network
        elsif error_message.match?(/dns/i) || error_message.match?(/resolve/i)
          :dns_resolution
        elsif error_message.match?(/ssl/i) || error_message.match?(/tls/i) || error_message.match?(/certificate/i)
          :ssl_tls

        # Authentication and authorization errors
        elsif error_message.match?(/authentication/i) || error_message.match?(/unauthorized/i) ||
            error_message.match?(/401/i) || error_class.include?("authentication")
          :authentication
        elsif error_message.match?(/permission/i) || error_message.match?(/forbidden/i) ||
            error_message.match?(/403/i) || error_class.include?("permission")
          :permission
        elsif error_message.match?(/access.{0,20}denied/i) || error_message.match?(/insufficient.{0,20}privileges/i)
          :access_denied

        # File and I/O errors (check these first as they're more specific)
        elsif error_message.match?(/file.{0,20}not.{0,20}found/i) || error_message.match?(/no.{0,20}such.{0,20}file/i)
          :file_not_found

        # HTTP and API errors
        elsif error_message.match?(/not found/i) || error_message.match?(/404/i)
          :not_found
        elsif error_message.match?(/server error/i) || error_message.match?(/500/i) ||
            error_message.match?(/internal.{0,20}error/i)
          :server_error
        elsif error_message.match?(/bad request/i) || error_message.match?(/400/i) ||
            error_message.match?(/invalid.{0,20}request/i)
          :bad_request
        elsif error_message.match?(/rate limit/i) || error_message.match?(/429/i) ||
            error_message.match?(/too many requests/i)
          :rate_limit
        elsif error_message.match?(/quota.{0,20}exceeded/i) || error_message.match?(/usage.{0,20}limit/i)
          :quota_exceeded
        elsif error_message.match?(/permission.{0,20}denied/i) || error_message.match?(/eacces/i)
          :file_permission
        elsif error_message.match?(/disk.{0,20}full/i) || error_message.match?(/no.{0,20}space/i)
          :disk_full
        elsif error_message.match?(/read.{0,20}only/i) || error_message.match?(/eacces/i)
          :read_only_filesystem

        # Memory and resource errors
        elsif error_message.match?(/memory/i) || error_message.match?(/out of memory/i) ||
            error_class.include?("memory")
          :memory_error
        elsif error_message.match?(/resource.{0,20}unavailable/i) || error_message.match?(/resource.{0,20}exhausted/i)
          :resource_exhausted

        # Configuration and setup errors
        elsif error_message.match?(/configuration/i) || error_message.match?(/config/i) ||
            error_class.include?("configuration")
          :configuration
        elsif error_message.match?(/missing.{0,20}dependency/i) || error_message.match?(/gem.{0,20}not found/i)
          :missing_dependency
        elsif error_message.match?(/environment/i) || error_message.match?(/env/i)
          :environment

        # Provider-specific errors
        elsif error_message.match?(/anthropic/i) || error_message.match?(/claude/i)
          :anthropic_error
        elsif error_message.match?(/openai/i) || error_message.match?(/gpt/i)
          :openai_error
        elsif error_message.match?(/google/i) || error_message.match?(/gemini/i)
          :google_error
        elsif error_message.match?(/cursor/i)
          :cursor_error

        # Parsing and format errors
        elsif error_message.match?(/parse/i) || error_message.match?(/json/i) ||
            error_message.match?(/syntax/i) || error_class.include?("parse")
          :parsing_error
        elsif error_message.match?(/format/i) || error_message.match?(/invalid.{0,20}format/i)
          :format_error

        # Validation errors
        elsif error_message.match?(/validation/i) || error_message.match?(/invalid.{0,20}input/i) ||
            error_class.include?("validation")
          :validation_error
        elsif error_message.match?(/argument/i) || error_message.match?(/parameter/i)
          :argument_error

        # System errors
        elsif error_message.match?(/system/i) || error_class.include?("system")
          :system_error
        elsif error_message.match?(/interrupt/i) || error_message.match?(/sigint/i) ||
            error_class.include?("interrupt")
          :interrupted

        else
          :unknown
        end
      end

      # Determine error severity
      def determine_error_severity(error_type, _error_message)
        case error_type
        when :authentication, :permission, :access_denied, :configuration, :missing_dependency
          :critical
        when :rate_limit, :quota_exceeded, :disk_full, :memory_error, :resource_exhausted
          :high
        when :timeout, :network, :dns_resolution, :ssl_tls, :server_error, :bad_request
          :medium
        when :not_found, :file_not_found, :file_permission, :read_only_filesystem
          :medium
        when :parsing_error, :format_error, :validation_error, :argument_error
          :low
        when :interrupted, :system_error
          :high
        else
          :medium
        end
      end

      # Determine if error is recoverable
      def determine_recoverability(error_type, _error_message)
        case error_type
        when :authentication, :permission, :access_denied, :configuration, :missing_dependency
          false
        when :rate_limit, :quota_exceeded, :timeout, :network, :dns_resolution, :ssl_tls
          true
        when :server_error, :bad_request, :not_found, :file_not_found
          true
        when :disk_full, :memory_error, :resource_exhausted
          false
        when :file_permission, :read_only_filesystem
          false
        when :parsing_error, :format_error, :validation_error, :argument_error
          true
        when :interrupted, :system_error
          false
        else
          # Unknown errors are considered recoverable with caution
          true
        end
      end

      # Determine retry strategy
      def determine_retry_strategy(error_type, _error_message)
        case error_type
        when :timeout, :network, :dns_resolution, :ssl_tls
          {strategy: :exponential_backoff, max_retries: 3, base_delay: 5}
        when :rate_limit, :quota_exceeded
          {strategy: :fixed_delay, max_retries: 2, delay: 60}
        when :server_error, :bad_request
          {strategy: :exponential_backoff, max_retries: 2, base_delay: 10}
        when :not_found, :file_not_found
          {strategy: :no_retry, max_retries: 0, delay: 0}
        when :parsing_error, :format_error, :validation_error, :argument_error
          {strategy: :no_retry, max_retries: 0, delay: 0}
        when :authentication, :permission, :access_denied, :configuration, :missing_dependency
          {strategy: :no_retry, max_retries: 0, delay: 0}
        when :disk_full, :memory_error, :resource_exhausted
          {strategy: :no_retry, max_retries: 0, delay: 0}
        when :interrupted, :system_error
          {strategy: :no_retry, max_retries: 0, delay: 0}
        else
          {strategy: :exponential_backoff, max_retries: 1, base_delay: 5}
        end
      end

      # Check if error is recoverable
      def recoverable_error?(error)
        error_info = extract_error_info(error)
        error_info[:recoverable]
      end

      # Get retry delay for error type
      def retry_delay_for_error(error, attempt_number)
        error_info = extract_error_info(error)
        retry_strategy = error_info[:retry_strategy]

        case retry_strategy[:strategy]
        when :exponential_backoff
          retry_strategy[:base_delay] * (2**(attempt_number - 1))
        when :fixed_delay
          retry_strategy[:delay]
        when :no_retry
          0
        else
          5 # Default delay
        end
      end

      # Get maximum retries for error type
      def max_retries_for_error(error)
        error_info = extract_error_info(error)
        error_info[:retry_strategy][:max_retries]
      end

      # Get error severity
      def get_error_severity(error)
        error_info = extract_error_info(error)
        error_info[:severity]
      end

      # Check if error is high severity
      def high_severity_error?(error)
        [:critical, :high].include?(get_error_severity(error))
      end

      # Get error description
      def get_error_description(error)
        error_info = extract_error_info(error)
        error_type = error_info[:type]

        case error_type
        when :timeout
          "Request timed out"
        when :network
          "Network connection error"
        when :dns_resolution
          "DNS resolution failed"
        when :ssl_tls
          "SSL/TLS connection error"
        when :authentication
          "Authentication failed"
        when :permission
          "Permission denied"
        when :access_denied
          "Access denied"
        when :not_found
          "Resource not found"
        when :server_error
          "Server error"
        when :bad_request
          "Bad request"
        when :rate_limit
          "Rate limit exceeded"
        when :quota_exceeded
          "Quota exceeded"
        when :file_not_found
          "File not found"
        when :file_permission
          "File permission denied"
        when :disk_full
          "Disk full"
        when :read_only_filesystem
          "Read-only filesystem"
        when :memory_error
          "Memory error"
        when :resource_exhausted
          "Resource exhausted"
        when :configuration
          "Configuration error"
        when :missing_dependency
          "Missing dependency"
        when :environment
          "Environment error"
        when :anthropic_error
          "Anthropic API error"
        when :openai_error
          "OpenAI API error"
        when :google_error
          "Google API error"
        when :cursor_error
          "Cursor API error"
        when :parsing_error
          "Parsing error"
        when :format_error
          "Format error"
        when :validation_error
          "Validation error"
        when :argument_error
          "Argument error"
        when :system_error
          "System error"
        when :interrupted
          "Operation interrupted"
        else
          "Unknown error"
        end
      end

      # Get error recovery suggestions
      def get_error_recovery_suggestions(error)
        error_info = extract_error_info(error)
        error_type = error_info[:type]

        case error_type
        when :timeout, :network, :dns_resolution, :ssl_tls
          ["Check network connection", "Retry the operation", "Check firewall settings"]
        when :authentication, :permission, :access_denied
          ["Check credentials", "Verify permissions", "Contact administrator"]
        when :rate_limit, :quota_exceeded
          ["Wait before retrying", "Check usage limits", "Consider upgrading plan"]
        when :file_not_found, :file_permission
          ["Check file path", "Verify file permissions", "Ensure file exists"]
        when :disk_full, :memory_error, :resource_exhausted
          ["Free up disk space", "Increase memory", "Check system resources"]
        when :configuration, :missing_dependency, :environment
          ["Check configuration", "Install missing dependencies", "Verify environment setup"]
        when :parsing_error, :format_error, :validation_error, :argument_error
          ["Check input format", "Validate parameters", "Review data structure"]
        when :server_error, :bad_request
          ["Retry the operation", "Check request format", "Contact service provider"]
        else
          ["Review error details", "Check logs", "Contact support"]
        end
      end

      # Check if a provider is currently rate limited
      def is_provider_rate_limited?(provider, rate_limit_info)
        return false unless rate_limit_info && rate_limit_info[:provider] == provider

        # Check if the rate limit has expired
        if rate_limit_info[:reset_time] && rate_limit_info[:reset_time] > Time.now
          return true
        end

        false
      end

      # Get time until rate limit resets
      def time_until_reset(rate_limit_info)
        return 0 unless rate_limit_info && rate_limit_info[:reset_time]

        reset_time = rate_limit_info[:reset_time]
        remaining = reset_time - Time.now
        [remaining, 0].max
      end

      # Check if rate limit has expired
      def rate_limit_expired?(rate_limit_info)
        return true unless rate_limit_info && rate_limit_info[:reset_time]

        rate_limit_info[:reset_time] <= Time.now
      end

      # Get all available rate limit patterns for a provider
      def get_rate_limit_patterns(provider = nil)
        if provider && @rate_limit_patterns[provider.to_sym]
          @rate_limit_patterns[:common] + @rate_limit_patterns[provider.to_sym]
        else
          @rate_limit_patterns[:common]
        end
      end

      # Check if operation has timed out
      def is_timeout?(result, start_time, timeout_duration = nil)
        return false unless result.is_a?(Hash) && start_time.is_a?(Time)

        # Check for explicit timeout indicators in result
        if has_timeout_indicators?(result)
          return true
        end

        # Check if operation duration exceeds timeout
        if timeout_duration && (Time.now - start_time) > timeout_duration
          return true
        end

        false
      end

      # Check for timeout indicators in result
      def has_timeout_indicators?(result)
        return false unless result.is_a?(Hash)

        # Get all text content to analyze
        text_content = [
          result[:output],
          result[:message],
          result[:response],
          result[:body],
          result[:error]
        ].compact.join(" ")

        return false if text_content.empty?

        # Check for timeout patterns
        timeout_patterns = [
          /timeout/i,
          /timed out/i,
          /time.{0,20}out/i,
          /request.{0,20}timeout/i,
          /connection.{0,20}timeout/i,
          /read.{0,20}timeout/i,
          /write.{0,20}timeout/i,
          /operation.{0,20}timeout/i,
          /execution.{0,20}timeout/i,
          /deadline.{0,20}exceeded/i,
          /time.{0,20}limit.{0,20}exceeded/i,
          /time.{0,20}expired/i
        ]

        timeout_patterns.any? { |pattern| text_content.match?(pattern) }
      end

      # Extract timeout information from result
      def extract_timeout_info(result, start_time, timeout_duration = nil)
        timeout_info = {
          is_timeout: false,
          timeout_type: nil,
          duration: nil,
          timeout_duration: timeout_duration,
          exceeded_by: nil,
          indicators: []
        }

        return timeout_info unless result.is_a?(Hash) && start_time.is_a?(Time)

        # Check for explicit timeout indicators
        if has_timeout_indicators?(result)
          timeout_info[:is_timeout] = true
          timeout_info[:timeout_type] = "explicit"
          timeout_info[:indicators] = extract_timeout_indicators(result)
        end

        # Check for duration-based timeout
        if timeout_duration
          duration = Time.now - start_time
          timeout_info[:duration] = duration

          if duration > timeout_duration
            timeout_info[:is_timeout] = true
            timeout_info[:timeout_type] = "duration"
            timeout_info[:exceeded_by] = duration - timeout_duration
          end
        end

        timeout_info
      end

      # Extract timeout indicators from result
      def extract_timeout_indicators(result)
        text_content = [
          result[:output],
          result[:message],
          result[:response],
          result[:body],
          result[:error]
        ].compact.join(" ")

        timeout_patterns = [
          /timeout/i,
          /timed out/i,
          /time.{0,20}out/i,
          /request.{0,20}timeout/i,
          /connection.{0,20}timeout/i,
          /read.{0,20}timeout/i,
          /write.{0,20}timeout/i,
          /operation.{0,20}timeout/i,
          /execution.{0,20}timeout/i,
          /deadline.{0,20}exceeded/i,
          /time.{0,20}limit.{0,20}exceeded/i,
          /time.{0,20}expired/i
        ]

        found_indicators = []
        timeout_patterns.each do |pattern|
          if text_content.match?(pattern)
            found_indicators << pattern.source
          end
        end

        found_indicators
      end

      # Get timeout duration for operation type
      def get_timeout_duration(operation_type, configuration = nil)
        default_timeouts = {
          analyze: 300, # 5 minutes
          execute: 600, # 10 minutes
          provider_call: 120, # 2 minutes
          file_operation: 30, # 30 seconds
          network_request: 60, # 1 minute
          user_input: 300, # 5 minutes
          default: 120 # 2 minutes
        }

        # Get timeout from configuration if available
        if configuration && configuration[:timeouts] && configuration[:timeouts][operation_type]
          return configuration[:timeouts][operation_type]
        end

        # Return default timeout for operation type
        default_timeouts[operation_type] || default_timeouts[:default]
      end

      # Get time remaining until timeout
      def time_until_timeout(start_time, timeout_duration)
        return 0 unless start_time.is_a?(Time) && timeout_duration

        elapsed = Time.now - start_time
        remaining = timeout_duration - elapsed
        [remaining, 0].max
      end

      # Get timeout status description
      def get_timeout_status_description(timeout_info)
        return "No timeout" unless timeout_info && timeout_info[:is_timeout]

        case timeout_info[:timeout_type]
        when "explicit"
          "Operation timed out (explicit timeout detected)"
        when "duration"
          if timeout_info[:exceeded_by]
            "Operation timed out (exceeded by #{timeout_info[:exceeded_by].round(2)}s)"
          else
            "Operation timed out (duration exceeded)"
          end
        else
          "Operation timed out"
        end
      end

      # Get timeout recovery suggestions
      def get_timeout_recovery_suggestions(timeout_info, operation_type = nil)
        suggestions = []

        case timeout_info[:timeout_type]
        when "explicit"
          suggestions << "Check network connection"
          suggestions << "Verify service availability"
          suggestions << "Retry with longer timeout"
        when "duration"
          suggestions << "Increase timeout duration"
          suggestions << "Optimize operation performance"
          suggestions << "Break operation into smaller chunks"
        end

        # Add operation-specific suggestions
        case operation_type
        when :analyze
          suggestions << "Reduce analysis scope"
          suggestions << "Use incremental analysis"
        when :execute
          suggestions << "Break execution into smaller steps"
          suggestions << "Optimize execution performance"
        when :provider_call
          suggestions << "Check provider status"
          suggestions << "Try different provider"
        when :file_operation
          suggestions << "Check file system performance"
          suggestions << "Verify file permissions"
        when :network_request
          suggestions << "Check network connectivity"
          suggestions << "Verify endpoint availability"
        end

        suggestions.uniq
      end

      # Validate user response based on expected input type
      def validate_user_response(response, expected_input_type)
        return false if response.nil? || response.strip.empty?

        case expected_input_type
        when "email"
          response.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
        when "url"
          response.match?(/\Ahttps?:\/\/.+/i)
        when "number"
          response.match?(/^\d+$/)
        when "boolean"
          response.match?(/^(yes|no|true|false|y|n|1|0)$/i)
        when "file"
          response.match?(/^@/) || File.exist?(response)
        when "path"
          File.exist?(response) || Dir.exist?(response)
        else
          # For text input, just check it's not empty
          !response.strip.empty?
        end
      end

      # Get user feedback patterns for a specific type
      def get_user_feedback_patterns(feedback_type = nil)
        if feedback_type && @user_feedback_patterns[feedback_type.to_sym]
          @user_feedback_patterns[feedback_type.to_sym]
        else
          @user_feedback_patterns.values.flatten
        end
      end

      # Get completion confidence level
      def completion_confidence(completion_info)
        return 0.0 unless completion_info && completion_info[:confidence]

        completion_info[:confidence]
      end

      # Check if completion is high confidence
      def high_confidence_completion?(completion_info)
        completion_confidence(completion_info) >= 0.8
      end

      # Check if completion is medium confidence
      def medium_confidence_completion?(completion_info)
        confidence = completion_confidence(completion_info)
        confidence >= 0.5 && confidence < 0.8
      end

      # Check if completion is low confidence
      def low_confidence_completion?(completion_info)
        confidence = completion_confidence(completion_info)
        confidence > 0.0 && confidence < 0.5
      end

      # Get next actions from completion info
      def next_actions(completion_info)
        return [] unless completion_info && completion_info[:next_actions]

        completion_info[:next_actions]
      end

      # Check if work is in progress
      def is_work_in_progress?(completion_info)
        return false unless completion_info

        !completion_info[:is_complete] &&
          completion_info[:progress_status] != "waiting_for_input" &&
          completion_info[:progress_status] != "has_errors"
      end

      # Check if work is waiting for input
      def is_waiting_for_input?(completion_info)
        return false unless completion_info

        if completion_info[:progress_status] == "waiting_for_input"
          return true
        end

        if completion_info[:next_actions]&.include?("collect_user_input")
          return true
        end

        false
      end

      # Check if work has errors
      def has_errors?(completion_info)
        return false unless completion_info

        if completion_info[:progress_status] == "has_errors"
          return true
        end

        if completion_info[:next_actions]&.include?("handle_errors")
          return true
        end

        false
      end

      # Get progress status description
      def progress_status_description(completion_info)
        return "unknown" unless completion_info

        case completion_info[:progress_status]
        when "all_steps_completed"
          "All steps completed successfully"
        when "near_completion"
          "Near completion (80%+ done)"
        when "half_complete"
          "Half complete (50%+ done)"
        when "early_stage"
          "Early stage (20%+ done)"
        when "just_started"
          "Just started (0-20% done)"
        when "has_next_actions"
          "Has next actions to perform"
        when "waiting_for_input"
          "Waiting for user input"
        when "has_errors"
          "Has errors that need attention"
        when "in_progress"
          "Work in progress"
        else
          "Status unknown"
        end
      end
    end
  end
end
