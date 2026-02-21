# frozen_string_literal: true

module Spurline
  module Security
    module Gates
      # Gate for live user messages. Trust level: :user.
      class UserInput < Base
        class << self
          private

          def trust_level
            :user
          end

          def source_for(user_id: "anonymous", **)
            "user:#{user_id}"
          end
        end
      end
    end
  end
end
