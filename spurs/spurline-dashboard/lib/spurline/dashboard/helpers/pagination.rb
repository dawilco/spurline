# frozen_string_literal: true

require "rack/utils"

module Spurline
  module Dashboard
    module Helpers
      # Pagination helper for slicing collections with page/per_page.
      # Returns a hash with :items, :page, :per_page, :total, :total_pages.
      module Pagination
        def paginate(items, page:, per_page: 25)
          page = [page.to_i, 1].max
          total = items.length
          total_pages = [(total.to_f / per_page).ceil, 1].max
          page = [page, total_pages].min

          offset = (page - 1) * per_page
          sliced = items[offset, per_page] || []

          {
            items: sliced,
            page: page,
            per_page: per_page,
            total: total,
            total_pages: total_pages,
          }
        end

        # Generates pagination HTML with prev/next links.
        def pagination_nav(pagination, base_path:, params: {})
          return "" if pagination[:total_pages] <= 1

          parts = []

          if pagination[:page] > 1
            prev_params = params.merge("page" => pagination[:page] - 1)
            query = build_query(prev_params)
            parts << "<a href='#{base_path}?#{query}' class='page-link'>&laquo; Prev</a>"
          else
            parts << "<span class='page-link disabled'>&laquo; Prev</span>"
          end

          parts << "<span class='page-info'>Page #{pagination[:page]} of #{pagination[:total_pages]} (#{pagination[:total]} total)</span>"

          if pagination[:page] < pagination[:total_pages]
            next_params = params.merge("page" => pagination[:page] + 1)
            query = build_query(next_params)
            parts << "<a href='#{base_path}?#{query}' class='page-link'>Next &raquo;</a>"
          else
            parts << "<span class='page-link disabled'>Next &raquo;</span>"
          end

          "<nav class='pagination'>#{parts.join}</nav>"
        end

        private

        def build_query(params)
          params.reject { |_, v| v.nil? || v.to_s.empty? }
                .map { |k, v| "#{Rack::Utils.escape(k.to_s)}=#{Rack::Utils.escape(v.to_s)}" }
                .join("&")
        end
      end
    end
  end
end
