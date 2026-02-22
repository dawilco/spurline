# frozen_string_literal: true

module Spurline
  module Review
    module Tools
      class PostReviewComment < Spurline::Tools::Base
        tool_name :post_review_comment
        description "Post a review comment on a GitHub pull request. " \
          "Supports both general PR comments and inline file-level comments."
        requires_confirmation true
        idempotent true
        idempotency_key :pr_number, :repo, :file, :line, :body
        secret :github_token, description: "GitHub personal access token or app token"

        parameters({
          type: "object",
          properties: {
            repo: {
              type: "string",
              description: "Repository in 'owner/repo' format",
            },
            pr_number: {
              type: "integer",
              description: "Pull request number",
            },
            body: {
              type: "string",
              description: "Comment body in markdown",
            },
            file: {
              type: "string",
              description: "File path for inline comment (omit for general PR comment)",
            },
            line: {
              type: "integer",
              description: "Line number for inline comment (required if file is provided)",
            },
          },
          required: %w[repo pr_number body],
        })

        def call(repo:, pr_number:, body:, file: nil, line: nil, github_token: nil)
          validate_inline_params!(file, line)
          token = resolve_token(github_token)
          client = GitHubClient.new(token: token)
          client.create_review_comment(
            repo: repo,
            pr_number: Integer(pr_number),
            body: body,
            file: file,
            line: line ? Integer(line) : nil
          )
        end

        private

        def validate_inline_params!(file, line)
          return unless file && line.nil?

          raise ArgumentError,
            "When 'file' is provided for an inline comment, 'line' must also be specified."
        end

        def resolve_token(explicit_token)
          explicit_token || ENV["GITHUB_TOKEN"]
        end
      end
    end
  end
end
