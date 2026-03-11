# frozen_string_literal: true

workers ENV.fetch("WEB_CONCURRENCY", 2).to_i
threads_count = ENV.fetch("MAX_THREADS", 5).to_i
threads threads_count, threads_count

bind "tcp://0.0.0.0:9292"
environment ENV.fetch("RACK_ENV", "production")

preload_app!
