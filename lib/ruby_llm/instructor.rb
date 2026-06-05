# frozen_string_literal: true

require "ruby_llm"
require "ruby_llm/schema"
require "active_model"
require_relative "instructor/version"
require_relative "instructor/utils"
require_relative "instructor/adapters/ruby_llm_schema"
require_relative "instructor/client"

begin
  require "dry-validation"
  require "dry/schema"
  Dry::Schema.load_extensions(:json_schema)
rescue LoadError
  nil
end

module RubyLLM
  module Instructor
    class ValidationError < StandardError; end
  end
end
