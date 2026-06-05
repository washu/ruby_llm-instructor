# frozen_string_literal: true

require "spec_helper"
require "active_model"
require "dry-validation"

# Plain Ruby class — no validation framework
class PersonPoro
  attr_accessor :name, :email
end

# ActiveModel with format validation
class PersonActiveModel
  include ActiveModel::Model
  attr_accessor :name, :email

  validates :email, format: { with: /\A[^@\s]+@[^@\s]+\z/, message: "must include @" }
end

# ActiveModel with inclusion (enum) validation
class SupportTicketModel
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :priority, :string
  validates :priority,
            inclusion: { in: %w[P0 P1 P2 P3], message: "must be one of P0, P1, P2, P3" }
end

# ActiveModel with strict format validation
class ProductModel
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :sku, :string
  validates :sku,
            format: {
              with: /\Asku_[a-z]+_\d{4}\z/,
              message: "must look like sku_brandname_1234 (lowercase, underscores)"
            }
end

# Immutable value object (Ruby 3.2+)
PersonData = Data.define(:name, :email)

# Struct with keyword_init for clean keyword construction
PersonStruct = Struct.new(:name, :email, keyword_init: true)

# dry-validation: a PORO whose valid?/errors delegate to a Dry::Validation::Contract.
# This is the duck-typing bridge — instructor-ruby needs no special dry-v knowledge.
class PersonDry
  attr_accessor :name, :email

  CONTRACT = Class.new(Dry::Validation::Contract) do
    params do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end
    rule(:email) { key.failure("must include @") unless value.include?("@") }
  end

  def valid?
    @result = CONTRACT.new.call(name: @name, email: @email)
    @result.success?
  end

  def errors
    DryErrors.new(@result)
  end

  # Bridges dry-validation's result.errors.to_h to the full_messages interface
  # that RubyLLM::Instructor::Client expects.
  DryErrors = Struct.new(:result) do
    def full_messages
      return [] unless result
      result.errors.to_h.flat_map { |field, msgs| msgs.map { |m| "#{field} #{m}" } }
    end
  end
end

RSpec.describe RubyLLM::Instructor::Client do
  let(:client) { described_class.new }
  let(:mock_session) { instance_double("RubyLLM::ChatSession") }

  before do
    allow(RubyLLM).to receive(:chat).with(model: "gpt-4o").and_return(mock_session)
    allow(mock_session).to receive(:with_schema).and_return(mock_session)
  end

  def stub_response(content)
    instance_double("RubyLLM::Response", content: content)
  end

  describe "#chat" do
    context "with a plain Ruby class (PORO)" do
      it "hydrates attributes from the LLM response" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test")

        expect(result).to be_a(PersonPoro)
        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end

      it "hydrates correctly when the LLM returns string keys (real JSON response)" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ "name" => "Sal", "email" => "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test")

        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end

      it "silently ignores extra keys the model has no setter for" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com", unknown_field: "ignored" }))

        result = client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test")

        expect(result.name).to eq("Sal")
        expect(result).not_to respond_to(:unknown_field)
      end
    end

    context "with ActiveModel::Model" do
      it "hydrates the object when validation passes" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonActiveModel, prompt: "test")

        expect(result).to be_a(PersonActiveModel)
        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end

      it "feeds validation errors back to the LLM and retries" do
        bad  = stub_response({ name: "Sal", email: "not-an-email" })
        good = stub_response({ name: "Sal", email: "sal@example.com" })

        expect(mock_session).to receive(:ask).with("Extract person").and_return(bad)
        expect(mock_session).to receive(:ask).with(/Your previous response failed validation.*must include @/).and_return(good)

        result = client.chat(model: "gpt-4o", response_model: PersonActiveModel, prompt: "Extract person", max_retries: 2)

        expect(result.email).to eq("sal@example.com")
      end
    end

    context "with ActiveModel inclusion (enum) validation" do
      it "feeds the inclusion error back to the LLM and recovers with an allowed value" do
        bad  = stub_response({ priority: "URGENT" })
        good = stub_response({ priority: "P0" })

        expect(mock_session).to receive(:ask).with("Assign priority").and_return(bad)
        expect(mock_session).to receive(:ask).with(/Your previous response failed validation.*must be one of P0/).and_return(good)

        result = client.chat(model: "gpt-4o", response_model: SupportTicketModel, prompt: "Assign priority", max_retries: 2)

        expect(result.priority).to eq("P0")
      end
    end

    context "with ActiveModel strict format validation (e.g. SKU)" do
      it "feeds the format error back to the LLM and recovers with a reformatted value" do
        bad  = stub_response({ sku: "ACME-1234" })
        good = stub_response({ sku: "sku_acme_1234" })

        expect(mock_session).to receive(:ask).with("Extract sku").and_return(bad)
        expect(mock_session).to receive(:ask).with(/Your previous response failed validation.*sku_brandname_1234/).and_return(good)

        result = client.chat(model: "gpt-4o", response_model: ProductModel, prompt: "Extract sku", max_retries: 2)

        expect(result.sku).to eq("sku_acme_1234")
      end
    end

    context "with Ruby Data.define (immutable value object)" do
      it "hydrates a frozen value object" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonData, prompt: "test")

        expect(result).to be_a(PersonData)
        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
        expect(result).to be_frozen
      end

      it "hydrates correctly when the LLM returns string keys (real JSON response)" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ "name" => "Sal", "email" => "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonData, prompt: "test")

        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end
    end

    context "with Struct" do
      it "hydrates the struct from the LLM response" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonStruct, prompt: "test")

        expect(result).to be_a(PersonStruct)
        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end
    end

    context "with dry-validation (duck-typed via valid?/errors bridge)" do
      it "hydrates the object when the contract passes" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonDry, prompt: "test")

        expect(result).to be_a(PersonDry)
        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end

      it "feeds contract errors back to the LLM and retries" do
        bad  = stub_response({ name: "Sal", email: "not-valid" })
        good = stub_response({ name: "Sal", email: "sal@example.com" })

        expect(mock_session).to receive(:ask).with("Extract person").and_return(bad)
        expect(mock_session).to receive(:ask).with(/Your previous response failed validation.*email must include @/).and_return(good)

        result = client.chat(model: "gpt-4o", response_model: PersonDry, prompt: "Extract person", max_retries: 2)

        expect(result.email).to eq("sal@example.com")
      end

      it "raises after exhausting retries when the contract always fails" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "bad" }))

        expect {
          client.chat(model: "gpt-4o", response_model: PersonDry, prompt: "test", max_retries: 1)
        }.to raise_error(RubyLLM::Instructor::ValidationError, /failed validation after 1 attempts/)
      end
    end

    context "when max_retries is 0" do
      let(:always_invalid_model) do
        Class.new do
          attr_accessor :name
          def valid? = false
          def errors = Object.new.tap { |e| e.define_singleton_method(:full_messages) { ["bad"] } }
        end
      end

      it "raises immediately on the first validation failure" do
        allow(mock_session).to receive(:ask).once.and_return(stub_response({ name: "" }))

        expect {
          client.chat(model: "gpt-4o", response_model: always_invalid_model, prompt: "test", max_retries: 0)
        }.to raise_error(RubyLLM::Instructor::ValidationError, /failed validation after 0 attempts/)
      end
    end

    context "with a PORO that has valid? = false, errors exists but has no full_messages" do
      let(:partial_errors_model) do
        Class.new do
          attr_accessor :name
          def valid? = false
          def errors = Object.new  # no full_messages method
        end
      end

      it "falls back to a generic validation message" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "x" }))

        expect {
          client.chat(model: "gpt-4o", response_model: partial_errors_model, prompt: "test", max_retries: 0)
        }.to raise_error(RubyLLM::Instructor::ValidationError, /Validation failed/)
      end
    end

    context "with a PORO that has valid? but no errors object" do
      let(:bare_invalid_model) do
        Class.new do
          attr_accessor :name
          def valid? = false
        end
      end

      it "falls back to a generic validation message and retries" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "x" }))
        expect {
          client.chat(model: "gpt-4o", response_model: bare_invalid_model, prompt: "test", max_retries: 1)
        }.to raise_error(RubyLLM::Instructor::ValidationError, /Validation failed/)
      end
    end

    context "with a native Dry::Validation::Contract subclass" do
      let(:contract_klass) do
        Class.new(Dry::Validation::Contract) do
          params do
            required(:name).filled(:string)
            required(:email).filled(:string)
          end
          rule(:email) { key.failure("must include @") unless value.include?("@") }
        end
      end

      it "hydrates a Data object when the contract passes" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: contract_klass, prompt: "test")

        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
        expect(result).to be_frozen
      end

      it "feeds contract rule errors back to the LLM and retries" do
        bad  = stub_response({ name: "Sal", email: "not-valid" })
        good = stub_response({ name: "Sal", email: "sal@example.com" })

        expect(mock_session).to receive(:ask).with("Extract contract").and_return(bad)
        expect(mock_session).to receive(:ask).with(/Your previous response failed validation.*email must include @/).and_return(good)

        result = client.chat(model: "gpt-4o", response_model: contract_klass, prompt: "Extract contract", max_retries: 2)

        expect(result.email).to eq("sal@example.com")
      end

      it "raises after exhausting retries when the contract always fails" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "bad" }))

        expect {
          client.chat(model: "gpt-4o", response_model: contract_klass, prompt: "test", max_retries: 1)
        }.to raise_error(RubyLLM::Instructor::ValidationError, /failed validation after 1 attempts/)
      end

      it "hydrates with string-keyed responses" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ "name" => "Sal", "email" => "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: contract_klass, prompt: "test")

        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end
    end

    context "with streaming (stream: proc)" do
      it "passes the stream proc as a block to ask" do
        chunks = []
        stream_proc = ->(chunk) { chunks << chunk }

        expect(mock_session).to receive(:ask) do |_prompt, &blk|
          expect(blk).not_to be_nil
          stub_response({ name: "Sal", email: "sal@example.com" })
        end

        result = client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test", stream: stream_proc)

        expect(result.name).to eq("Sal")
      end

      it "works without a stream proc (stream: nil is default)" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test")

        expect(result.name).to eq("Sal")
      end
    end

    context "with an invalid mode" do
      it "raises ArgumentError immediately" do
        expect {
          client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test", mode: :json)
        }.to raise_error(ArgumentError, /Unknown mode :json/)
      end
    end

    context "with a positional Struct (no keyword_init)" do
      let(:pos_struct) { Struct.new(:name, :email) }

      it "hydrates using positional args" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: pos_struct, prompt: "test")

        expect(result).to be_a(pos_struct)
        expect(result.name).to eq("Sal")
        expect(result.email).to eq("sal@example.com")
      end
    end

    context "with mode: :tools" do      before do
        allow(RubyLLM).to receive(:chat).with(model: "gpt-4o").and_return(mock_session)
        allow(mock_session).to receive(:with_tool).and_return(mock_session)
        allow(mock_session).to receive(:with_schema).and_return(mock_session)
      end

      it "uses with_tool instead of with_schema" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        expect(mock_session).to receive(:with_tool).and_return(mock_session)
        expect(mock_session).not_to receive(:with_schema)

        client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test", mode: :tools)
      end

      it "hydrates the response model from tools mode" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "Sal", email: "sal@example.com" }))

        result = client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test", mode: :tools)

        expect(result).to be_a(PersonPoro)
        expect(result.name).to eq("Sal")
      end
    end

    context "when max retries are exhausted" do
      let(:always_invalid_model) do
        Class.new do
          attr_accessor :name

          def valid?
            false
          end

          def errors
            @errors ||= Object.new.tap do |e|
              e.define_singleton_method(:full_messages) { ["Name can't be blank"] }
            end
          end
        end
      end

      it "raises a RuntimeError with the attempt count" do
        allow(mock_session).to receive(:ask).and_return(stub_response({ name: "" }))

        expect {
          client.chat(model: "gpt-4o", response_model: always_invalid_model, prompt: "test", max_retries: 1)
        }.to raise_error(RubyLLM::Instructor::ValidationError, /failed validation after 1 attempts/)
      end
    end

    context "when the LLM returns unstructured content instead of a JSON object" do
      it "treats it as a validation failure and retries" do
        allow(mock_session).to receive(:ask).and_return(
          stub_response("Sure, here you go: { name: Sal }"),
          stub_response({ name: "Sal", email: "sal@example.com" })
        )

        result = client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test", max_retries: 2)

        expect(result).to be_a(PersonPoro)
        expect(result.name).to eq("Sal")
      end

      it "raises a RuntimeError after exhausting retries on persistently unstructured content" do
        allow(mock_session).to receive(:ask).and_return(stub_response("not json at all"))

        expect {
          client.chat(model: "gpt-4o", response_model: PersonPoro, prompt: "test", max_retries: 1)
        }.to raise_error(RubyLLM::Instructor::ValidationError, /Expected a structured JSON object/)
      end
    end
  end
end
