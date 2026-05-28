# frozen_string_literal: true

require_relative "setup"

RSpec.describe LLM::Tool::Param do
  context "when given enum values for a param" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "create-image"
        description "Create a generated image"
        param :provider, String, "The provider", enum: %w[openai google], default: "google"
      end
    end

    subject(:provider_param) { tool.function.params.properties[:provider] }

    it "serializes the enum as a flat array" do
      expect(provider_param.to_h[:enum]).to eq(%w[openai google])
    end

    it "preserves the default value" do
      expect(provider_param.to_h[:default]).to eq("google")
    end
  end

  context "when given Enum[...] as the param type" do
    let(:tool) do
      stub_const("EnumTool", Module.new)
      EnumTool.const_set(:Enum, LLM::Schema::Enum)
      EnumTool.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
        class Tool < LLM::Tool
          name "create-image"
          description "Create a generated image"
          param :provider, Enum["openai", "google"], "The provider"
        end
      RUBY
      EnumTool::Tool
    end

    subject(:provider_param) { tool.function.params.properties[:provider] }

    it "builds a string param with enum values" do
      expect(provider_param).to be_a(LLM::Schema::String)
      expect(provider_param.to_h[:enum]).to eq(%w[openai google])
    end
  end

  context "when using parameter as an alias of param" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "weather"
        description "Lookup the weather for a location"
        parameter :location, String, "A location"
      end
    end

    subject(:location_param) { tool.function.params.properties[:location] }

    it "defines the parameter" do
      expect(location_param).to be_a(LLM::Schema::String)
    end

    it "preserves the description" do
      expect(location_param.description).to eq("A location")
    end
  end

  context "when required fields are declared separately" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "weather"
        description "Lookup the weather for a location"
        parameter :location, String, "A location"
        required %i[location]
      end
    end

    subject(:schema) { tool.function.params }

    it "marks the parameter as required" do
      expect(schema.properties[:location]).to be_required
    end

    it "serializes the required field list" do
      expect(schema.to_h[:required]).to eq([:location])
    end
  end
end
