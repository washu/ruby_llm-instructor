# frozen_string_literal: true

module RubyLLM
  module Instructor
    class Client
      VALID_MODES = %i[schema tools].freeze

      def chat(model:, response_model:, prompt:, max_retries: 3, stream: nil, mode: :schema)
        unless VALID_MODES.include?(mode)
          raise ArgumentError, "Unknown mode #{mode.inspect}. Valid modes are: #{VALID_MODES.join(', ')}"
        end

        compiled_schema = Adapters::RubyLlmSchemaAdapter.new(response_model).build_schema
        current_prompt = prompt
        retries = 0

        begin
          session = RubyLLM.chat(model: model)
          response = mode == :tools ? via_tools(session, compiled_schema, current_prompt, stream)
                                    : via_schema(session, compiled_schema, current_prompt, stream)
          parsed_data = response.content

          unless parsed_data.is_a?(Hash)
            raise ValidationError,
                  "Expected a structured JSON object matching the schema, " \
                  "got #{parsed_data.class} (#{parsed_data.inspect[0, 200]})"
          end

          errors = validate_payload(response_model, parsed_data)
          raise ValidationError, errors.join(", ") if errors.any?

          build_instance(response_model, parsed_data)

        rescue ValidationError => e
          if retries < max_retries
            retries += 1
            current_prompt = "Original task: #{prompt}\n\n" \
                             "Your previous response failed validation: #{e.message}. " \
                             "Please fix the data to match the schema exactly."
            retry
          else
            raise ValidationError, "ruby_llm-instructor failed validation after #{max_retries} attempts. Errors: #{e.message}"
          end
        end
      end

      private

      def via_schema(session, schema, prompt, stream)
        session.with_schema(schema).ask(prompt, &stream)
      end

      def via_tools(session, schema, prompt, stream)
        tool = extraction_tool_for(schema)
        session.with_tool(tool, choice: :required, calls: :one).ask(prompt, &stream)
      end

      def extraction_tool_for(schema)
        tool_params = schema.is_a?(Hash) ? (schema[:schema] || schema["schema"] || schema) : schema
        Class.new(RubyLLM::Tool) do
          description "Extract and return the structured data from the text"
          singleton_class.define_method(:name) { "RubyLLMInstructorExtract" }
          params tool_params
          def execute(**args) = halt(args)
        end
      end

      def dry_contract?(klass)
        Utils.dry_contract?(klass)
      end

      def validate_payload(response_model, parsed_data)
        if dry_contract?(response_model)
          result = response_model.new.call(parsed_data.transform_keys(&:to_sym))
          return [] if result.success?
          return result.errors.to_h.flat_map { |field, msgs| msgs.map { |m| "#{field} #{m}" } }
        end

        return [] unless response_model.respond_to?(:new)

        instance = build_instance(response_model, parsed_data)
        return [] unless instance.respond_to?(:valid?) && !instance.valid?

        if instance.respond_to?(:errors) && instance.errors.respond_to?(:full_messages)
          instance.errors.full_messages
        else
          ["Validation failed"]
        end
      end

      def build_instance(response_model, parsed_data)
        if dry_contract?(response_model)
          fields = response_model.schema.key_map.map(&:name).map(&:to_sym)
          return Data.define(*fields).new(**parsed_data.transform_keys(&:to_sym).slice(*fields))
        end

        if response_model.respond_to?(:members)
          kwargs = parsed_data.transform_keys(&:to_sym)
          begin
            response_model.new(**kwargs)
          rescue ArgumentError
            # Positional Struct (no keyword_init:true) — fall back to positional args
            response_model.new(*response_model.members.map { |m| kwargs[m] })
          end
        else
          instance = response_model.new
          parsed_data.each do |key, value|
            instance.send("#{key}=", value) if instance.respond_to?("#{key}=")
          end
          instance
        end
      end
    end
  end
end
