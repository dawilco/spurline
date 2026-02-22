# frozen_string_literal: true

module Spurline
  module Memory
    # Structured per-session trace for replay and explainability.
    class EpisodicStore
      attr_reader :enabled

      def initialize(enabled: true, episodes: [])
        @enabled = enabled
        @episodes = Array(episodes).map { |episode| coerce_episode(episode) }
      end

      def record(type:, content:, metadata: {}, turn_number: nil, parent_episode_id: nil, timestamp: Time.now)
        return nil unless enabled

        episode = Episode.new(
          type: type,
          content: content,
          metadata: metadata,
          timestamp: timestamp,
          turn_number: turn_number,
          parent_episode_id: parent_episode_id
        )
        @episodes << episode
        episode
      end

      def all
        @episodes.dup
      end

      def count
        @episodes.length
      end

      def empty?
        @episodes.empty?
      end

      def clear!
        @episodes.clear
      end

      def for_turn(turn_number)
        @episodes.select { |episode| episode.turn_number == turn_number }
      end

      def tool_calls
        by_type(:tool_call)
      end

      def decisions
        by_type(:decision)
      end

      def external_data
        by_type(:external_data)
      end

      def user_messages
        by_type(:user_message)
      end

      def assistant_responses
        by_type(:assistant_response)
      end

      def find(id)
        @episodes.find { |episode| episode.id == id }
      end

      def serialize
        @episodes.map(&:to_h)
      end

      def restore(serialized_episodes)
        @episodes = Array(serialized_episodes).map { |episode| coerce_episode(episode) }
        self
      end

      def explain
        return "No episodes recorded." if @episodes.empty?

        @episodes.sort_by(&:timestamp).map do |episode|
          turn_label = episode.turn_number ? "Turn #{episode.turn_number}" : "Turn ?"
          "#{turn_label} | #{episode_label(episode)}#{episode_parent_label(episode)}"
        end.join("\n")
      end

      private

      def by_type(type)
        target = type.to_sym
        @episodes.select { |episode| episode.type == target }
      end

      def coerce_episode(episode)
        return episode if episode.is_a?(Episode)

        Episode.from_h(episode)
      end

      def episode_label(episode)
        case episode.type
        when :user_message
          "User message: #{summarize(episode.content)}"
        when :decision
          decision = episode.metadata[:decision] || episode.metadata["decision"] || "decision"
          "Decision (#{decision}): #{summarize(episode.content)}"
        when :tool_call
          tool_name = episode.metadata[:tool_name] || episode.metadata["tool_name"] || "unknown_tool"
          "Tool call #{tool_name}: #{summarize(episode.content)}"
        when :external_data
          source = episode.metadata[:source] || episode.metadata["source"] || "external"
          "External data (#{source}): #{summarize(episode.content)}"
        when :assistant_response
          "Assistant response: #{summarize(episode.content)}"
        else
          "#{episode.type}: #{summarize(episode.content)}"
        end
      end

      def episode_parent_label(episode)
        return "" unless episode.parent_episode_id

        " [after #{episode.parent_episode_id}]"
      end

      def summarize(content)
        text = case content
               when Spurline::Security::Content
                 content.text
               when String
                 content
               else
                 content.inspect
               end

        cleaned = text.to_s.gsub(/\s+/, " ").strip
        return cleaned if cleaned.length <= 120

        "#{cleaned[0, 117]}..."
      end
    end
  end
end
