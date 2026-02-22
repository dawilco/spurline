# frozen_string_literal: true

module Spurline
  module Docs
    # Base error for all spurline-docs errors.
    class Error < Spurline::AgentError; end

    # Raised when write_doc_file targets a path that already exists
    # and overwrite is not explicitly enabled.
    class FileExistsError < Error; end

    # Raised when a doc file path attempts to escape the repository root.
    # All output paths must resolve within the repo_path directory.
    class PathTraversalError < Error; end

    # Raised when a doc generator cannot produce valid output from the
    # available RepoProfile data.
    class GenerationError < Error; end
  end
end
