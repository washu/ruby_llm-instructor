# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
end

require "bundler/setup"
require "ruby_llm/instructor"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
  Kernel.srand config.seed

  # Integration specs require OPENROUTER_API_KEY and are excluded by default.
  # Run them with: bundle exec rspec --tag integration
  config.filter_run_excluding :integration unless ENV["OPENROUTER_API_KEY"]
end
