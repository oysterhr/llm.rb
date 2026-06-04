# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer::Langsmith do
  let(:provider) { LLM::OpenAI.new }
  let(:openai) do
    Class.new do
      def initialize
        @host = "api.openai.com"
        @port = 443
      end
    end
  end

  before { stub_const("LLM::OpenAI", openai) }

  describe "trace attributes" do
    let(:session_id) { "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa" }
    let(:reference_example_id) { "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb" }
    let(:tracer) { described_class.new(provider, session_id:, reference_example_id:) }

    it "uses constructor-provided LangSmith experiment ids" do
      attributes = tracer.send(:trace_attributes, span_kind: "llm")

      expect(attributes).to include(
        "langsmith.trace.session_id" => session_id,
        "langsmith.reference_example_id" => reference_example_id
      )
      expect(attributes.values).not_to include(
        "123792d1-1688-4ba7-944c-491a936cb13f",
        "f96e913a-4258-42f5-85d4-6ab8ce0278ef"
      )
    end

    it "omits langsmith.span.parent_id when no parent_span_id is configured" do
      attributes = tracer.send(:trace_attributes, span_kind: "llm")
      expect(attributes).not_to have_key("langsmith.span.parent_id")
    end

    it "includes langsmith.span.parent_id when parent_span_id is given to the constructor" do
      parent_id = "cccccccc-3333-4333-8333-cccccccccccc"
      tracer = described_class.new(provider, session_id:, reference_example_id:, parent_span_id: parent_id)
      attributes = tracer.send(:trace_attributes, span_kind: "llm")
      expect(attributes).to include("langsmith.span.parent_id" => parent_id)
    end

    it "reflects parent_span_id assigned after construction" do
      parent_id = "dddddddd-4444-4444-8444-dddddddddddd"
      tracer.parent_span_id = parent_id
      attributes = tracer.send(:trace_attributes, span_kind: "llm")
      expect(attributes).to include("langsmith.span.parent_id" => parent_id)
    end
  end
end
