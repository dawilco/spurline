# frozen_string_literal: true

require "tempfile"

RSpec.describe Spurline::DSL::Tools do
  let(:tool_registry) { Spurline::Agent.tool_registry }

  around do |example|
    original_tools = tool_registry.all
    original_spurs = Spurline::Spur.registry.dup
    original_permissions_file = Spurline.config.permissions_file
    original_brave_api_key = Spurline.config.brave_api_key

    example.run
  ensure
    tool_registry.clear!
    original_tools.each { |name, klass| tool_registry.register(name, klass) }

    Spurline::Spur.registry.clear
    original_spurs.each { |name, info| Spurline::Spur.registry[name] = info }

    Spurline.configure do |config|
      config.permissions_file = original_permissions_file
      config.brave_api_key = original_brave_api_key
    end
  end

  describe ".permissions_config" do
    it "merges spur defaults, inline config, then YAML overrides" do
      temp_permissions = Tempfile.new(["permissions", ".yml"])
      temp_permissions.write(<<~YAML)
        tools:
          web_search:
            requires_confirmation: false
            denied: true
      YAML
      temp_permissions.close

      Spurline.configure do |config|
        config.permissions_file = temp_permissions.path
      end

      web_search_tool = Class.new(Spurline::Tools::Base) do
        tool_name :web_search

        def call(**)
          "ok"
        end
      end

      spur_class = Class.new(Spurline::Spur) do
        spur_name "test-web-search-spur"

        tools do
          register :web_search, web_search_tool
        end

        permissions do
          default_trust :external
          requires_confirmation true
          sandbox false
        end
      end
      spur_class.send(:auto_register!)

      agent_class = Class.new(Spurline::Agent) do
        tools web_search: { requires_confirmation: true, sandbox: true }
      end

      permissions = agent_class.permissions_config
      expect(permissions[:web_search]).to include(
        default_trust: :external,
        sandbox: true,
        requires_confirmation: false,
        denied: true
      )
    ensure
      temp_permissions&.unlink
    end

    it "returns inline + spur defaults when permissions file does not exist" do
      Spurline.configure do |config|
        config.permissions_file = "/tmp/does-not-exist.yml"
      end

      report_tool = Class.new(Spurline::Tools::Base) do
        tool_name :report

        def call(**)
          "ok"
        end
      end

      spur_class = Class.new(Spurline::Spur) do
        spur_name "test-report-spur"

        tools do
          register :report, report_tool
        end

        permissions do
          requires_confirmation true
        end
      end
      spur_class.send(:auto_register!)

      agent_class = Class.new(Spurline::Agent) do
        tools report: { denied: false }
      end

      expect(agent_class.permissions_config[:report]).to include(
        requires_confirmation: true,
        denied: false
      )
    end
  end
end
