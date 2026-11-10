# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer::Telemetry do
  let(:provider) { LLM::OpenAI.new }
  let(:tracer) { described_class.new(provider) }
  let(:openai) do
    Class.new do
      def initialize
        @host = "api.openai.com"
        @port = 443
      end
    end
  end

  before { stub_const("LLM::OpenAI", openai) }

  describe "#on_request_start" do
    context "when given a chat operation" do
      subject { tracer.on_request_start(operation: "chat", model: "test-model") }
      it { is_expected.to be_a(OpenTelemetry::SDK::Trace::Span) }
    end

    context "when given a retrieval operation" do
      subject { tracer.on_request_start(operation: "retrieval") }
      it { is_expected.to be_a(OpenTelemetry::SDK::Trace::Span) }
    end
  end

  describe "#on_request_finish" do
    context "when given a chat operation" do
      let(:usage) { LLM::Usage.new(input_tokens: 1, output_tokens: 2) }
      let(:res) { double("LLM::Response", id: "res_123", usage:, service_tier: "default", system_fingerprint: "yabadabadoo") }
      let(:span) { tracer.on_request_start(operation: "chat", model: "test-model") }
      let(:attributes) { {"gen_ai.operation.name" => "chat", "gen_ai.request.model" => "test-model"} }

      before { tracer.on_request_finish(operation: "chat", model: "test-model", res:, span:) }

      it "finishes the span" do
        expect(span.name).to eq("chat test-model")
        expect(span.attributes).to match(hash_including(attributes))
      end
    end

    context "when given a retrieval operation" do
      let(:res) { double("LLM::Response", size: 1, has_more: false) }
      let(:span) { tracer.on_request_start(operation: "retrieval") }
      let(:attributes) { {"gen_ai.operation.name" => "retrieval"} }

      before { tracer.on_request_finish(operation: "retrieval", res:, span:) }

      it "finishes the span" do
        expect(span.name).to eq("retrieval")
        expect(span.attributes).to match(hash_including(attributes))
      end
    end
  end

  describe "#on_request_error" do
    let(:ex) { RuntimeError.new("yabadabadoo") }
    let(:span) { tracer.on_request_start(operation: "chat", model: "test-model") }

    before { tracer.on_request_error(ex:, span:) }

    it "records error.type" do
      expect(tracer.spans.last.attributes["error.type"]).to eq("RuntimeError")
    end
  end

  describe "#on_tool_start" do
    subject { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }
    it { is_expected.to be_a(OpenTelemetry::SDK::Trace::Span) }
  end

  describe "#on_tool_finish" do
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }
    let(:result) { LLM::Function::Return.new("call_1", "tool", {ok: true}) }

    before { tracer.on_tool_finish(result:, span:) }

    it "finishes the span" do
      expect(span.name).to eq("execute_tool tool")
      expect(span.attributes["gen_ai.tool.call.id"]).to eq("call_1")
    end
  end

  describe "#on_tool_error" do
    let(:ex) { RuntimeError.new("yabadabadoo") }
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }

    before { tracer.on_tool_error(ex:, span:) }

    it "records error.type" do
      expect(tracer.spans.last.attributes["error.type"]).to eq("RuntimeError")
    end
  end

  describe "#spans" do
    let(:tracer) { described_class.new(provider, exporter:) }
    let(:exporter) do
      Class.new do
        def export(*) = OpenTelemetry::SDK::Trace::Export::SUCCESS
        def shutdown(*) = OpenTelemetry::SDK::Trace::Export::SUCCESS
        def force_flush(*) = OpenTelemetry::SDK::Trace::Export::SUCCESS
      end.new
    end

    it "returns an empty array" do
      expect(tracer.spans).to eq([])
    end
  end

  describe "#flush!" do
    it "returns nil" do
      expect(tracer.flush!).to be_nil
    end
  end

  context "when given a tracer_provider" do
    let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }
    let(:tracer_provider) do
      OpenTelemetry::SDK::Trace::TracerProvider.new.tap do |tracer_provider|
        tracer_provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))
      end
    end
    let(:tracer) { described_class.new(provider, tracer_provider:) }

    it "exports spans through the given provider" do
      span = tracer.on_request_start(operation: "chat", model: "test-model")
      tracer.on_request_error(ex: RuntimeError.new("yabadabadoo"), span:)

      expect(exporter.finished_spans.map(&:name)).to eq(["chat test-model"])
    end

    it "does not build a span processor of its own" do
      allow(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).to receive(:new).and_call_original
      tracer

      expect(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).not_to have_received(:new)
    end

    it "does not start a thread per tracer" do
      tracer_provider
      threads_before = Thread.list.size
      20.times { described_class.new(provider, tracer_provider:) }

      expect(Thread.list.size).to eq(threads_before)
    end

    it "ignores the exporter option" do
      other_exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
      tracer = described_class.new(provider, tracer_provider:, exporter: other_exporter)
      tracer.emit_chain_span(span_id: "s-1", name: "chatbot.turn", started_at: Time.now, finished_at: Time.now)

      expect(exporter.finished_spans.size).to eq(1)
      expect(other_exporter.finished_spans).to be_empty
    end
  end

  context "when not given a tracer_provider" do
    it "builds its own provider with a batch span processor" do
      allow(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).to receive(:new).and_call_original
      tracer

      expect(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).to have_received(:new).once
    end
  end

  describe "#emit_chain_span" do
    let(:span_id) { "eeeeeeee-5555-4555-8555-eeeeeeeeeeee" }
    let(:started_at) { Time.at(1_700_000_000) }
    let(:finished_at) { Time.at(1_700_000_010) }

    it "returns a finished span with the given name" do
      span = tracer.emit_chain_span(
        span_id:, name: "chatbot.turn",
        started_at:, finished_at:
      )
      expect(span).to be_a(OpenTelemetry::SDK::Trace::Span)
      expect(span.name).to eq("chatbot.turn")
    end

    it "stamps langsmith.span.id and langsmith.span.kind=chain" do
      tracer.emit_chain_span(
        span_id:, name: "chatbot.turn",
        started_at:, finished_at:
      )
      attrs = tracer.spans.last.attributes
      expect(attrs).to include(
        "langsmith.span.id" => span_id,
        "langsmith.span.kind" => "chain"
      )
    end

    it "stamps custom attributes and skips nil values" do
      tracer.emit_chain_span(
        span_id:, name: "chatbot.turn",
        started_at:, finished_at:,
        attributes: {"custom.key" => "value", "custom.nil" => nil}
      )
      attrs = tracer.spans.last.attributes
      expect(attrs).to include("custom.key" => "value")
      expect(attrs).not_to have_key("custom.nil")
    end

    it "stamps metadata as langsmith.metadata.* and serializes complex values to JSON" do
      tracer.emit_chain_span(
        span_id:, name: "chatbot.turn",
        started_at:, finished_at:,
        metadata: {turn_id: "t-1", payload: {a: 1}, skipped: nil}
      )
      attrs = tracer.spans.last.attributes
      expect(attrs).to include(
        "langsmith.metadata.turn_id" => "t-1",
        "langsmith.metadata.payload" => LLM.json.dump({a: 1})
      )
      expect(attrs).not_to have_key("langsmith.metadata.skipped")
    end

    it "drops langsmith.span.parent_id passed via attributes (synthetic root invariant)" do
      tracer.emit_chain_span(
        span_id:, name: "chatbot.turn",
        started_at:, finished_at:,
        attributes: {"langsmith.span.parent_id" => "should-be-dropped"}
      )
      attrs = tracer.spans.last.attributes
      expect(attrs).not_to have_key("langsmith.span.parent_id")
    end

    it "honors the provided start and end timestamps" do
      tracer.emit_chain_span(
        span_id:, name: "chatbot.turn",
        started_at:, finished_at:
      )
      span_data = tracer.spans.last
      expect(span_data.start_timestamp).to eq((started_at.to_r * 1_000_000_000).to_i)
      expect(span_data.end_timestamp).to eq((finished_at.to_r * 1_000_000_000).to_i)
    end
  end
end
