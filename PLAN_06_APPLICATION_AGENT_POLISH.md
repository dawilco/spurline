# Plan 06: ApplicationAgent Pattern Polish

> Milestone 1.6 | Independent of M1.1 (Secret Management)

## Context

Generators exist and produce working code. Generated projects pass `spur check`. But the developer experience has gaps: no README, no `.env.example`, agent generator doesn't create specs, and templates lack educational comments.

## Critical Files

| File | Role |
|------|------|
| `lib/spurline/cli/generators/project.rb` | `spur new` scaffold |
| `lib/spurline/cli/generators/agent.rb` | `spur generate agent` |
| `lib/spurline/cli/generators/tool.rb` | `spur generate tool` (already creates specs) |
| `lib/spurline/cli/checks/project_structure.rb` | `spur check` validation |
| `spec/spurline/cli/generators/project_spec.rb` | Scaffold tests |
| `spec/spurline/cli/generators/agent_spec.rb` | Agent generator tests |

## Steps

### Step 1: Improve ApplicationAgent Template

**File:** `lib/spurline/cli/generators/project.rb` — `create_application_agent!`

```ruby
def create_application_agent!
  write_file("app/agents/application_agent.rb", <<~RUBY)
    # frozen_string_literal: true

    require "spurline"

    # The shared base class for all agents in this project.
    # Configure defaults here -- individual agents inherit and override.
    class ApplicationAgent < Spurline::Agent
      use_model :claude_sonnet

      guardrails do
        max_tool_calls 10
        injection_filter :strict
        pii_filter :off
      end

      # Uncomment to add a default persona with date injection:
      # persona(:default) do
      #   system_prompt "You are a helpful assistant."
      #   inject_date true
      # end

      # Uncomment to add lifecycle hooks:
      # on_start  { |session| puts "Session \#{session.id} started" }
      # on_finish { |session| puts "Session \#{session.id} finished" }
      # on_error  { |error| $stderr.puts "Error: \#{error.message}" }

      # Uncomment for memory window customization:
      # memory :short_term, window: 20
    end
  RUBY
end
```

### Step 2: Improve AssistantAgent Template

```ruby
def create_example_agent!
  write_file("app/agents/assistant_agent.rb", <<~RUBY)
    # frozen_string_literal: true

    require_relative "application_agent"

    class AssistantAgent < ApplicationAgent
      persona(:default) do
        system_prompt "You are a helpful assistant for the #{classify(name)} project."
        inject_date true
      end

      # Uncomment to register tools:
      # tools :example_tool

      # Uncomment to override guardrails from ApplicationAgent:
      # guardrails do
      #   max_tool_calls 5
      # end
    end
  RUBY
end
```

### Step 3: Add `.env.example` to Scaffold

```ruby
def create_env_example!
  write_file(".env.example", <<~TEXT)
    # Spurline environment variables.
    # Copy this file to .env and fill in your values.
    # Never commit .env to version control.

    ANTHROPIC_API_KEY=your_key_here

    # Uncomment for encrypted credentials support:
    # SPURLINE_MASTER_KEY=your_32_byte_hex_key
  TEXT
end
```

### Step 4: Add README.md to Scaffold

```ruby
def create_readme!
  write_file("README.md", <<~MARKDOWN)
    # #{classify(name)}

    A [Spurline](https://github.com/dylanwilcox/spurline) agent project.

    ## Setup

    ```bash
    bundle install
    cp .env.example .env
    # Edit .env with your ANTHROPIC_API_KEY
    ```

    ## Validate

    ```bash
    bundle exec spur check
    ```

    ## Run Tests

    ```bash
    bundle exec rspec
    ```

    ## Project Structure

    ```
    app/
      agents/           # Agent classes (inherit from ApplicationAgent)
      tools/            # Tool classes (inherit from Spurline::Tools::Base)
    config/
      spurline.rb       # Framework configuration
      permissions.yml   # Tool permission rules
    spec/               # RSpec test files
    ```

    ## Generators

    ```bash
    spur generate agent researcher    # Creates app/agents/researcher_agent.rb
    spur generate tool web_scraper    # Creates app/tools/web_scraper.rb + spec
    ```
  MARKDOWN
end
```

### Step 5: Add Example Agent Spec to Scaffold

```ruby
def create_example_agent_spec!
  write_file("spec/agents/assistant_agent_spec.rb", <<~RUBY)
    # frozen_string_literal: true

    RSpec.describe AssistantAgent do
      let(:agent) do
        described_class.new.tap do |a|
          a.use_stub_adapter(responses: [stub_text("Hello!")])
        end
      end

      describe "#run" do
        it "streams a response" do
          chunks = []
          agent.run("Say hello") { |chunk| chunks << chunk }

          text = chunks.select(&:text?).map(&:text).join
          expect(text).to eq("Hello!")
        end
      end
    end
  RUBY
end
```

### Step 6: Improve `config/spurline.rb` Initializer

```ruby
def create_initializer!
  write_file("config/spurline.rb", <<~RUBY)
    # frozen_string_literal: true

    require "spurline"

    Spurline.configure do |config|
      config.default_model = :claude_sonnet
      config.session_store = :memory
      config.permissions_file = "config/permissions.yml"

      # Durable sessions (survives process restart):
      # config.session_store = :sqlite
      # config.session_store_path = "tmp/spurline_sessions.db"

      # PostgreSQL sessions (for team deployments):
      # config.session_store = :postgres
      # config.session_store_postgres_url = "postgresql://localhost/my_app_development"
    end
  RUBY
end
```

### Step 7: Update `generate!` Method

Call new methods in the right order:

```ruby
def generate!
  # ... existing checks ...
  create_directories!
  create_gemfile!
  create_rakefile!
  create_initializer!
  create_application_agent!
  create_example_agent!
  create_spec_helper!
  create_example_agent_spec!    # NEW
  create_permissions!
  create_gitignore!
  create_ruby_version!
  create_env_example!           # NEW
  create_readme!                # NEW
  # ... existing output ...
end
```

### Step 8: Add Spec Generation to `spur generate agent`

**File:** `lib/spurline/cli/generators/agent.rb`

```ruby
def generate!
  verify_project_structure!
  generate_agent_file!
  generate_spec_file!
end

private

def verify_project_structure!
  unless Dir.exist?("app/agents")
    $stderr.puts "No app/agents directory found. " \
      "Run this from a Spurline project root, or run 'spur new' first."
    exit 1
  end
  unless File.exist?(File.join("app", "agents", "application_agent.rb"))
    $stderr.puts "No application_agent.rb found. Run 'spur new' first."
    exit 1
  end
end

def generate_spec_file!
  spec_path = File.join("spec", "agents", "#{snake_name}_agent_spec.rb")
  if File.exist?(spec_path)
    $stderr.puts "  skip    #{spec_path} (already exists)"
    return
  end
  FileUtils.mkdir_p(File.dirname(spec_path))
  File.write(spec_path, spec_template)
  puts "  create  #{spec_path}"
end

def spec_template
  <<~RUBY
    # frozen_string_literal: true

    RSpec.describe #{class_name}Agent do
      let(:agent) do
        described_class.new.tap do |a|
          a.use_stub_adapter(responses: [stub_text("Test response")])
        end
      end

      describe "#run" do
        it "streams a response" do
          chunks = []
          agent.run("Test input") { |chunk| chunks << chunk }
          text = chunks.select(&:text?).map(&:text).join
          expect(text).not_to be_empty
        end
      end
    end
  RUBY
end
```

### Step 9: Improve `spur check` Error Messages

**File:** `lib/spurline/cli/checks/project_structure.rb`

Add recommended file warnings:

```ruby
RECOMMENDED_FILES = %w[config/spurline.rb config/permissions.yml .env.example].freeze

# In run method, after required checks:
RECOMMENDED_FILES.each do |file|
  path = File.join(project_root, file)
  unless File.file?(path)
    results << warn(:"missing_#{file.tr("/.", "_")}",
      message: "Recommended file missing: #{file}")
  end
end
```

Add actionable error message for missing required paths:

```ruby
results << fail(:project_structure,
  message: "Missing required paths: #{missing.join(", ")}. " \
    "Run 'spur new <project>' to create a project scaffold.")
```

### Step 10: Update Gemfile Template

```ruby
def create_gemfile!
  write_file("Gemfile", <<~RUBY)
    # frozen_string_literal: true

    source "https://rubygems.org"

    gem "spurline-core"

    # Uncomment to add bundled spurs:
    # gem "spurline-web-search"

    group :development, :test do
      gem "rspec"
      # gem "webmock"   # Useful for testing tools that make HTTP calls
    end
  RUBY
end
```

### Step 11: Update Tests

**File:** `spec/spurline/cli/generators/project_spec.rb`

```ruby
it "creates .env.example" do
  generate!
  content = File.read(File.join(project_path, ".env.example"))
  expect(content).to include("ANTHROPIC_API_KEY")
end

it "creates README.md" do
  generate!
  content = File.read(File.join(project_path, "README.md"))
  expect(content).to include("Spurline")
  expect(content).to include("spur check")
end

it "creates example agent spec" do
  generate!
  path = File.join(project_path, "spec", "agents", "assistant_agent_spec.rb")
  expect(File.exist?(path)).to be true
  content = File.read(path)
  expect(content).to include("RSpec.describe AssistantAgent")
end

it "includes Postgres option in initializer comments" do
  generate!
  content = File.read(File.join(project_path, "config", "spurline.rb"))
  expect(content).to include("postgres")
end
```

**File:** `spec/spurline/cli/generators/agent_spec.rb`

```ruby
it "generates a spec alongside the agent" do
  Dir.chdir(tmpdir) do
    FileUtils.mkdir_p("app/agents")
    File.write("app/agents/application_agent.rb", "# stub")
    described_class.new(name: "research").generate!
  end

  spec_path = File.join(tmpdir, "spec", "agents", "research_agent_spec.rb")
  expect(File.exist?(spec_path)).to be true
end

it "exits with error outside a Spurline project" do
  Dir.chdir(tmpdir) do
    expect {
      described_class.new(name: "research").generate!
    }.to raise_error(SystemExit)
  end
end

it "skips spec if it already exists" do
  Dir.chdir(tmpdir) do
    FileUtils.mkdir_p("app/agents")
    File.write("app/agents/application_agent.rb", "# stub")
    FileUtils.mkdir_p("spec/agents")
    File.write("spec/agents/research_agent_spec.rb", "# existing")
    expect {
      described_class.new(name: "research").generate!
    }.to output(/skip/).to_stdout
  end
end
```

## Dependency on Plan 5

The `AssistantAgent` template uses `inject_date true`. If Plan 5 is not yet implemented, this DSL call is accepted (PersonaConfig already has the method) but has no effect at runtime. When Plan 5 lands, it starts working automatically. Forward-compatible.

## Verification

```bash
# Generator tests
bundle exec rspec spec/spurline/cli/generators/

# Functional test: generate a project and verify it works
cd /tmp && spur new test_project && cd test_project && bundle install && bundle exec spur check && bundle exec rspec

# Full suite
bundle exec rspec
```
