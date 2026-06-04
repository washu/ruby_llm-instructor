# ruby_llm-instructor

[![CI](https://github.com/washu/ruby_llm-instructor/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/washu/ruby_llm-instructor/actions/workflows/ci.yml)

Structured, validated outputs from LLMs for Ruby. Define a Ruby class, hand it to
`RubyLLM::Instructor::Client`, and get back a fully-hydrated, validated instance —
with automatic retries on validation failure.

Part of the [RubyLLM ecosystem](https://rubyllm.com/ecosystem/). Built on top of
[`ruby_llm`](https://github.com/crmne/ruby_llm), so the same code works against
OpenAI, Anthropic, Gemini, and every other provider `ruby_llm` supports.

## Installation

```ruby
gem "ruby_llm-instructor"
```

```bash
bundle install
```

## Quick start

Configure `RubyLLM` with your API key(s), then pass any Ruby class as `response_model`:

```ruby
require "ruby_llm"
require "ruby_llm/instructor"

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

class UserProfile
  attr_accessor :name, :email
end

instructor = RubyLLM::Instructor::Client.new

user = instructor.chat(
  model: "gpt-4o",
  response_model: UserProfile,
  prompt: "Extract information: My name is Sal, reached at sal@example.com"
)

user.name   # => "Sal"
user.email  # => "sal@example.com"
user.class  # => UserProfile
```

## Supported response model types

`ruby_llm-instructor` uses duck-typing — no base class or mixin required. The JSON
schema sent to the LLM is inferred automatically from your class's shape.

### Plain Ruby class (PORO)

Schema inferred from `attr_accessor` setters. No validation — any response is accepted.

```ruby
class UserProfile
  attr_accessor :name, :email
end
```

### ActiveModel

Add validations; `ruby_llm-instructor` calls `valid?` automatically and feeds
error messages back to the LLM on retry.

```ruby
require "active_model"

class LeadCapture
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :company, :string
  attribute :phone,   :string
  attribute :revenue, :integer

  validates :company, presence: true
  validates :phone, format: { with: /\A\+?\d{10,15}\z/, message: "must be a valid phone number" }
end

instructor = RubyLLM::Instructor::Client.new

lead = instructor.chat(
  model: "claude-3-5-sonnet",
  response_model: LeadCapture,
  prompt: "Inbound transcript: We are Stripe, call us at +15550192831. ARR is $4B."
)

lead.company # => "Stripe"
lead.phone   # => "+15550192831"
lead.revenue # => 4000000000
```

Using `ActiveModel::Attributes` also improves the JSON schema sent to the LLM —
field types (`integer`, `number`, `boolean`) are inferred from your attribute
declarations rather than defaulting to `string`.

### dry-validation (native contract)

Pass a `Dry::Validation::Contract` subclass directly. The JSON schema is built
automatically from the contract's params block, and validation runs through the
contract itself — no bridge required.

```ruby
require "dry-validation"

class PersonContract < Dry::Validation::Contract
  params do
    required(:name).filled(:string)
    required(:email).filled(:string)
  end

  rule(:email) { key.failure("must include @") unless value.include?("@") }
end

instructor = RubyLLM::Instructor::Client.new

person = instructor.chat(
  model: "gpt-4o",
  response_model: PersonContract,
  prompt: "Sal Scotto, sal@example.com"
)

person.name    # => "Sal Scotto"
person.email   # => "sal@example.com"
person.frozen? # => true  (returned as a Data object)
```

The returned instance is a `Data.define` value object with one member per contract
field — immutable and frozen.

#### Duck-typed bridge (alternative)

If you prefer to keep your domain class, bridge dry-validation's result to
`valid?` / `errors.full_messages` and it works the same way:

```ruby
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

  DryErrors = Struct.new(:result) do
    def full_messages
      return [] unless result
      result.errors.to_h.flat_map { |field, msgs| msgs.map { |m| "#{field} #{m}" } }
    end
  end
end
```

### Ruby `Data.define` (immutable value object)

Members are inferred automatically. The returned instance is frozen.

```ruby
Person = Data.define(:name, :email)

person = instructor.chat(
  model: "gpt-4o",
  response_model: Person,
  prompt: "Sal Scotto, sal@example.com"
)

person.name    # => "Sal Scotto"
person.frozen? # => true
```

### Struct

```ruby
Address = Struct.new(:street, :city, :zip, keyword_init: true)

address = instructor.chat(
  model: "gpt-4o",
  response_model: Address,
  prompt: "Ship to: 123 Main St, Springfield, 62701"
)

address.city # => "Springfield"
```

### Custom schema

If your class defines `to_json_schema` (class or instance method), the adapter uses
it directly instead of introspecting setters — giving you full control over the schema
sent to the LLM while keeping the normal hydration and validation flow.

```ruby
class Article
  attr_accessor :title, :status

  def self.to_json_schema
    {
      name: "article",
      schema: {
        type: "object",
        properties: {
          title:  { type: "string", description: "Article headline" },
          status: { type: "string", enum: %w[draft published archived] }
        },
        required: %w[title status]
      }
    }
  end
end
```

## Streaming

Pass a `stream:` proc to receive chunks as they arrive. The final hydrated object
is still returned once the response completes.

```ruby
instructor.chat(
  model: "gpt-4o",
  response_model: UserProfile,
  prompt: "...",
  stream: ->(chunk) { print chunk.content }
)
```

## Extraction mode: schema vs tools

By default `ruby_llm-instructor` uses `mode: :schema` — structured output via the
provider's native JSON schema constraint. Pass `mode: :tools` to use function
calling instead, which works with older models that pre-date structured output.

```ruby
# Default — structured output (recommended for modern models)
instructor.chat(model: "gpt-4o", response_model: MyModel, prompt: "...", mode: :schema)

# Function-calling fallback — works with older models
instructor.chat(model: "gpt-3.5-turbo", response_model: MyModel, prompt: "...", mode: :tools)
```

## Auto-retry on validation failure

When the LLM returns data that fails `valid?`, `ruby_llm-instructor` feeds the
error messages back to the model and asks for a corrected response — up to
`max_retries` times (default: 3). If all retries are exhausted, a `RuntimeError`
is raised.

```ruby
instructor.chat(
  model: "gpt-4o",
  response_model: LeadCapture,
  prompt: "...",
  max_retries: 5
)
```

## One model, any provider

The `model:` string is passed straight through to `ruby_llm`:

```ruby
# OpenAI
instructor.chat(model: "gpt-4o", ...)

# Anthropic
instructor.chat(model: "claude-3-5-sonnet", ...)

# Ollama (local)
instructor.chat(model: "llama3", ...)
```

## What's in v0.1

- All `ruby_llm`-supported providers (OpenAI, Anthropic, Gemini, Ollama, …)
- Response models: PORO, ActiveModel, native dry-validation contract, duck-typed dry-v bridge, `Data.define`, `Struct`, custom `to_json_schema`
- Type inference from `ActiveModel::Attributes` (integer, number, boolean)
- Required vs. optional fields from presence validators
- Automatic retry-on-validation-failure with corrective prompt
- Streaming via `stream:` proc
- Function-calling fallback via `mode: :tools`

## Development

```bash
bin/setup
bundle exec rspec
```

## License

MIT
