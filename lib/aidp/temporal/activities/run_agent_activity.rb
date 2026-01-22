# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that executes an AI agent iteration
      # Wraps the existing AIDP agent execution with Temporal durability
      class RunAgentActivity < BaseActivity

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            step_name = input[:step_name]
            iteration = input[:iteration]
            injected_instructions = input[:injected_instructions] || []
            escalate = input[:escalate] || false

            log_activity("executing_agent",
              project_dir: project_dir,
              step_name: step_name,
              iteration: iteration,
              instructions_count: injected_instructions.length,
              escalate: escalate)

            # Load configuration
            config = load_config(project_dir)
            provider_manager = create_provider_manager(project_dir, config)

            # Get prompt content
            prompt_manager = Aidp::Execute::PromptManager.new(project_dir, config: config)
            prompt_content = prompt_manager.read

            unless prompt_content
              return error_result("No PROMPT.md found")
            end

            # Inject any queued instructions
            if injected_instructions.any?
              prompt_content = inject_instructions(prompt_content, injected_instructions)
              prompt_manager.write(prompt_content)
            end

            # Select model based on escalation status
            model_selector = create_model_selector(config, escalate: escalate)
            provider, model = model_selector.select

            log_activity("agent_model_selected",
              provider: provider,
              model: model,
              escalate: escalate)

            # Periodic heartbeat during agent execution
            heartbeat_thread = start_heartbeat_thread(iteration: iteration)

            begin
              # Execute agent
              result = execute_agent(
                project_dir: project_dir,
                provider_manager: provider_manager,
                provider: provider,
                model: model,
                prompt_content: prompt_content
              )

              check_cancellation!

              if result[:success]
                success_result(
                  result: result[:output],
                  provider: provider,
                  model: model,
                  iteration: iteration
                )
              else
                error_result(result[:error] || "Agent execution failed",
                  provider: provider,
                  model: model,
                  iteration: iteration)
              end
            ensure
              heartbeat_thread&.kill
            end
          end
        end

        private

        def inject_instructions(prompt_content, instructions)
          injection_text = instructions.map { |i| i[:content] || i }.join("\n\n")

          <<~PROMPT
            #{prompt_content}

            ---
            ## Additional Instructions (Injected)

            #{injection_text}
          PROMPT
        end

        def create_model_selector(config, escalate:)
          require_relative "../../harness/thinking_depth_manager"

          manager = Aidp::Harness::ThinkingDepthManager.new(config)
          manager.escalate if escalate
          manager
        end

        def start_heartbeat_thread(iteration:)
          Thread.new do
            loop do
              sleep 30
              heartbeat(iteration: iteration, status: "running")
            end
          end
        end

        def execute_agent(project_dir:, provider_manager:, provider:, model:, prompt_content:)
          # Use the provider manager to execute
          prompt_path = File.join(project_dir, ".aidp", "PROMPT.md")

          result = provider_manager.execute_with_provider(
            provider,
            model: model,
            prompt_path: prompt_path
          )

          {success: result[:success], output: result[:output], error: result[:error]}
        rescue => e
          Aidp.log_error("run_agent_activity", "agent_execution_failed",
            error: e.message,
            error_class: e.class.name)
          {success: false, error: e.message}
        end
      end
    end
  end
end
