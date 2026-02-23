# Spurline Review — Pull Request Code Review

Spurline Review fetches pull request diffs from GitHub, analyzes them for code quality issues, and posts structured review comments. It combines pattern-based static analysis with LLM reasoning to produce constructive, actionable feedback.

## Quick Start

```ruby
require "spurline/review"

class MyReviewAgent < Spurline::Agent
  use_model :claude_sonnet

  persona(:default) do
    system_prompt "You review pull requests for code quality and security."
  end

  tools :fetch_pr_diff, :analyze_diff, :summarize_findings, :post_review_comment
end

agent = MyReviewAgent.new
agent.run("Review PR #42 on acme/widget") do |chunk|
  print chunk.text
end
```

## GitHub Token Configuration

`FetchPRDiff` and `PostReviewComment` require a GitHub token. The token is resolved in this order:

1. Explicit `github_token:` keyword argument passed to the tool
2. `ENV["GITHUB_TOKEN"]` environment variable

Both tools declare `secret :github_token`, which integrates with Spurline's secret management system. If no token is available, `Spurline::ConfigurationError` is raised with a message explaining how to provide it.

The token needs the `repo` and `pull_requests` scopes for full functionality (reading diffs and posting comments).

## Tools

### fetch_pr_diff

Fetches the unified diff for a GitHub pull request along with file change statistics.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo` | String | Yes | Repository in `owner/repo` format (e.g., `acme/widget`) |
| `pr_number` | Integer | Yes | Pull request number |
| `provider` | String | No | Git hosting provider. Only `github` is supported in v1. |

**Returns:**

```ruby
{
  diff: "diff --git a/lib/foo.rb b/lib/foo.rb\n...",  # Raw unified diff
  files_changed: 5,                                     # Number of changed files
  additions: 120,                                       # Total lines added
  deletions: 45,                                        # Total lines removed
}
```

Unsupported providers raise `Spurline::Review::Error`. GitLab and Bitbucket support is planned for a future release.

### analyze_diff

Parses a unified diff and detects code quality issues using pattern-based checks. Returns structured findings with file paths, line numbers, severities, and suggestions. This tool is **scoped** — when a `ScopedToolContext` is active, files outside the scope are skipped.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `diff` | String | Yes | Unified diff text to analyze |
| `repo_profile` | Object | No | Optional Cartographer RepoProfile for convention-aware checks |

**Returns:**

```ruby
{
  findings: [
    {
      file: "lib/foo.rb",
      line: 42,
      severity: :critical,
      category: :security,
      message: "Possible hardcoded secret or credential",
      suggestion: "Move this value to environment variables or a secrets manager.",
    }
  ],
  file_count: 5,         # Number of files analyzed
  total_issues: 3,       # Total findings count
}
```

**Analysis categories:**

| Category | Checks | Severity |
|----------|--------|----------|
| `:security` | Hardcoded secrets (API keys, tokens, passwords, AWS credentials, private keys), `eval()` usage | `:critical` / `:high` |
| `:debug` | Debugger statements (`binding.pry`, `binding.irb`, `byebug`, `debugger`, `console.log`, debug prints, `require "pry"`) | `:high` |
| `:style` | Trailing whitespace, lines exceeding 120 characters | `:low` |
| `:maintenance` | TODO/FIXME/HACK/XXX comments in new code | `:info` |

The tool uses the `DiffParser` class internally to parse unified diffs into structured file entries with additions, deletions, and hunks. Only **additions** (new lines) are checked — deleted code is not flagged.

### summarize_findings

Groups code review findings by severity and renders a markdown summary. This is a **pure function** with no side effects — it is **idempotent** and makes no API calls.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `findings` | Array | Yes | Array of finding objects from `analyze_diff` |
| `file_count` | Integer | No | Number of files analyzed (for display) |

**Returns:** A markdown string with findings grouped by severity (critical first, info last), each with emoji indicators:

- Critical: alarm
- High: red circle
- Medium: orange circle
- Low: yellow circle
- Info: blue circle

When no findings are present, returns `"No issues found. The diff looks clean."`.

### post_review_comment

Posts a review comment on a GitHub pull request. Supports both general PR comments and inline file-level comments. **Requires confirmation** before posting.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo` | String | Yes | Repository in `owner/repo` format |
| `pr_number` | Integer | Yes | Pull request number |
| `body` | String | Yes | Comment body in markdown |
| `file` | String | No | File path for inline comment (omit for general PR comment) |
| `line` | Integer | No | Line number for inline comment (required if `file` is provided) |

**Returns:** Parsed JSON response from the GitHub API containing the created comment.

When `file` is provided without `line`, raises `ArgumentError` — inline comments require both a file path and a line number.

**Idempotency:** This tool declares `idempotent true` with `idempotency_key :pr_number, :repo, :file, :line, :body`. When the idempotency system is active, identical comments are not posted twice. This prevents duplicate review comments if the agent retries or resumes from a suspended session.

## CodeReviewAgent

The reference agent demonstrates the full review workflow with suspension behavior.

```ruby
module Spurline
  module Review
    module Agents
      class CodeReviewAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are a thorough, constructive code reviewer. Your job is to:

            1. Fetch the pull request diff using fetch_pr_diff
            2. Analyze the diff for code quality issues using analyze_diff
            3. Summarize findings using summarize_findings
            4. Post review comments using post_review_comment

            Guidelines:
            - Be constructive. Suggest improvements, don't just point out problems.
            - Prioritize security issues (hardcoded secrets, eval usage) above all else.
            - Group related findings into a single comment when they affect the same area.
            - Always include the summarized findings as a top-level PR comment.
            - After posting your review, stop and wait for the author's response.
          PROMPT
        end

        tools :fetch_pr_diff, :analyze_diff, :summarize_findings, :post_review_comment

        guardrails do
          max_tool_calls 20
          max_turns 8
        end

        episodic true

        suspend_until :custom do |boundary|
          if boundary.type == :after_tool_result &&
              boundary.context[:tool_name] == :post_review_comment
            :suspend
          else
            :continue
          end
        end
      end
    end
  end
end
```

**Suspension behavior:** The agent suspends after posting a review comment. This is intentional — the agent should wait for the PR author's response before continuing. When the author replies, resume the session and the agent can respond to feedback or post follow-up comments. See the [Suspended Sessions guide](../../guides/suspended_sessions.md) for details on resumption.

**Guardrails:**

- **`max_tool_calls 20`** — allows fetching the diff, analyzing it, summarizing, and posting multiple inline comments
- **`max_turns 8`** — enough for the full review cycle including follow-up after resumption

## DiffParser

`Spurline::Review::DiffParser` is an internal utility that parses unified diff text into structured data. It handles file headers, hunk headers, additions, deletions, context lines, and file renames.

```ruby
files = Spurline::Review::DiffParser.parse(diff_text)
# => [
#   {
#     file: "lib/foo.rb",
#     old_file: nil,             # Non-nil for renames
#     additions: [{ line_number: 42, content: "new code" }],
#     deletions: [{ line_number: 40, content: "old code" }],
#     hunks: [{
#       old_start: 38, new_start: 38,
#       lines: [{ type: :addition, line_number: 42, content: "new code" }, ...]
#     }],
#   }
# ]
```

## GitHubClient

`Spurline::Review::GitHubClient` wraps the GitHub REST API using stdlib `net/http`. It provides two methods:

- `pull_request_diff(repo:, pr_number:)` — fetches the diff and PR metadata
- `create_review_comment(repo:, pr_number:, body:, file:, line:)` — posts comments

The client handles authentication, rate limiting, and error responses with specific error classes:

| Error | When |
|-------|------|
| `Spurline::Review::AuthenticationError` | 401/403 from GitHub (bad token or missing scopes) |
| `Spurline::Review::RateLimitError` | 429 from GitHub (includes reset time) |
| `Spurline::Review::APIError` | Any other non-success response or network failure |

## Errors

All errors inherit from `Spurline::Review::Error`, which inherits from `Spurline::AgentError`.

| Error | When |
|-------|------|
| `Spurline::Review::Error` | Base error (unsupported provider) |
| `Spurline::Review::APIError` | GitHub API returned an unexpected response |
| `Spurline::Review::AuthenticationError` | GitHub token is invalid or lacks required scopes |
| `Spurline::Review::RateLimitError` | GitHub API rate limit exceeded |
