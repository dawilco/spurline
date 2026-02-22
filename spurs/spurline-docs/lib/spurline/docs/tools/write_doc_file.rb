# frozen_string_literal: true

require "fileutils"

module Spurline
  module Docs
    module Tools
      class WriteDocFile < Spurline::Tools::Base
        tool_name :write_doc_file
        description "Write a documentation file to disk within a repository. " \
                    "Enforces path traversal protection — all output paths must resolve " \
                    "within the repository root. Requires confirmation before writing."
        parameters({
          type: "object",
          properties: {
            repo_path: {
              type: "string",
              description: "Absolute path to the repository root",
            },
            relative_path: {
              type: "string",
              description: "Path relative to repo root for the output file (e.g., 'docs/GETTING_STARTED.md')",
            },
            content: {
              type: "string",
              description: "Markdown content to write",
            },
            overwrite: {
              type: "boolean",
              description: "If true, overwrite existing files. Default false.",
            },
          },
          required: %w[repo_path relative_path content],
        })

        scoped true
        requires_confirmation true

        def call(repo_path:, relative_path:, content:, overwrite: false, _scope: nil)
          expanded_repo = File.expand_path(repo_path)
          validate_repo_path!(expanded_repo)

          full_path = resolve_and_validate_path!(expanded_repo, relative_path)
          check_existing!(full_path, overwrite)

          directory = File.dirname(full_path)
          FileUtils.mkdir_p(directory) unless File.directory?(directory)

          File.write(full_path, content)

          {
            written: true,
            path: full_path,
            relative_path: relative_path,
            bytes: content.bytesize,
          }
        end

        private

        def validate_repo_path!(path)
          return if File.directory?(path)

          raise Spurline::Docs::Error,
            "Repository path '#{path}' does not exist or is not a directory."
        end

        def resolve_and_validate_path!(repo_path, relative_path)
          raise Spurline::Docs::PathTraversalError, "Path must be provided." if relative_path.to_s.strip.empty?

          if relative_path.include?("\0")
            raise Spurline::Docs::PathTraversalError,
              "Path contains null bytes — this is not a valid file path."
          end

          candidate = File.expand_path(relative_path, repo_path)
          repo_prefix = repo_path.end_with?("/") ? repo_path : "#{repo_path}/"

          unless candidate == repo_path || candidate.start_with?(repo_prefix)
            raise Spurline::Docs::PathTraversalError,
              "Path '#{relative_path}' resolves to '#{candidate}' which is outside " \
              "the repository root '#{repo_path}'. All doc files must be within the repo."
          end

          anchor = deepest_existing_ancestor(File.dirname(candidate))
          anchor_real = File.realpath(anchor)
          repo_real = File.realpath(repo_path)
          repo_real_prefix = repo_real.end_with?("/") ? repo_real : "#{repo_real}/"

          unless anchor_real == repo_real || anchor_real.start_with?(repo_real_prefix)
            raise Spurline::Docs::PathTraversalError,
              "Path '#{relative_path}' resolves through '#{anchor_real}', which escapes " \
              "the repository root '#{repo_path}'."
          end

          candidate
        end

        def deepest_existing_ancestor(path)
          current = path
          until File.exist?(current)
            parent = File.dirname(current)
            break if parent == current

            current = parent
          end
          current
        end

        def check_existing!(path, overwrite)
          return unless File.exist?(path)
          return if overwrite

          raise Spurline::Docs::FileExistsError,
            "File already exists at '#{path}'. Set overwrite: true to replace it, " \
            "or choose a different path."
        end
      end
    end
  end
end
