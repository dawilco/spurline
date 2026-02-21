# frozen_string_literal: true

RSpec.describe Spurline::Tools::Runner do
  let(:registry) { Spurline::Tools::Registry.new }
  let(:secret_resolver) { nil }
  let(:runner) do
    described_class.new(
      registry: registry,
      permissions: permissions,
      secret_resolver: secret_resolver
    )
  end
  let(:permissions) { {} }
  let(:store) { Spurline::Session::Store::Memory.new }
  let(:session) { Spurline::Session::Session.load_or_create(store: store) }

  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      def call(message:)
        "Echo: #{message}"
      end
    end
  end

  before do
    registry.register(:echo, echo_tool)
    session.start_turn(input: "test")
  end

  describe "#execute" do
    it "executes the tool and returns a Content object" do
      tool_call = { name: :echo, arguments: { message: "hello" } }
      result = runner.execute(tool_call, session: session)

      expect(result).to be_a(Spurline::Security::Content)
      expect(result.trust).to eq(:external)
      expect(result.text).to include("Echo: hello")
    end

    it "records the tool call on the session turn" do
      tool_call = { name: :echo, arguments: { message: "test" } }
      runner.execute(tool_call, session: session)

      expect(session.current_turn.tool_call_count).to eq(1)
      expect(session.current_turn.tool_calls.first[:name]).to eq("echo")
    end

    it "records redacted arguments on the session turn" do
      sensitive_tool = Class.new(Spurline::Tools::Base) do
        tool_name :sensitive
        parameters(
          type: "object",
          properties: {
            api_key: { type: "string", sensitive: true },
            message: { type: "string" },
          },
          required: %w[api_key message]
        )

        def call(api_key:, message:)
          "#{api_key}:#{message}"
        end
      end
      registry.register(:sensitive, sensitive_tool)

      tool_call = { name: :sensitive, arguments: { api_key: "secret-value", message: "hello" } }
      runner.execute(tool_call, session: session)
      recorded = session.current_turn.tool_calls.first[:arguments]

      expect(recorded).to eq(api_key: "[REDACTED:api_key]", message: "hello")
    end

    it "raises ToolNotFoundError for unknown tools" do
      tool_call = { name: :nonexistent, arguments: {} }
      expect {
        runner.execute(tool_call, session: session)
      }.to raise_error(Spurline::ToolNotFoundError)
    end

    it "wraps the result through the ToolResult gate" do
      tool_call = { name: :echo, arguments: { message: "test" } }
      result = runner.execute(tool_call, session: session)

      expect(result).to be_tainted
      expect(result.source).to eq("tool:echo")
    end

    it "handles string keys in arguments" do
      tool_call = { name: :echo, arguments: { "message" => "hello" } }
      result = runner.execute(tool_call, session: session)
      expect(result.text).to include("Echo: hello")
    end

    it "handles nil arguments" do
      no_args_tool = Class.new(Spurline::Tools::Base) do
        tool_name :no_args
        def call
          "no args"
        end
      end
      registry.register(:no_args, no_args_tool)

      tool_call = { name: :no_args, arguments: nil }
      result = runner.execute(tool_call, session: session)
      expect(result.text).to include("no args")
    end

    it "raises ConfigurationError for missing required parameters" do
      required_tool = Class.new(Spurline::Tools::Base) do
        tool_name :required
        parameters({
          type: "object",
          properties: { query: { type: "string" } },
          required: %w[query],
        })

        def call(query:)
          "query=#{query}"
        end
      end
      registry.register(:required, required_tool)

      expect {
        runner.execute({ name: :required, arguments: {} }, session: session)
      }.to raise_error(
        Spurline::ConfigurationError,
        /Invalid tool call for 'required'.*missing required parameter 'query'/m
      )
    end

    it "serializes structured results as JSON for tool feedback" do
      structured_tool = Class.new(Spurline::Tools::Base) do
        tool_name :structured
        def call(query:)
          [{ title: "Result", url: "https://example.com", snippet: query }]
        end
      end
      registry.register(:structured, structured_tool)

      tool_call = { name: :structured, arguments: { query: "spurline" } }
      result = runner.execute(tool_call, session: session)

      expect(result.text).to include("\"title\":\"Result\"")
      expect(result.text).to include("\"snippet\":\"spurline\"")
    end

    it "injects declared secrets into tool call arguments" do
      secure_tool = Class.new(Spurline::Tools::Base) do
        tool_name :secure
        secret :api_key, description: "Injected API key"

        def call(to:, api_key:)
          "sent #{to} with #{api_key}"
        end
      end
      registry.register(:secure, secure_tool)

      resolver = instance_double(Spurline::Secrets::Resolver)
      allow(resolver).to receive(:resolve!).with(:api_key).and_return("injected-secret")

      secure_runner = described_class.new(
        registry: registry,
        permissions: permissions,
        secret_resolver: resolver
      )

      result = secure_runner.execute({ name: :secure, arguments: { to: "user@example.com" } }, session: session)

      expect(result.text).to include("injected-secret")
    end

    it "does not overwrite llm-provided secret arguments" do
      secure_tool = Class.new(Spurline::Tools::Base) do
        tool_name :secure_passthrough
        secret :api_key, description: "Injected API key"

        def call(to:, api_key:)
          "sent #{to} with #{api_key}"
        end
      end
      registry.register(:secure_passthrough, secure_tool)

      resolver = instance_double(Spurline::Secrets::Resolver)
      expect(resolver).not_to receive(:resolve!)

      secure_runner = described_class.new(
        registry: registry,
        permissions: permissions,
        secret_resolver: resolver
      )

      result = secure_runner.execute(
        { name: :secure_passthrough, arguments: { to: "user@example.com", api_key: "llm-value" } },
        session: session
      )

      expect(result.text).to include("llm-value")
    end

    it "raises SecretNotFoundError when a declared secret cannot be resolved" do
      secure_tool = Class.new(Spurline::Tools::Base) do
        tool_name :secure_missing
        secret :api_key, description: "Injected API key"

        def call(to:, api_key:)
          "sent #{to} with #{api_key}"
        end
      end
      registry.register(:secure_missing, secure_tool)

      resolver = instance_double(Spurline::Secrets::Resolver)
      allow(resolver).to receive(:resolve!).with(:api_key).and_raise(
        Spurline::SecretNotFoundError,
        "missing"
      )

      secure_runner = described_class.new(
        registry: registry,
        permissions: permissions,
        secret_resolver: resolver
      )

      expect {
        secure_runner.execute({ name: :secure_missing, arguments: { to: "user@example.com" } }, session: session)
      }.to raise_error(Spurline::SecretNotFoundError, /missing/)
    end

    it "does not change tools without declared secrets when resolver is configured" do
      resolver = instance_double(Spurline::Secrets::Resolver)
      expect(resolver).not_to receive(:resolve!)

      secure_runner = described_class.new(
        registry: registry,
        permissions: permissions,
        secret_resolver: resolver
      )

      result = secure_runner.execute({ name: :echo, arguments: { message: "hello" } }, session: session)
      expect(result.text).to include("Echo: hello")
    end

    it "records injected secrets as redacted values on the session turn" do
      secure_tool = Class.new(Spurline::Tools::Base) do
        tool_name :secure_redaction
        secret :api_key, description: "Injected API key"

        def call(to:, api_key:)
          "sent #{to} with #{api_key.length}"
        end
      end
      registry.register(:secure_redaction, secure_tool)

      resolver = instance_double(Spurline::Secrets::Resolver)
      allow(resolver).to receive(:resolve!).with(:api_key).and_return("secret-injected-value")

      secure_runner = described_class.new(
        registry: registry,
        permissions: permissions,
        secret_resolver: resolver
      )

      secure_runner.execute({ name: :secure_redaction, arguments: { to: "user@example.com" } }, session: session)

      recorded = session.current_turn.tool_calls.first[:arguments]
      expect(recorded).to include(
        to: "user@example.com",
        api_key: "[REDACTED:api_key]"
      )
      expect(recorded.inspect).not_to include("secret-injected-value")
    end
  end

  describe "permissions" do
    context "when tool is denied" do
      let(:permissions) { { echo: { denied: true } } }

      it "raises PermissionDeniedError" do
        tool_call = { name: :echo, arguments: { message: "test" } }
        expect {
          runner.execute(tool_call, session: session)
        }.to raise_error(Spurline::PermissionDeniedError, /denied/)
      end
    end

    context "when tool has user restrictions" do
      let(:permissions) { { echo: { allowed_users: %w[admin] } } }

      it "raises PermissionDeniedError for unauthorized user" do
        session_with_user = Spurline::Session::Session.load_or_create(
          store: store, user: "regular_user"
        )
        session_with_user.start_turn(input: "test")

        tool_call = { name: :echo, arguments: { message: "test" } }
        expect {
          runner.execute(tool_call, session: session_with_user)
        }.to raise_error(Spurline::PermissionDeniedError, /not permitted/)
      end

      it "allows authorized user" do
        session_with_user = Spurline::Session::Session.load_or_create(
          store: store, user: "admin"
        )
        session_with_user.start_turn(input: "test")

        tool_call = { name: :echo, arguments: { message: "test" } }
        result = runner.execute(tool_call, session: session_with_user)
        expect(result.text).to include("Echo: test")
      end
    end

    context "with no permissions configured" do
      let(:permissions) { {} }

      it "allows all tools" do
        tool_call = { name: :echo, arguments: { message: "test" } }
        result = runner.execute(tool_call, session: session)
        expect(result.text).to include("Echo: test")
      end
    end
  end

  describe "confirmation" do
    let(:confirm_tool) do
      Class.new(Spurline::Tools::Base) do
        tool_name :confirm_me
        requires_confirmation true

        def call(action:)
          "Performed: #{action}"
        end
      end
    end

    before { registry.register(:confirm_me, confirm_tool) }

    it "calls confirmation handler when tool requires confirmation" do
      confirmed = false
      tool_call = { name: :confirm_me, arguments: { action: "delete" } }

      runner.execute(tool_call, session: session) do |tool_name:, arguments:|
        confirmed = true
        true # approve
      end

      expect(confirmed).to be true
    end

    it "raises PermissionDeniedError when confirmation is denied" do
      tool_call = { name: :confirm_me, arguments: { action: "delete" } }

      expect {
        runner.execute(tool_call, session: session) do |tool_name:, arguments:|
          false # deny
        end
      }.to raise_error(Spurline::PermissionDeniedError, /confirmation was denied/)
    end

    it "skips confirmation when no handler is provided" do
      tool_call = { name: :confirm_me, arguments: { action: "delete" } }
      # No block — should execute without confirmation
      result = runner.execute(tool_call, session: session)
      expect(result.text).to include("Performed: delete")
    end

    context "with requires_confirmation in permissions config" do
      let(:permissions) { { echo: { requires_confirmation: true } } }

      it "checks confirmation based on permissions config" do
        tool_call = { name: :echo, arguments: { message: "test" } }

        expect {
          runner.execute(tool_call, session: session) do |tool_name:, arguments:|
            false # deny
          end
        }.to raise_error(Spurline::PermissionDeniedError)
      end
    end
  end
end

RSpec.describe Spurline::Tools::Base do
  describe ".validate_arguments!" do
    let(:tool_class) do
      Class.new(described_class) do
        tool_name :test_tool
        parameters({
          type: "object",
          properties: {
            name: { type: "string" },
            age: { type: "integer" },
          },
          required: %w[name],
        })
      end
    end

    it "passes when required arguments are present" do
      expect(tool_class.validate_arguments!(name: "Alice")).to be true
    end

    it "raises ConfigurationError when required argument is missing" do
      expect {
        tool_class.validate_arguments!(age: 25)
      }.to raise_error(Spurline::ConfigurationError, /missing required parameter 'name'/)
    end

    it "passes when schema is empty" do
      empty_tool = Class.new(described_class) do
        tool_name :empty
      end
      expect(empty_tool.validate_arguments!(anything: "value")).to be true
    end
  end
end
