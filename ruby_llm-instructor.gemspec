# frozen_string_literal: true

require_relative "lib/ruby_llm/instructor/version"

Gem::Specification.new do |spec|
  spec.name          = "ruby_llm-instructor"
  spec.version       = RubyLLM::Instructor::VERSION
  spec.authors       = ["Sal Scotto Di Luzio"]
  spec.summary       = "Structured outputs for LLMs in Ruby, powered by RubyLLM and Can be used with ActiveModel, DryValidations or PORO objects that define a valid? method."
  spec.description   = "Validates and coerces unstructured LLM responses directly into rich, schema-validated Ruby objects with automatic self-correction loops."
  spec.licenses      = ["MIT"]
  spec.homepage      = "https://github.com/washu/ruby_llm-instructor"
  spec.metadata      = {
    "source_code_uri" => "https://github.com/washu/ruby_llm-instructor",
    "changelog_uri"   => "https://github.com/washu/ruby_llm-instructor/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/washu/ruby_llm-instructor/issues"
  }

  spec.files         = Dir["lib/**/*.rb", "Rakefile", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "ruby_llm", ">= 1.15.0"
  spec.add_runtime_dependency "ruby_llm-schema", ">= 0.4.0", "< 2"
  # the user decides on teh valdiation model, i.e. dry or acive model or a poro
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "activemodel", ">= 7.0"
  spec.add_development_dependency "dry-validation", ">= 1.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
