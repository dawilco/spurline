# frozen_string_literal: true

module Spurline
  module Review
    class Spur < Spurline::Spur
      spur_name :review

      tools do
        register :analyze_diff, Spurline::Review::Tools::AnalyzeDiff
        register :fetch_pr_diff, Spurline::Review::Tools::FetchPRDiff
        register :post_review_comment, Spurline::Review::Tools::PostReviewComment
        register :summarize_findings, Spurline::Review::Tools::SummarizeFindings
      end

      permissions do
        default_trust :external
        requires_confirmation false
      end
    end
  end
end
