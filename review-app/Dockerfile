# Multi-stage build for the Spurline Review App.
# Build context: repository root (not review-app/).
#
#   docker build -f review-app/Dockerfile -t spurline-review .

# --- Stage 1: Builder -------------------------------------------------------
FROM ruby:3.4-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libyaml-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy gemspecs and version files first for layer caching.
COPY spurline.gemspec ./
COPY lib/spurline/version.rb lib/spurline/
COPY spurs/spurline-review/spurline-review.gemspec spurs/spurline-review/
COPY spurs/spurline-review/lib/spurline/review/version.rb spurs/spurline-review/lib/spurline/review/
COPY spurs/spurline-dashboard/spurline-dashboard.gemspec spurs/spurline-dashboard/
COPY spurs/spurline-dashboard/lib/spurline/dashboard/version.rb spurs/spurline-dashboard/lib/spurline/dashboard/
COPY spurs/spurline-web-search/spurline-web-search.gemspec spurs/spurline-web-search/
COPY spurs/spurline-web-search/lib/spurline/web_search/version.rb spurs/spurline-web-search/lib/spurline/web_search/

# Copy review-app Gemfile and install dependencies.
COPY review-app/Gemfile review-app/Gemfile.lock* review-app/
WORKDIR /app/review-app
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Copy all source code.
WORKDIR /app
COPY lib/ lib/
COPY exe/ exe/
COPY config/ config/
COPY spurs/spurline-review/lib/ spurs/spurline-review/lib/
COPY spurs/spurline-dashboard/lib/ spurs/spurline-dashboard/lib/
COPY spurs/spurline-web-search/lib/ spurs/spurline-web-search/lib/
COPY review-app/ review-app/

# --- Stage 2: Runtime --------------------------------------------------------
FROM ruby:3.4-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 spurline && \
    useradd --uid 1000 --gid spurline --create-home spurline

WORKDIR /app
COPY --from=builder /app /app
COPY --from=builder /usr/local/bundle /usr/local/bundle

RUN mkdir -p /app/review-app/tmp && chown -R spurline:spurline /app/review-app/tmp

USER spurline
EXPOSE 9292

WORKDIR /app/review-app
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
