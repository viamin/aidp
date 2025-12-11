# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/security_command"
require "aidp/security"

RSpec.describe Aidp::CLI::SecurityCommand do
  let(:project_dir) { Dir.mktmpdir("security_command_spec") }
  let(:mock_prompt) { instance_double(TTY::Prompt) }

  subject(:command) do
    described_class.new(project_dir: project_dir, prompt: mock_prompt)
  end

  before do
    allow(mock_prompt).to receive(:say)
    allow(mock_prompt).to receive(:ok)
    allow(mock_prompt).to receive(:warn)
    allow(mock_prompt).to receive(:error)
    # Reset security state
    Aidp::Security.reset!
  end

  after do
    FileUtils.rm_rf(project_dir) if project_dir && Dir.exist?(project_dir)
    Aidp::Security.reset!
  end

  describe "#run" do
    context "with status subcommand" do
      it "runs status and returns 0" do
        expect(command).to receive(:run_status).and_return(0)
        expect(command.run(["status"])).to eq(0)
      end
    end

    context "with register subcommand" do
      it "returns error when no secret name provided" do
        expect(mock_prompt).to receive(:error).with("Error: secret name required")
        expect(command.run(["register"])).to eq(1)
      end

      it "runs register with secret name" do
        expect(command).to receive(:run_register).with("my_secret", "my_secret").and_return(0)
        expect(command.run(["register", "my_secret"])).to eq(0)
      end

      it "parses --env-var option" do
        expect(command).to receive(:run_register).with("my_secret", "ENV_VAR").and_return(0)
        expect(command.run(["register", "my_secret", "--env-var", "ENV_VAR"])).to eq(0)
      end

      it "accepts register-secret alias" do
        expect(command).to receive(:run_register).with("my_secret", "my_secret").and_return(0)
        expect(command.run(["register-secret", "my_secret"])).to eq(0)
      end
    end

    context "with unregister subcommand" do
      it "returns error when no secret name provided" do
        expect(mock_prompt).to receive(:error).with("Error: secret name required")
        expect(command.run(["unregister"])).to eq(1)
      end

      it "runs unregister with secret name" do
        expect(command).to receive(:run_unregister).with("my_secret").and_return(0)
        expect(command.run(["unregister", "my_secret"])).to eq(0)
      end
    end

    context "with list subcommand" do
      it "runs list" do
        expect(command).to receive(:run_list).and_return(0)
        expect(command.run(["list"])).to eq(0)
      end

      it "accepts secrets alias" do
        expect(command).to receive(:run_list).and_return(0)
        expect(command.run(["secrets"])).to eq(0)
      end
    end

    context "with audit subcommand" do
      it "runs audit" do
        expect(command).to receive(:run_audit).with([]).and_return(0)
        expect(command.run(["audit"])).to eq(0)
      end
    end

    context "with proxy-status subcommand" do
      it "runs proxy-status" do
        expect(command).to receive(:run_proxy_status).and_return(0)
        expect(command.run(["proxy-status"])).to eq(0)
      end
    end

    context "with help" do
      it "shows help for nil subcommand" do
        expect(command).to receive(:show_help)
        expect(command.run([])).to eq(0)
      end

      it "shows help for 'help' subcommand" do
        expect(command).to receive(:show_help)
        expect(command.run(["help"])).to eq(0)
      end

      it "shows help for '--help' flag" do
        expect(command).to receive(:show_help)
        expect(command.run(["--help"])).to eq(0)
      end

      it "shows help for '-h' flag" do
        expect(command).to receive(:show_help)
        expect(command.run(["-h"])).to eq(0)
      end
    end

    context "with unknown subcommand" do
      it "returns error" do
        expect(mock_prompt).to receive(:error).with("Unknown subcommand: foobar")
        expect(command.run(["foobar"])).to eq(1)
      end
    end
  end

  describe "#show_help" do
    it "displays help text" do
      expect(mock_prompt).to receive(:say).at_least(:once)
      command.show_help
    end
  end

  describe "#run_status" do
    it "displays security status" do
      expect(mock_prompt).to receive(:say).at_least(:once)
      result = command.run_status
      expect(result).to eq(0)
    end
  end

  describe "#run_list" do
    context "when no secrets registered" do
      before do
        # Ensure registry is empty by using a fresh registry
        registry = Aidp::Security.secrets_registry
        registry.list.each do |secret|
          registry.unregister(name: secret[:name])
        end
      end

      it "shows no secrets message" do
        expect(mock_prompt).to receive(:say).with("\nNo secrets registered")
        expect(command.run_list).to eq(0)
      end
    end

    context "when secrets are registered" do
      before do
        registry = Aidp::Security.secrets_registry
        registry.register(name: "test_secret", env_var: "TEST_SECRET")
      end

      it "displays secrets table" do
        expect(mock_prompt).to receive(:say).at_least(:once)
        expect(command.run_list).to eq(0)
      end
    end
  end

  describe "#run_register" do
    # Clean up any existing registrations before each test
    before do
      registry = Aidp::Security.secrets_registry
      %w[existing new_secret fail_secret].each do |name|
        registry.unregister(name: name) if registry.registered?(name)
      end
    end

    context "when secret is already registered" do
      before do
        registry = Aidp::Security.secrets_registry
        registry.register(name: "existing", env_var: "EXISTING_VAR")
      end

      it "returns error" do
        expect(mock_prompt).to receive(:warn).with("Secret 'existing' is already registered")
        expect(command.run_register("existing", "EXISTING_VAR")).to eq(1)
      end
    end

    context "when env var does not exist" do
      before do
        allow(ENV).to receive(:key?).and_call_original
        allow(ENV).to receive(:key?).with("MISSING_VAR").and_return(false)
        allow(mock_prompt).to receive(:yes?).and_return(false)
      end

      it "warns and asks to continue" do
        expect(mock_prompt).to receive(:warn).with("Warning: Environment variable 'MISSING_VAR' is not currently set")
        expect(mock_prompt).to receive(:yes?).with("Continue anyway?").and_return(false)
        expect(command.run_register("new_secret", "MISSING_VAR")).to eq(1)
      end
    end

    context "when registration succeeds" do
      before do
        allow(ENV).to receive(:key?).and_call_original
        allow(ENV).to receive(:key?).with("NEW_SECRET").and_return(true)
        allow(mock_prompt).to receive(:ask).and_return(nil)
      end

      it "registers the secret" do
        expect(mock_prompt).to receive(:ok).with("Secret 'new_secret' registered successfully")
        expect(command.run_register("new_secret", "NEW_SECRET")).to eq(0)
      end
    end

    context "when registration fails" do
      before do
        allow(ENV).to receive(:key?).and_call_original
        allow(ENV).to receive(:key?).with("FAIL_VAR").and_return(true)
        allow(mock_prompt).to receive(:ask).and_return(nil)
        registry = Aidp::Security.secrets_registry
        allow(registry).to receive(:register).and_raise(StandardError, "Database error")
      end

      it "returns error" do
        expect(mock_prompt).to receive(:error).with("Failed to register secret: Database error")
        expect(command.run_register("fail_secret", "FAIL_VAR")).to eq(1)
      end
    end
  end

  describe "#run_unregister" do
    context "when secret is not registered" do
      it "returns error" do
        expect(mock_prompt).to receive(:error).with("Secret 'unknown' is not registered")
        expect(command.run_unregister("unknown")).to eq(1)
      end
    end

    context "when user cancels" do
      before do
        registry = Aidp::Security.secrets_registry
        registry.register(name: "to_remove", env_var: "TO_REMOVE")
        allow(mock_prompt).to receive(:yes?).and_return(false)
      end

      it "cancels unregistration" do
        expect(mock_prompt).to receive(:say).with("Cancelled")
        expect(command.run_unregister("to_remove")).to eq(0)
      end
    end

    context "when user confirms" do
      before do
        registry = Aidp::Security.secrets_registry
        registry.register(name: "to_remove", env_var: "TO_REMOVE")
        allow(mock_prompt).to receive(:yes?).and_return(true)
      end

      it "unregisters the secret" do
        expect(mock_prompt).to receive(:ok).with("Secret 'to_remove' unregistered")
        expect(command.run_unregister("to_remove")).to eq(0)
      end
    end
  end

  describe "#run_proxy_status" do
    it "displays proxy status" do
      expect(mock_prompt).to receive(:say).at_least(:once)
      expect(command.run_proxy_status).to eq(0)
    end

    context "with active tokens" do
      before do
        registry = Aidp::Security.secrets_registry
        registry.register(name: "active_secret", env_var: "ACTIVE_SECRET")
        proxy = Aidp::Security.secrets_proxy
        proxy.request_token(secret_name: "active_secret")
      end

      it "displays active tokens table" do
        expect(mock_prompt).to receive(:say).at_least(:once)
        expect(command.run_proxy_status).to eq(0)
      end
    end
  end

  describe "#run_audit" do
    let(:rspec_path) { File.join(project_dir, "spec", "aidp", "security") }

    context "when spec directory does not exist" do
      it "creates the directory" do
        expect(mock_prompt).to receive(:warn)
        expect(mock_prompt).to receive(:ok)
        command.run_audit([])
        expect(Dir.exist?(rspec_path)).to be true
      end
    end

    context "when no spec files exist" do
      before do
        FileUtils.mkdir_p(rspec_path)
      end

      it "warns about missing specs" do
        expect(mock_prompt).to receive(:warn).with("No security spec files found")
        expect(command.run_audit([])).to eq(0)
      end
    end
  end
end
