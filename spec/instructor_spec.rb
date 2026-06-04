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
end
