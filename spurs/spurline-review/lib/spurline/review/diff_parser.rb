# frozen_string_literal: true

module Spurline
  module Review
    class DiffParser
      # Regex for diff file headers: "diff --git a/path b/path"
      FILE_HEADER = /\Adiff --git a\/(.+?) b\/(.+)\z/

      # Regex for hunk headers: "@@ -old_start,old_count +new_start,new_count @@"
      HUNK_HEADER = /\A@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/

      # Regex for rename detection: "rename from path" / "rename to path"
      RENAME_FROM = /\Arename from (.+)\z/
      RENAME_TO = /\Arename to (.+)\z/

      # Parses a unified diff string into structured file hunks.
      #
      # @param diff_text [String] Raw unified diff output
      # @return [Array<Hash>] Array of file hashes:
      #   [{ file: String, old_file: String|nil, additions: [{line_number:, content:}],
      #      deletions: [{line_number:, content:}], hunks: [{old_start:, new_start:, lines:}] }]
      def self.parse(diff_text)
        return [] if diff_text.nil? || diff_text.strip.empty?

        files = []
        current_file = nil
        current_hunk = nil
        old_line = 0
        new_line = 0
        rename_from = nil

        diff_text.each_line do |raw_line|
          line = raw_line.chomp

          # Detect file header
          if (match = FILE_HEADER.match(line))
            current_file = build_file_entry(match[2], rename_from)
            files << current_file
            current_hunk = nil
            rename_from = nil
            next
          end

          # Track renames in extended headers
          if (match = RENAME_FROM.match(line))
            rename_from = match[1]
            current_file[:old_file] = rename_from if current_file
            next
          end

          if RENAME_TO.match(line)
            # rename_to is captured by FILE_HEADER's b/path
            next
          end

          # Detect hunk header
          if (match = HUNK_HEADER.match(line))
            old_line = match[1].to_i
            new_line = match[3].to_i
            current_hunk = {
              old_start: old_line,
              new_start: new_line,
              lines: [],
            }
            current_file[:hunks] << current_hunk if current_file
            next
          end

          # Skip non-hunk lines (index, ---, +++ headers)
          next unless current_hunk && current_file

          case line[0]
          when "+"
            content = line[1..]
            current_file[:additions] << { line_number: new_line, content: content }
            current_hunk[:lines] << { type: :addition, line_number: new_line, content: content }
            new_line += 1
          when "-"
            content = line[1..]
            current_file[:deletions] << { line_number: old_line, content: content }
            current_hunk[:lines] << { type: :deletion, line_number: old_line, content: content }
            old_line += 1
          when " "
            content = line[1..]
            current_hunk[:lines] << { type: :context, old_line: old_line, new_line: new_line, content: content }
            old_line += 1
            new_line += 1
          when "\\"
            # "\ No newline at end of file" — skip
            next
          else
            # Context line without leading space (some diff formats)
            old_line += 1
            new_line += 1
          end
        end

        files
      end

      # @param path [String] File path from diff header
      # @param rename_from [String, nil] Original path if renamed
      # @return [Hash] Empty file entry
      def self.build_file_entry(path, rename_from)
        {
          file: path,
          old_file: rename_from,
          additions: [],
          deletions: [],
          hunks: [],
        }
      end

      private_class_method :build_file_entry
    end
  end
end
