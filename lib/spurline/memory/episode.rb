# frozen_string_literal: true

require "securerandom"

module Spurline
  module Memory
    # Immutable value object representing one structured event in an agent session.
    class Episode
      attr_reader :id, :type, :content, :metadata, :timestamp, :turn_number, :parent_episode_id

      def initialize(
        type:,
        content:,
        metadata: {},
        timestamp: Time.now,
        turn_number: nil,
        parent_episode_id: nil,
        id: SecureRandom.uuid
      )
        @id = id.to_s
        @type = type.to_sym
        @content = content
        @metadata = (metadata || {}).dup.freeze
        @timestamp = timestamp
        @turn_number = turn_number
        @parent_episode_id = parent_episode_id
        freeze
      end

      def to_h
        {
          id: id,
          type: type,
          content: content,
          metadata: metadata,
          timestamp: timestamp,
          turn_number: turn_number,
          parent_episode_id: parent_episode_id,
        }
      end

      def self.from_h(data)
        hash = data.transform_keys(&:to_sym)
        new(
          id: hash[:id],
          type: hash.fetch(:type),
          content: hash[:content],
          metadata: hash[:metadata] || {},
          timestamp: hash[:timestamp] || Time.now,
          turn_number: hash[:turn_number],
          parent_episode_id: hash[:parent_episode_id]
        )
      end
    end
  end
end
