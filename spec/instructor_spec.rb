# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::Instructor do
  it "has a version number" do
    expect(RubyLLM::Instructor::VERSION).not_to be_nil
  end

  it "exposes RubyLLM::Instructor::Client" do
    expect(RubyLLM::Instructor::Client).to be_a(Class)
  end

  it "exposes RubyLLM::Instructor::ValidationError as a StandardError subclass" do
    expect(RubyLLM::Instructor::ValidationError).to be < StandardError
  end

  it "exposes RubyLLM::Instructor::Adapters::RubyLlmSchemaAdapter" do
    expect(RubyLLM::Instructor::Adapters::RubyLlmSchemaAdapter).to be_a(Class)
  end

  it "exposes RubyLLM::Instructor::Utils" do
    expect(RubyLLM::Instructor::Utils).to be_a(Module)
  end

  describe "RubyLLM::Instructor::Utils.dry_contract?" do
    require "dry-validation"

    it "returns true for a Dry::Validation::Contract subclass" do
      klass = Class.new(Dry::Validation::Contract)
      expect(RubyLLM::Instructor::Utils.dry_contract?(klass)).to be true
    end

    it "returns false for a plain class" do
      expect(RubyLLM::Instructor::Utils.dry_contract?(String)).to be false
    end

    it "returns false for a non-class object" do
      expect(RubyLLM::Instructor::Utils.dry_contract?("not a class")).to be false
    end
  end
end
