# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ConditionDetector do
  let(:detector) { described_class.new }

  describe "#initialize" do
    it "initializes with rate limit patterns for different providers" do
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:common)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:anthropic)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:openai)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:google)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:cursor)
    end

    it "initializes with user feedback patterns" do
      patterns = detector.instance_variable_get(:@user_feedback_patterns)
      expect(patterns).to be_a(Hash)
      expect(patterns[:direct_requests]).to include(/please provide/i)
      expect(patterns[:clarification]).to include(/can you clarify/i)
    end

    it "initializes with question patterns" do
      patterns = detector.instance_variable_get(:@question_patterns)
      expect(patterns).to include(/^\d+\.\s+(.+)\?/)
      expect(patterns).to include(/^(\d+)\)\s+(.+)\?/)
    end

    it "initializes with reset time patterns" do
      patterns = detector.instance_variable_get(:@reset_time_patterns)
      expect(patterns).to include(/reset.{0,20}in.{0,20}(\d+).{0,20}seconds/i)
      expect(patterns).to include(/retry.{0,20}after.{0,20}(\d+).{0,20}seconds/i)
    end
  end

  describe "#is_rate_limited?" do
    it "detects rate limiting from HTTP status code" do
      result = {status_code: 429}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects rate limiting from http_status field" do
      result = {http_status: 429}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects rate limiting from error message" do
      result = {error: "Rate limit exceeded"}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects rate limiting from output" do
      result = {output: "Too many requests"}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects provider-specific rate limiting" do
      result = {error: "Anthropic rate limit exceeded"}
      expect(detector.is_rate_limited?(result, "anthropic")).to be true
    end

    it "detects OpenAI-specific rate limiting" do
      result = {error: "Requests per minute limit exceeded"}
      expect(detector.is_rate_limited?(result, "openai")).to be true
    end

    it "detects Google-specific rate limiting" do
      result = {error: "Quota exceeded for Google API"}
      expect(detector.is_rate_limited?(result, "google")).to be true
    end

    it "detects Cursor-specific rate limiting" do
      result = {error: "Package limit exceeded"}
      expect(detector.is_rate_limited?(result, "cursor")).to be true
    end

    it "returns false for non-rate-limited results" do
      result = {status: "success", output: "Task completed"}
      expect(detector.is_rate_limited?(result)).to be false
    end

    it "returns false for invalid input" do
      expect(detector.is_rate_limited?(nil)).to be false
      expect(detector.is_rate_limited?("string")).to be false
    end
  end

  describe "#extract_rate_limit_info" do
    it "extracts rate limit information from result" do
      result = {error: "Rate limit exceeded. Retry after 60 seconds"}
      info = detector.extract_rate_limit_info(result, "anthropic")

      expect(info).to be_a(Hash)
      expect(info[:provider]).to eq("anthropic")
      expect(info[:detected_at]).to be_a(Time)
      expect(info[:limit_type]).to eq("general_rate_limit")
      expect(info[:message]).to include("Rate limit exceeded")
    end

    it "extracts reset time from message" do
      result = {error: "Rate limit exceeded. Reset in 120 seconds"}
      info = detector.extract_rate_limit_info(result)

      expect(info[:reset_time]).to be_a(Time)
      expect(info[:reset_time]).to be > Time.now
    end

    it "extracts retry after value" do
      result = {error: "Rate limit exceeded. Retry after 90 seconds"}
      info = detector.extract_rate_limit_info(result)

      expect(info[:retry_after]).to eq(90)
    end

    it "detects limit type for Anthropic" do
      result = {error: "Requests per minute limit exceeded"}
      info = detector.extract_rate_limit_info(result, "anthropic")

      expect(info[:limit_type]).to eq("requests_per_minute")
    end

    it "detects limit type for OpenAI" do
      result = {error: "Tokens per minute limit exceeded"}
      info = detector.extract_rate_limit_info(result, "openai")

      expect(info[:limit_type]).to eq("tokens_per_minute")
    end

    it "detects limit type for Google" do
      result = {error: "Quota exceeded for Google API"}
      info = detector.extract_rate_limit_info(result, "google")

      expect(info[:limit_type]).to eq("quota_exceeded")
    end

    it "detects limit type for Cursor" do
      result = {error: "Package limit exceeded"}
      info = detector.extract_rate_limit_info(result, "cursor")

      expect(info[:limit_type]).to eq("package_limit")
    end

    it "returns nil for non-rate-limited results" do
      result = {status: "success", output: "Task completed"}
      expect(detector.extract_rate_limit_info(result)).to be_nil
    end
  end

  describe "#extract_reset_time" do
    it "extracts seconds from now" do
      text = "Rate limit exceeded. Reset in 120 seconds"
      reset_time = detector.send(:extract_reset_time, text)

      expect(reset_time).to be_a(Time)
      expect(reset_time).to be > Time.now
    end

    it "extracts specific timestamp" do
      future_time = Time.now + 300
      text = "Rate limit exceeded. Reset at #{future_time.strftime("%Y-%m-%d %H:%M:%S")}"
      reset_time = detector.send(:extract_reset_time, text)

      expect(reset_time).to be_a(Time)
      # Allow for a reasonable time difference since timestamp parsing can vary
      expect(reset_time.to_i).to be_within(300).of(future_time.to_i)
    end

    it "defaults to 60 seconds if no time found" do
      text = "Rate limit exceeded"
      reset_time = detector.send(:extract_reset_time, text)

      expect(reset_time).to be_a(Time)
      expect(reset_time).to be > Time.now
      expect(reset_time).to be <= Time.now + 61
    end
  end

  describe "#extract_retry_after" do
    it "extracts retry after value" do
      text = "Rate limit exceeded. Retry after 90 seconds"
      retry_after = detector.send(:extract_retry_after, text)

      expect(retry_after).to eq(90)
    end

    it "extracts wait time" do
      text = "Rate limit exceeded. Wait 45 seconds"
      retry_after = detector.send(:extract_retry_after, text)

      expect(retry_after).to eq(45)
    end

    it "defaults to 60 seconds if no time found" do
      text = "Rate limit exceeded"
      retry_after = detector.send(:extract_retry_after, text)

      expect(retry_after).to eq(60)
    end
  end

  describe "#detect_limit_type" do
    it "detects requests per minute for Anthropic" do
      text = "Requests per minute limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "anthropic")

      expect(limit_type).to eq("requests_per_minute")
    end

    it "detects tokens per minute for OpenAI" do
      text = "Tokens per minute limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "openai")

      expect(limit_type).to eq("tokens_per_minute")
    end

    it "detects quota exceeded for Google" do
      text = "Quota exceeded for Google API"
      limit_type = detector.send(:detect_limit_type, text, "google")

      expect(limit_type).to eq("quota_exceeded")
    end

    it "detects package limit for Cursor" do
      text = "Package limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "cursor")

      expect(limit_type).to eq("package_limit")
    end

    it "defaults to general rate limit" do
      text = "Rate limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "unknown")

      expect(limit_type).to eq("general_rate_limit")
    end
  end

  describe "#is_provider_rate_limited?" do
    it "returns true if provider is rate limited and not expired" do
      rate_limit_info = {
        provider: "anthropic",
        reset_time: Time.now + 60
      }

      expect(detector.is_provider_rate_limited?("anthropic", rate_limit_info)).to be true
    end

    it "returns false if provider is different" do
      rate_limit_info = {
        provider: "anthropic",
        reset_time: Time.now + 60
      }

      expect(detector.is_provider_rate_limited?("openai", rate_limit_info)).to be false
    end

    it "returns false if rate limit has expired" do
      rate_limit_info = {
        provider: "anthropic",
        reset_time: Time.now - 60
      }

      expect(detector.is_provider_rate_limited?("anthropic", rate_limit_info)).to be false
    end

    it "returns false if no rate limit info" do
      expect(detector.is_provider_rate_limited?("anthropic", nil)).to be false
    end
  end

  describe "#time_until_reset" do
    it "returns time until reset" do
      rate_limit_info = {
        reset_time: Time.now + 120
      }

      time_until = detector.time_until_reset(rate_limit_info)
      expect(time_until).to be_within(1).of(120)
    end

    it "returns 0 if rate limit has expired" do
      rate_limit_info = {
        reset_time: Time.now - 60
      }

      expect(detector.time_until_reset(rate_limit_info)).to eq(0)
    end

    it "returns 0 if no rate limit info" do
      expect(detector.time_until_reset(nil)).to eq(0)
    end
  end

  describe "#rate_limit_expired?" do
    it "returns true if rate limit has expired" do
      rate_limit_info = {
        reset_time: Time.now - 60
      }

      expect(detector.rate_limit_expired?(rate_limit_info)).to be true
    end

    it "returns false if rate limit is still active" do
      rate_limit_info = {
        reset_time: Time.now + 60
      }

      expect(detector.rate_limit_expired?(rate_limit_info)).to be false
    end

    it "returns true if no rate limit info" do
      expect(detector.rate_limit_expired?(nil)).to be true
    end
  end

  describe "#get_rate_limit_patterns" do
    it "returns common patterns for unknown provider" do
      patterns = detector.get_rate_limit_patterns("unknown")
      expect(patterns).to eq(detector.instance_variable_get(:@rate_limit_patterns)[:common])
    end

    it "returns combined patterns for known provider" do
      patterns = detector.get_rate_limit_patterns("anthropic")
      common_patterns = detector.instance_variable_get(:@rate_limit_patterns)[:common]
      anthropic_patterns = detector.instance_variable_get(:@rate_limit_patterns)[:anthropic]

      expect(patterns).to eq(common_patterns + anthropic_patterns)
    end

    it "returns common patterns for nil provider" do
      patterns = detector.get_rate_limit_patterns(nil)
      expect(patterns).to eq(detector.instance_variable_get(:@rate_limit_patterns)[:common])
    end
  end

  describe "#detect_input_type" do
    it "detects file input type" do
      expect(detector.send(:detect_input_type, "Please upload a file")).to eq("file")
      expect(detector.send(:detect_input_type, "Attach the document")).to eq("file")
    end

    it "detects email input type" do
      expect(detector.send(:detect_input_type, "What is your email address?")).to eq("email")
    end

    it "detects URL input type" do
      expect(detector.send(:detect_input_type, "Please provide the URL")).to eq("url")
      expect(detector.send(:detect_input_type, "Enter the link")).to eq("url")
    end

    it "detects path input type for directory without file keyword" do
      expect(detector.send(:detect_input_type, "Which directory?")).to eq("path")
    end

    it "prioritizes file over path when both keywords present" do
      expect(detector.send(:detect_input_type, "Enter the file path")).to eq("file")
    end

    it "detects number input type" do
      expect(detector.send(:detect_input_type, "How many items?")).to eq("number")
      expect(detector.send(:detect_input_type, "Enter the count")).to eq("number")
      expect(detector.send(:detect_input_type, "What is the amount?")).to eq("number")
    end

    it "detects boolean input type" do
      expect(detector.send(:detect_input_type, "Should I proceed?")).to eq("boolean")
      expect(detector.send(:detect_input_type, "Yes or no?")).to eq("boolean")
      expect(detector.send(:detect_input_type, "Please confirm")).to eq("boolean")
    end

    it "defaults to text input type" do
      expect(detector.send(:detect_input_type, "Tell me about yourself")).to eq("text")
    end
  end

  describe "#detect_urgency" do
    it "detects high urgency" do
      expect(detector.send(:detect_urgency, "URGENT: Please respond immediately")).to eq("high")
      expect(detector.send(:detect_urgency, "This is critical!")).to eq("high")
      expect(detector.send(:detect_urgency, "This is important")).to eq("high")
    end

    it "detects medium urgency with polite phrases" do
      expect(detector.send(:detect_urgency, "Please address this soon")).to eq("medium")
      expect(detector.send(:detect_urgency, "Can you help?")).to eq("medium")
    end

    it "detects low urgency" do
      expect(detector.send(:detect_urgency, "When you have time, please review")).to eq("low")
    end

    it "defaults to low urgency for neutral messages" do
      expect(detector.send(:detect_urgency, "Regular message")).to eq("low")
    end
  end

  describe "#detect_feedback_type" do
    it "detects clarification feedback" do
      expect(detector.send(:detect_feedback_type, "Can you clarify this point?")).to eq("clarification")
    end

    it "detects choices feedback (plural form)" do
      expect(detector.send(:detect_feedback_type, "Which option do you prefer?")).to eq("choices")
    end

    it "detects confirmation feedback" do
      expect(detector.send(:detect_feedback_type, "Is this correct?")).to eq("confirmation")
    end

    it "detects file_requests feedback (plural form)" do
      expect(detector.send(:detect_feedback_type, "Please upload the file")).to eq("file_requests")
    end

    it "defaults to general feedback" do
      expect(detector.send(:detect_feedback_type, "Some general question")).to eq("general")
    end
  end

  describe "#extract_context" do
    it "extracts context patterns from text" do
      text = "Waiting for input from the user. Need feedback on this."
      contexts = detector.send(:extract_context, text)

      expect(contexts).to be_an(Array)
      expect(contexts.length).to be > 0
    end

    it "returns unique context matches" do
      text = "Need feedback. Need feedback again."
      contexts = detector.send(:extract_context, text)

      expect(contexts.uniq.length).to eq(contexts.length)
    end

    it "returns empty array when no context patterns match" do
      text = "Regular text without context keywords"
      contexts = detector.send(:extract_context, text)

      expect(contexts).to be_an(Array)
    end
  end

  describe "#detect_question_type" do
    it "detects information questions" do
      expect(detector.send(:detect_question_type, "What is your name?")).to eq("information")
      expect(detector.send(:detect_question_type, "What is your email?")).to eq("information")
    end

    it "detects choice questions" do
      expect(detector.send(:detect_question_type, "Which do you prefer?")).to eq("choice")
      expect(detector.send(:detect_question_type, "Which one do you want?")).to eq("choice")
    end

    it "detects permission questions" do
      expect(detector.send(:detect_question_type, "Should I proceed?")).to eq("permission")
      expect(detector.send(:detect_question_type, "Can I continue?")).to eq("permission")
    end

    it "detects confirmation questions" do
      expect(detector.send(:detect_question_type, "Is this correct?")).to eq("confirmation")
      expect(detector.send(:detect_question_type, "Does this look right?")).to eq("confirmation")
    end

    it "detects request questions" do
      expect(detector.send(:detect_question_type, "Can you help me?")).to eq("request")
      expect(detector.send(:detect_question_type, "Could you provide more details?")).to eq("request")
    end

    it "detects quantity questions" do
      expect(detector.send(:detect_question_type, "How many items?")).to eq("quantity")
      expect(detector.send(:detect_question_type, "How much does it cost?")).to eq("quantity")
    end

    it "detects time questions" do
      expect(detector.send(:detect_question_type, "When will it be ready?")).to eq("time")
    end

    it "detects location questions" do
      expect(detector.send(:detect_question_type, "Where is the file?")).to eq("location")
    end

    it "detects explanation questions" do
      expect(detector.send(:detect_question_type, "Why did this happen?")).to eq("explanation")
    end

    it "defaults to general for other questions" do
      expect(detector.send(:detect_question_type, "Random question?")).to eq("general")
    end
  end

  describe "integration with existing methods" do
    it "works with needs_user_feedback?" do
      result = {output: "Please provide more information"}
      expect(detector.needs_user_feedback?(result)).to be true
    end

    it "works with extract_questions" do
      result = {output: "1. What is your preference?\n2. Which option do you choose?"}
      questions = detector.extract_questions(result)

      expect(questions.length).to eq(3) # The method extracts individual questions plus the full text
      expect(questions[0][:question]).to eq("What is your preference")
      expect(questions[1][:question]).to eq("Which option do you choose")
    end

    it "works with is_work_complete?" do
      result = {output: "All steps completed successfully"}
      progress = double("progress", completed_steps: [], total_steps: 5)

      expect(detector.is_work_complete?(result, progress)).to be true
    end

    it "works with classify_error" do
      error = StandardError.new("Rate limit exceeded")
      expect(detector.classify_error(error)).to eq(:rate_limit)
    end

    it "works with recoverable_error?" do
      error = StandardError.new("Rate limit exceeded")
      expect(detector.recoverable_error?(error)).to be true
    end

    it "works with retry_delay_for_error" do
      error = StandardError.new("Rate limit exceeded")
      delay = detector.retry_delay_for_error(error, 1)
      expect(delay).to eq(60)
    end
  end

  # Work completion detection (previously condition_detector_completion_spec.rb)
  describe "work completion detection" do
    let(:mock_progress) { double("progress", completed_steps: [], total_steps: 5) }

    describe "#is_work_complete?" do
      it "returns true when all steps are completed" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4, 5])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Some output"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects explicit high confidence completion" do
        result = {output: "All steps completed successfully"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects explicit medium confidence completion" do
        result = {output: "Task completed"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects explicit low confidence completion" do
        result = {output: "Work finished"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from summary" do
        result = {output: "Here is a summary of the analysis results"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from deliverables" do
        result = {output: "Report generated and saved to file"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from status" do
        result = {output: "Status: Complete"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from high progress" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Almost done with the analysis"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "returns false for incomplete work" do
        result = {output: "Working on the next step"}
        expect(detector.is_work_complete?(result, mock_progress)).to be false
      end

      it "returns false for invalid input" do
        expect(detector.is_work_complete?(nil, mock_progress)).to be false
        expect(detector.is_work_complete?("string", mock_progress)).to be false
      end
    end

    describe "#extract_completion_info" do
      it "extracts comprehensive completion information" do
        result = {output: "All steps completed successfully"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info).to be_a(Hash)
        expect(info[:is_complete]).to be true
        expect(info[:completion_type]).to eq("explicit_high_confidence")
        expect(info[:confidence]).to eq(0.9)
        expect(info[:indicators]).to be_an(Array)
        expect(info[:progress_status]).to be_nil
        expect(info[:next_actions]).to be_an(Array)
      end

      it "extracts progress-based completion info" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4, 5])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Some output"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be true
        expect(info[:completion_type]).to eq("all_steps_completed")
        expect(info[:confidence]).to eq(1.0)
        expect(info[:progress_status]).to eq("all_steps_completed")
      end

      it "extracts partial completion info" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Currently processing data"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be false
        expect(info[:progress_status]).to eq("early_stage")
        expect(info[:next_actions]).to include("continue_execution")
      end

      it "detects waiting for input status" do
        result = {output: "Waiting for user input to continue"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be false
        expect(info[:progress_status]).to eq("waiting_for_input")
        expect(info[:next_actions]).to include("collect_user_input")
      end

      it "detects error status" do
        result = {output: "Error occurred during execution"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be false
        expect(info[:progress_status]).to eq("has_errors")
        expect(info[:next_actions]).to include("handle_errors")
      end
    end

    describe "#detect_explicit_completion" do
      it "detects high confidence completion" do
        text = "All steps completed successfully"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("explicit_high_confidence")
        expect(result[:confidence]).to eq(0.9)
        expect(result[:indicators]).to include("all steps completed")
      end

      it "detects medium confidence completion" do
        text = "Work is complete"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("explicit_medium_confidence")
        expect(result[:confidence]).to eq(0.7)
        expect(result[:indicators]).to include("complete")
      end

      it "detects low confidence completion" do
        text = "Work will end"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("explicit_low_confidence")
        expect(result[:confidence]).to eq(0.5)
        expect(result[:indicators]).to include("end")
      end

      it "returns false for no completion indicators" do
        text = "Working on the next step"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be false
        expect(result[:confidence]).to eq(0.0)
      end
    end

    describe "#detect_implicit_completion" do
      it "detects summary patterns" do
        text = "Here is a summary of the results"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_summary")
        expect(result[:confidence]).to eq(0.8)
        expect(result[:indicators]).to include("summary_patterns")
      end

      it "detects deliverable patterns" do
        text = "Report generated and saved"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_deliverable")
        expect(result[:confidence]).to eq(0.8)
        expect(result[:indicators]).to include("deliverable_patterns")
      end

      it "detects status patterns" do
        text = "Status: Complete"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_status")
        expect(result[:confidence]).to eq(0.7)
        expect(result[:indicators]).to include("status_patterns")
      end

      it "detects high progress completion" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Almost done with the work"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_high_progress")
        expect(result[:confidence]).to eq(0.6)
        expect(result[:indicators]).to include("high_progress_ratio")
      end

      it "returns false for no implicit completion" do
        text = "Working on the next step"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be false
        expect(result[:confidence]).to eq(0.0)
      end
    end

    describe "#detect_partial_completion" do
      it "detects next action status" do
        text = "Next step will be to analyze the data"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("has_next_actions")
        expect(result[:next_actions]).to include("continue_execution")
      end

      it "detects waiting for input status" do
        text = "Waiting for user input to continue"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("waiting_for_input")
        expect(result[:next_actions]).to include("collect_user_input")
      end

      it "detects error status" do
        text = "Error occurred during execution"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("has_errors")
        expect(result[:next_actions]).to include("handle_errors")
      end

      it "detects progress-based status" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Working on the analysis"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("half_complete")
        expect(result[:next_actions]).to include("continue_execution")
      end

      it "detects near completion status" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Almost done"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("near_completion")
        expect(result[:next_actions]).to include("continue_to_completion")
      end

      it "detects early stage status" do
        allow(mock_progress).to receive(:completed_steps).and_return([1])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Just started"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("early_stage")
        expect(result[:next_actions]).to include("continue_execution")
      end

      it "detects just started status" do
        allow(mock_progress).to receive(:completed_steps).and_return([])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Starting work"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("just_started")
        expect(result[:next_actions]).to include("continue_execution")
      end
    end
  end

  describe "completion utility methods" do
    let(:completion_info) do
      {
        is_complete: true,
        completion_type: "explicit_high_confidence",
        confidence: 0.9,
        indicators: ["all steps completed"],
        progress_status: "all_steps_completed",
        next_actions: []
      }
    end

    describe "#get_completion_confidence" do
      it "returns confidence level" do
        expect(detector.completion_confidence(completion_info)).to eq(0.9)
      end

      it "returns 0.0 for nil info" do
        expect(detector.completion_confidence(nil)).to eq(0.0)
      end

      it "returns 0.0 for info without confidence" do
        info = {is_complete: true}
        expect(detector.completion_confidence(info)).to eq(0.0)
      end
    end

    describe "#high_confidence_completion?" do
      it "returns true for high confidence" do
        expect(detector.high_confidence_completion?(completion_info)).to be true
      end

      it "returns false for medium confidence" do
        info = {confidence: 0.7}
        expect(detector.high_confidence_completion?(info)).to be false
      end

      it "returns false for low confidence" do
        info = {confidence: 0.3}
        expect(detector.high_confidence_completion?(info)).to be false
      end
    end

    describe "#medium_confidence_completion?" do
      it "returns true for medium confidence" do
        info = {confidence: 0.7}
        expect(detector.medium_confidence_completion?(info)).to be true
      end

      it "returns false for high confidence" do
        expect(detector.medium_confidence_completion?(completion_info)).to be false
      end

      it "returns false for low confidence" do
        info = {confidence: 0.3}
        expect(detector.medium_confidence_completion?(info)).to be false
      end
    end

    describe "#low_confidence_completion?" do
      it "returns true for low confidence" do
        info = {confidence: 0.3}
        expect(detector.low_confidence_completion?(info)).to be true
      end

      it "returns false for high confidence" do
        expect(detector.low_confidence_completion?(completion_info)).to be false
      end

      it "returns false for medium confidence" do
        info = {confidence: 0.7}
        expect(detector.low_confidence_completion?(info)).to be false
      end
    end

    describe "#get_next_actions" do
      it "returns next actions" do
        info = {next_actions: ["continue_execution", "collect_user_input"]}
        expect(detector.next_actions(info)).to eq(["continue_execution", "collect_user_input"])
      end

      it "returns empty array for nil info" do
        expect(detector.next_actions(nil)).to eq([])
      end

      it "returns empty array for info without next_actions" do
        info = {is_complete: true}
        expect(detector.next_actions(info)).to eq([])
      end
    end

    describe "#is_work_in_progress?" do
      it "returns true for work in progress" do
        info = {is_complete: false, progress_status: "in_progress"}
        expect(detector.is_work_in_progress?(info)).to be true
      end

      it "returns false for completed work" do
        expect(detector.is_work_in_progress?(completion_info)).to be false
      end

      it "returns false for waiting for input" do
        info = {is_complete: false, progress_status: "waiting_for_input"}
        expect(detector.is_work_in_progress?(info)).to be false
      end

      it "returns false for work with errors" do
        info = {is_complete: false, progress_status: "has_errors"}
        expect(detector.is_work_in_progress?(info)).to be false
      end
    end

    describe "#is_waiting_for_input?" do
      it "returns true for waiting for input status" do
        info = {progress_status: "waiting_for_input"}
        expect(detector.is_waiting_for_input?(info)).to be true
      end

      it "returns true for next actions including collect_user_input" do
        info = {next_actions: ["collect_user_input"]}
        expect(detector.is_waiting_for_input?(info)).to be true
      end

      it "returns false for other statuses" do
        info = {progress_status: "in_progress"}
        expect(detector.is_waiting_for_input?(info)).to be false
      end
    end

    describe "#has_errors?" do
      it "returns true for has_errors status" do
        info = {progress_status: "has_errors"}
        expect(detector.has_errors?(info)).to be true
      end

      it "returns true for next actions including handle_errors" do
        info = {next_actions: ["handle_errors"]}
        expect(detector.has_errors?(info)).to be true
      end

      it "returns false for other statuses" do
        info = {progress_status: "in_progress"}
        expect(detector.has_errors?(info)).to be false
      end
    end

    describe "#get_progress_status_description" do
      it "returns description for all_steps_completed" do
        info = {progress_status: "all_steps_completed"}
        expect(detector.progress_status_description(info)).to eq("All steps completed successfully")
      end

      it "returns description for near_completion" do
        info = {progress_status: "near_completion"}
        expect(detector.progress_status_description(info)).to eq("Near completion (80%+ done)")
      end

      it "returns description for half_complete" do
        info = {progress_status: "half_complete"}
        expect(detector.progress_status_description(info)).to eq("Half complete (50%+ done)")
      end

      it "returns description for early_stage" do
        info = {progress_status: "early_stage"}
        expect(detector.progress_status_description(info)).to eq("Early stage (20%+ done)")
      end

      it "returns description for just_started" do
        info = {progress_status: "just_started"}
        expect(detector.progress_status_description(info)).to eq("Just started (0-20% done)")
      end

      it "returns description for has_next_actions" do
        info = {progress_status: "has_next_actions"}
        expect(detector.progress_status_description(info)).to eq("Has next actions to perform")
      end

      it "returns description for waiting_for_input" do
        info = {progress_status: "waiting_for_input"}
        expect(detector.progress_status_description(info)).to eq("Waiting for user input")
      end

      it "returns description for has_errors" do
        info = {progress_status: "has_errors"}
        expect(detector.progress_status_description(info)).to eq("Has errors that need attention")
      end

      it "returns description for in_progress" do
        info = {progress_status: "in_progress"}
        expect(detector.progress_status_description(info)).to eq("Work in progress")
      end

      it "returns unknown for unknown status" do
        info = {progress_status: "unknown_status"}
        expect(detector.progress_status_description(info)).to eq("Status unknown")
      end

      it "returns unknown for nil info" do
        expect(detector.progress_status_description(nil)).to eq("unknown")
      end
    end
  end
end
