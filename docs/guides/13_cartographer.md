# Cartographer — Repository Analysis

Cartographer analyzes a repository and produces a structured `RepoProfile`. It reads and infers — it never executes anything. Use it to understand a project's language, framework, test runner, CI setup, entry points, and security posture before an agent starts work.

## Quick Start

```ruby
profile = Spurline.analyze_repo("/path/to/your/project")

profile.languages        # => { primary: :ruby, secondary: [:javascript] }
profile.frameworks       # => { web: :rails, version: "7.2", test: :rspec, lint: :rubocop }
profile.ci               # => { provider: :github_actions, test_command: "bundle exec rspec" }
profile.entry_points     # => { web: ["bin/rails server"], test: ["bundle exec rspec"] }
profile.secure?          # => true
profile.confidence       # => { overall: 0.92, per_layer: { ... } }
```

## RepoProfile Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | String | Profile schema version (`"1.0"`) |
| `analyzed_at` | String | ISO 8601 timestamp of analysis |
| `repo_path` | String | Absolute path analyzed |
| `languages` | Hash | `{ primary: :ruby, secondary: [:javascript] }` |
| `frameworks` | Hash | `{ web: :rails, test: :rspec, lint: :rubocop }` |
| `ruby_version` | String/nil | From `.ruby-version` or Gemfile |
| `node_version` | String/nil | From `.nvmrc` or `.node-version` |
| `ci` | Hash | `{ provider:, test_command:, lint_command:, deploy_command: }` |
| `entry_points` | Hash | `{ web: [...], test: [...], console: [...] }` |
| `environment_vars_required` | Array | Variable names from `.env.example` |
| `security_findings` | Array | `[{ type:, severity:, file:, detail: }]` |
| `confidence` | Hash | `{ overall: 0.92, per_layer: { file_signatures: 1.0, ... } }` |
| `metadata` | Hash | Analyzer errors and extra data |

RepoProfile objects are frozen on creation. Call `to_h` for a mutable copy, `to_json` for serialization, and `from_h` to reconstruct from a hash.

## The Six Analyzer Layers

Each layer runs independently. If one fails, the others continue and the failed layer's confidence drops to 0.0.

### 1. FileSignatures

Detects languages and toolchains by checking for sentinel files (`Gemfile`, `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Dockerfile`, `docker-compose.yml`, etc.).

### 2. Manifests

Parses dependency files to extract framework versions, test frameworks, and linters. Reads `Gemfile`, `Gemfile.lock`, `package.json`, `.ruby-version`, `.node-version`, and `pyproject.toml`.

### 3. CIConfig

Parses CI configuration to extract actual commands. This is the highest-signal layer — CI config shows what the project really runs. Supports GitHub Actions, CircleCI, GitLab CI, and Jenkinsfile (basic pattern matching).

### 4. Dotfiles

Reads `.rubocop.yml`, `.eslintrc`, `.prettierrc`, `.editorconfig`, `.env.example`, `.tool-versions`, and `.nvmrc`. Extracts style configuration and required environment variables.

### 5. EntryPoints

Discovers how to run the project by scanning `bin/`, `exe/`, `Procfile`, `Makefile`, `Rakefile`, and `package.json` scripts. Classifies commands into categories: web, background, console, test, lint, deploy.

### 6. SecurityScan

Pattern-based scan for hardcoded secrets (API keys, tokens, passwords), sensitive committed files (`.env`, `*.pem`, `*.key`), and suspicious dependencies. Binary files and excluded directories are skipped.

## Running Individual Analyzers

```ruby
analyzer = Spurline::Cartographer::Analyzers::CIConfig.new(repo_path: "/path/to/project")
result = analyzer.analyze     # => { ci: { provider: :github_actions, ... } }
analyzer.confidence           # => 1.0
```

## Confidence Scoring

Each analyzer reports a confidence score (0.0 to 1.0). The overall score is the mean of all layer scores. A failed analyzer contributes 0.0. Typical scores:

- 0.9+ : Strong signals found (CI config, Gemfile with clear framework)
- 0.7–0.9 : Partial signals (some files present, some missing)
- Below 0.7 : Sparse project or analysis failures

## Configuration

```ruby
Spurline.configure do |c|
  c.cartographer_exclude_patterns = %w[.git node_modules vendor tmp log coverage]
end
```

Excluded patterns apply to all analyzers. Files in excluded directories are never read.

## Security Findings

When `profile.secure?` returns `false`, check `profile.security_findings`:

```ruby
profile.security_findings.each do |finding|
  puts "#{finding[:severity]}: #{finding[:type]} in #{finding[:file]}"
  puts "  #{finding[:detail]}"
end
```

Finding types include `:sensitive_file`, `:hardcoded_secret`, and `:suspicious_dependency`.

## Serialization

```ruby
# Save to JSON
File.write("profile.json", profile.to_json)

# Restore from hash
data = JSON.parse(File.read("profile.json"))
restored = Spurline::Cartographer::RepoProfile.from_h(data)
```

## What Comes Next

Phase 3 spurs will consume RepoProfile to make intelligent decisions:

- **spurline-test** reads `profile.ci.test_command` to know which test runner to invoke
- **spurline-deploy** reads `profile.entry_points` and `profile.ci.deploy_command`
- **spurline-review** reads `profile.frameworks.lint` to review against project standards
- **spurline-docs** reads the full profile to generate accurate setup documentation
