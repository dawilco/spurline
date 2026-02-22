# frozen_string_literal: true

module Spurline
  module Review
    module Tools
      class FetchPRDiff < Spurline::Tools::Base
        tool_name :fetch_pr_diff
        description "Fetch the diff for a GitHub pull request. " \
          "Returns the raw diff text along with file change statistics."
        secret :github_token, description: "GitHub personal access token or app token"

        parameters({
          type: "object",
          properties: {
            repo: {
              type: "string",
              description: "Repository in 'owner/repo' format (e.g., 'acme/widget')",
            },
            pr_number: {
              type: "integer",
              description: "Pull request number",
            },
            provider: {
              type: "string",
              description: "Git hosting provider. Only 'github' is supported in v1.",
            },
          },
          required: %w[repo pr_number],
        })

        SUPPORTED_PROVIDERS = %w[github].freeze

        def call(repo:, pr_number:, provider: "github", github_token: nil)
          validate_provider!(provider)
          token = resolve_token(github_token)
          client = GitHubClient.new(token: token)
          client.pull_request_diff(repo: repo, pr_number: Integer(pr_number))
        end

        private

        def validate_provider!(provider)
          return if SUPPORTED_PROVIDERS.include?(provider.to_s.downcase)

          raise Spurline::Review::Error,
            "Unsupported provider '#{provider}'. " \
            "Only #{SUPPORTED_PROVIDERS.join(', ')} is supported in v1. " \
            "GitLab and Bitbucket support is planned for a future release."
        end

        def resolve_token(explicit_token)
          explicit_token || ENV["GITHUB_TOKEN"]
        end
      end
    end
  end
end
