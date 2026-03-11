# frozen_string_literal: true

RSpec.describe "DSL::Tools#toolkits" do
  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Echo tool"
      parameters({ type: "object", properties: {}, required: [] })
      def call(**); "echo"; end
    end
  end

  let(:commit_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :git_commit
      description "Commit"
      def call(**); "committed"; end
    end
  end

  let(:push_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :git_push
      description "Push"
      def call(**); "pushed"; end
    end
  end

  let(:branch_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :git_branch
      description "Branch"
      def call(**); "branched"; end
    end
  end

  let(:fetch_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :fetch_linear_ticket
      description "Fetch ticket"
      def call(**); "fetched"; end
    end
  end

  let(:post_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :post_linear_comment
      description "Post comment"
      def call(**); "posted"; end
    end
  end

  let(:read_file_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :read_file
      description "Read file"
      def call(**); "read"; end
    end
  end

  let(:git_toolkit) do
    ct = commit_tool
    pt = push_tool
    bt = branch_tool
    Class.new(Spurline::Toolkit) do
      toolkit_name :git
      tool ct
      tool pt
      tool bt
      shared_config scoped: true
    end
  end

  let(:linear_toolkit) do
    ft = fetch_tool
    pc = post_tool
    Class.new(Spurline::Toolkit) do
      toolkit_name :linear
      tool ft
      tool pc
    end
  end

  let(:agent_class) do
    gt = git_toolkit
    lt = linear_toolkit
    rft = read_file_tool

    Class.new(Spurline::Agent) do
      use_model :stub
      persona(:default) { system_prompt "Test." }
    end.tap do |klass|
      klass.toolkit_registry.register(:git, gt)
      klass.toolkit_registry.register(:linear, lt)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
      # Register read_file as a standalone tool
      klass.tool_registry.register(:read_file, rft)
    end
  end

  it "expands a single toolkit into tool names" do
    klass = Class.new(agent_class) { toolkits :git }
    expect(klass.tool_config[:names]).to include(:git_commit, :git_push, :git_branch)
  end

  it "expands multiple toolkits" do
    klass = Class.new(agent_class) { toolkits :git, :linear }
    names = klass.tool_config[:names]
    expect(names).to include(:git_commit, :git_push, :git_branch)
    expect(names).to include(:fetch_linear_ticket, :post_linear_comment)
  end

  it "applies shared_config to each tool" do
    klass = Class.new(agent_class) { toolkits :git }
    %i[git_commit git_push git_branch].each do |tool|
      expect(klass.tool_config[:configs][tool]).to include(scoped: true)
    end
  end

  it "does not apply shared_config when empty" do
    klass = Class.new(agent_class) { toolkits :linear }
    %i[fetch_linear_ticket post_linear_comment].each do |tool|
      config = klass.tool_config[:configs][tool]
      expect(config).to be_nil.or(be_empty)
    end
  end

  it "mixes toolkits with standalone tools" do
    klass = Class.new(agent_class) do
      toolkits :git
      tools :read_file
    end
    names = klass.tool_config[:names]
    expect(names).to include(:git_commit, :git_push, :git_branch, :read_file)
  end

  it "allows per-tool overrides to win over toolkit shared_config" do
    klass = Class.new(agent_class) do
      toolkits :git
      tools git_push: { requires_confirmation: true }
    end
    config = klass.tool_config[:configs][:git_push]
    expect(config).to include(scoped: true, requires_confirmation: true)
  end

  it "deduplicates tool names when toolkit and tools overlap" do
    klass = Class.new(agent_class) do
      toolkits :git
      tools :git_commit
    end
    names = klass.tool_config[:names]
    expect(names.count(:git_commit)).to eq(1)
  end

  it "raises ToolkitNotFoundError for unregistered toolkit on access" do
    klass = Class.new(agent_class) { toolkits :nonexistent }
    expect { klass.tool_config }.to raise_error(
      Spurline::ToolkitNotFoundError, /nonexistent/
    )
  end

  it "supports toolkit-level overrides" do
    klass = Class.new(agent_class) do
      toolkits :linear, linear: { requires_confirmation: true }
    end
    %i[fetch_linear_ticket post_linear_comment].each do |tool|
      expect(klass.tool_config[:configs][tool]).to include(requires_confirmation: true)
    end
  end

  it "auto-registers toolkit tool classes into the tool registry" do
    klass = Class.new(agent_class) { toolkits :git }
    # Force expansion
    klass.tool_config

    expect(klass.tool_registry.registered?(:git_commit)).to be true
    expect(klass.tool_registry.registered?(:git_push)).to be true
    expect(klass.tool_registry.registered?(:git_branch)).to be true
  end

  it "supports inline tool definitions in toolkits" do
    inline_toolkit = Class.new(Spurline::Toolkit) do
      toolkit_name :inline_test
      tool :ping do
        description "Ping"
        parameters({ type: "object", properties: {}, required: [] })
        def call(**); "pong"; end
      end
    end

    klass = Class.new(agent_class)
    klass.toolkit_registry.register(:inline_test, inline_toolkit)

    sub = Class.new(klass) { toolkits :inline_test }
    sub.tool_config # force expansion

    expect(sub.tool_registry.registered?(:ping)).to be true
    tool = sub.tool_registry.fetch(:ping)
    expect(tool.new.call).to eq("pong")
  end
end
