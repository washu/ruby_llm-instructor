module RubyLLM
  module Instructor
    module Adapters
      class RubyLlmSchemaAdapter
        def initialize(model_klass)
          @klass = model_klass
        end

        def build_schema
          return build_dry_contract_schema if dry_contract?
          return @klass.to_json_schema if @klass.respond_to?(:to_json_schema)
          return @klass.new.to_json_schema if @klass.method_defined?(:to_json_schema)

          attrs = attribute_definitions

          RubyLLM::Schema.create do
            attrs.each do |name, type, required|
              opts = { required: required, description: "Extracted value for #{name}" }
              case type
              when :integer then integer name, **opts
              when :number  then number  name, **opts
              when :boolean then boolean name, **opts
              else               string  name, **opts
              end
            end
          end
        end

        private

        def attribute_definitions
          if @klass.respond_to?(:members)
            @klass.members.map { |m| [m.to_sym, :string, true] }
          elsif @klass.respond_to?(:attribute_types)
            required = presence_validated_fields
            @klass.attribute_types.filter_map do |name, type|
              next if name == "id"
              [name.to_sym, map_active_model_type(type), required.include?(name)]
            end
          else
            @klass.instance_methods(false)
                  .select { |m| m.to_s.end_with?("=") }
                  .map    { |m| [m.to_s.chomp("=").to_sym, :string, true] }
          end
        end

        def map_active_model_type(type)
          case type.type
          when :integer         then :integer
          when :float, :decimal then :number
          when :boolean         then :boolean
          else                       :string
          end
        end

        def dry_contract?
          Utils.dry_contract?(@klass)
        end

        def build_dry_contract_schema
          raw = @klass.schema.json_schema
          { name: "response", schema: raw.reject { |k, _| k.to_s == "$schema" } }
        end

        def presence_validated_fields
          return [] unless @klass.respond_to?(:_validators)

          @klass._validators.select { |_, validators|
            validators.any? { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
          }.keys.map(&:to_s)
        end
      end
    end
  end
end
