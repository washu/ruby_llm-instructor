# frozen_string_literal: true

module RubyLLM
  module Instructor
    module Utils
      # Returns true when +klass+ is a Dry::Validation::Contract subclass.
      # Safely returns false when dry-validation is not loaded or klass is not a
      # class (e.g. an instance, a module, or a Data object).
      def dry_contract?(klass)
        !!(defined?(Dry::Validation::Contract) &&
           klass.is_a?(Class) &&
           klass < Dry::Validation::Contract)
      rescue TypeError
        false
      end
      module_function :dry_contract?
    end
  end
end

