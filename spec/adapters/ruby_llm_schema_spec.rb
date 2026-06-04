# frozen_string_literal: true

require "spec_helper"
require "active_model"

RSpec.describe RubyLLM::Instructor::Adapters::RubyLlmSchemaAdapter do
  describe "#build_schema" do
    context "with a PORO (plain Ruby class)" do
      let(:klass) { Class.new { attr_accessor :username, :account_balance } }
      subject { described_class.new(klass) }

      it "compiles a RubyLLM::Schema from instance setters" do
        expect(subject.build_schema.ancestors).to include(RubyLLM::Schema)
      end
    end

    context "with Data.define (immutable value object)" do
      let(:klass) { Data.define(:first_name, :last_name) }
      subject { described_class.new(klass) }

      it "compiles a RubyLLM::Schema from Data members" do
        expect(subject.build_schema.ancestors).to include(RubyLLM::Schema)
      end
    end

    context "with Struct" do
      let(:klass) { Struct.new(:company, :phone) }
      subject { described_class.new(klass) }

      it "compiles a RubyLLM::Schema from Struct members" do
        expect(subject.build_schema.ancestors).to include(RubyLLM::Schema)
      end
    end

    context "with ActiveModel::Attributes (typed fields)" do
      let(:klass) do
        Class.new do
          include ActiveModel::Model
          include ActiveModel::Attributes
          attribute :name,     :string
          attribute :quantity, :integer
          attribute :price,    :decimal
          attribute :active,   :boolean
          validates :name, presence: true
        end
      end
      subject { described_class.new(klass) }

      it "compiles a RubyLLM::Schema with inferred types" do
        expect(subject.build_schema.ancestors).to include(RubyLLM::Schema)
      end

      it "marks only presence-validated fields as required" do
        schema_instance = subject.build_schema.new
        json = schema_instance.to_json_schema
        required = Array(json.dig(:schema, :required)).map(&:to_s)
        expect(required).to include("name")
        expect(required).not_to include("quantity", "price", "active")
      end
    end

    context "with a class that defines to_json_schema at the class level" do
      let(:custom_schema) do
        { name: "article", schema: { type: "object", properties: { title: { type: "string" } }, required: ["title"] } }
      end
      let(:klass) do
        schema = custom_schema
        Class.new do
          attr_accessor :title
          define_singleton_method(:to_json_schema) { schema }
        end
      end
      subject { described_class.new(klass) }

      it "returns the custom schema hash without introspection" do
        expect(subject.build_schema).to eq(custom_schema)
      end
    end

    context "with a class that defines to_json_schema as an instance method" do
      let(:custom_schema) do
        { name: "instance_schema", schema: { type: "object", properties: { body: { type: "string" } }, required: ["body"] } }
      end
      let(:klass) do
        schema = custom_schema
        Class.new do
          attr_accessor :body
          define_method(:to_json_schema) { schema }
        end
      end
      subject { described_class.new(klass) }

      it "instantiates the class and returns its to_json_schema" do
        expect(subject.build_schema).to eq(custom_schema)
      end
    end

    context "with ActiveModel::Attributes including an :id attribute" do
      let(:klass) do
        Class.new do
          include ActiveModel::Model
          include ActiveModel::Attributes
          attribute :id,    :integer
          attribute :title, :string
        end
      end
      subject { described_class.new(klass) }

      it "excludes the id attribute from the schema" do
        schema_instance = subject.build_schema.new
        properties = schema_instance.to_json_schema.dig(:schema, :properties)
        expect(properties.keys.map(&:to_s)).not_to include("id")
        expect(properties.keys.map(&:to_s)).to include("title")
      end
    end

    context "with ActiveModel::Attributes using :float type" do
      let(:klass) do
        Class.new do
          include ActiveModel::Model
          include ActiveModel::Attributes
          attribute :score, :float
        end
      end
      subject { described_class.new(klass) }

      it "maps :float to a number field in the schema" do
        expect(subject.build_schema.ancestors).to include(RubyLLM::Schema)
      end
    end

    context "with a native Dry::Validation::Contract subclass" do
      let(:klass) do
        Class.new(Dry::Validation::Contract) do
          params do
            required(:name).filled(:string)
            required(:email).filled(:string)
          end
        end
      end
      subject { described_class.new(klass) }

      it "returns a hash schema (not a RubyLLM::Schema class)" do
        result = subject.build_schema
        expect(result).to be_a(Hash)
      end

      it "includes a :schema key with type object" do
        result = subject.build_schema
        expect(result[:schema][:type]).to eq("object")
      end

      it "includes all contract fields in the schema properties" do
        result = subject.build_schema
        keys = result[:schema][:properties].keys.map(&:to_s)
        expect(keys).to include("name", "email")
      end

      it "does not include the $schema meta key" do
        result = subject.build_schema
        expect(result).not_to have_key("$schema")
        expect(result).not_to have_key(:"$schema")
      end
    end
  end
end
