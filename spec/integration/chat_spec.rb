# frozen_string_literal: true

require "spec_helper"
require "active_model"
require "dry-validation"

# These specs make real API calls against OpenRouter.
# Run with: bundle exec rspec spec/integration --tag integration
# Requires OPENROUTER_API_KEY to be set in the environment.

MODEL = "mistralai/mistral-small-3.2-24b-instruct"

class ContactInfo
  attr_accessor :name, :email
end

class Lead
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :company, :string
  attribute :phone,   :string
  attribute :revenue, :integer

  validates :company, presence: true
  validates :phone,   format: { with: /\A\+?\d{7,15}\z/, message: "must be digits, optional leading +" }
end

PersonRecord = Data.define(:first_name, :last_name, :city)

AddressStruct = Struct.new(:street, :city, :zip, keyword_init: true)

class ArticleContract < Dry::Validation::Contract
  params do
    required(:title).filled(:string)
    required(:author).filled(:string)
    required(:word_count).filled(:integer)
  end
end

class Product
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :sku, :string

  validates :sku,
            format: {
              with: /\Asku_[a-z]+_\d{4}\z/,
              message: "must look like sku_brandname_1234 (lowercase, underscores)"
            }
end

class SupportTicket
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :priority, :string

  validates :priority,
            inclusion: { in: %w[P0 P1 P2 P3], message: "must be one of P0, P1, P2, P3" }
end

RSpec.describe RubyLLM::Instructor::Client, :integration do
  before(:all) do
    RubyLLM.configure do |c|
      c.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY")
    end
  end

  let(:client) { described_class.new }

  describe "plain Ruby class (PORO)" do
    it "extracts name and email from natural language" do
      result = client.chat(
        model: MODEL,
        response_model: ContactInfo,
        prompt: "My name is Sal Scotto and you can reach me at sal@example.com"
      )

      expect(result).to be_a(ContactInfo)
      expect(result.name).to match(/sal/i)
      expect(result.email).to include("@")
    end
  end

  describe "ActiveModel with validation" do
    it "extracts a lead and passes validation" do
      result = client.chat(
        model: MODEL,
        response_model: Lead,
        prompt: "Inbound: Company is Stripe, phone +15550192831, ARR is roughly 4 billion dollars."
      )

      expect(result).to be_a(Lead)
      expect(result.company).to be_present
      expect(result.phone).to match(/\A\+?\d{7,15}\z/)
      expect(result.revenue).to be_a(Integer)
    end
  end

  describe "Data.define (immutable value object)" do
    it "returns a frozen Data instance" do
      result = client.chat(
        model: MODEL,
        response_model: PersonRecord,
        prompt: "Extract: John Smith lives in Austin."
      )

      expect(result).to be_a(PersonRecord)
      expect(result).to be_frozen
      expect(result.first_name).to be_a(String)
      expect(result.city).to match(/austin/i)
    end
  end

  describe "Struct" do
    it "extracts a mailing address" do
      result = client.chat(
        model: MODEL,
        response_model: AddressStruct,
        prompt: "Ship to: 123 Main Street, Springfield, 62701"
      )

      expect(result).to be_a(AddressStruct)
      expect(result.city).to match(/springfield/i)
      expect(result.zip).to eq("62701")
    end
  end

  describe "native Dry::Validation::Contract" do
    it "extracts article metadata and returns a frozen Data object" do
      result = client.chat(
        model: MODEL,
        response_model: ArticleContract,
        prompt: "Article: 'The Rise of AI' by Jane Doe, approximately 1200 words."
      )

      expect(result).to be_frozen
      expect(result.title).to be_a(String)
      expect(result.author).to be_a(String)
      expect(result.word_count).to be_a(Integer)
    end
  end

  describe "auto-retry on validation failure" do
    it "self-corrects and returns a valid object within retries" do
      # Forces a scenario where the model must get the phone format right.
      # If the first attempt fails format validation, instructor retries with errors.
      result = client.chat(
        model: MODEL,
        response_model: Lead,
        prompt: "Company: Acme Corp. Phone: (555) 867-5309. No revenue info.",
        max_retries: 3
      )

      expect(result).to be_a(Lead)
      expect(result).to be_valid
    end
  end

  describe "retry feedback loop (first attempt is expected to fail validation)" do
    it "maps a free-text urgency to an allowed enum value after the first attempt fails inclusion" do
      chat_calls = 0
      allow(RubyLLM).to receive(:chat).and_wrap_original do |original, **kwargs|
        chat_calls += 1
        original.call(**kwargs)
      end

      result = client.chat(
        model: MODEL,
        response_model: SupportTicket,
        prompt: "Customer says: 'My production site is completely down and we are losing " \
                "thousands of dollars per minute, this is the most urgent thing imaginable.' " \
                "Please assign a priority.",
        max_retries: 4
      )

      expect(result).to be_a(SupportTicket)
      expect(result).to be_valid
      expect(%w[P0 P1 P2 P3]).to include(result.priority)
      expect(chat_calls).to be > 1
    end

    it "reformats a SKU after the first attempt fails the strict format" do
      chat_calls = 0
      allow(RubyLLM).to receive(:chat).and_wrap_original do |original, **kwargs|
        chat_calls += 1
        original.call(**kwargs)
      end

      result = client.chat(
        model: MODEL,
        response_model: Product,
        prompt: "The product SKU printed on the invoice is ACME-1234.",
        max_retries: 4
      )

      expect(result).to be_a(Product)
      expect(result).to be_valid
      expect(result.sku).to match(/\Asku_[a-z]+_\d{4}\z/)
      expect(chat_calls).to be > 1
    end
  end

  describe "streaming" do
    it "invokes the stream proc with chunks and still returns a hydrated object" do
      chunks = []

      result = client.chat(
        model: MODEL,
        response_model: ContactInfo,
        prompt: "Name: Ada Lovelace, email: ada@babbage.io",
        stream: ->(chunk) { chunks << chunk }
      )

      expect(result).to be_a(ContactInfo)
      expect(result.name).to match(/ada/i)
      expect(chunks).not_to be_empty
    end
  end
end
