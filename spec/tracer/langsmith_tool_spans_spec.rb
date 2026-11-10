# frozen_string_literal: true

require "setup"

RSpec.describe "LangSmith spans started during a tool call" do
  let(:openai) do
    Class.new do
      def initialize
        @host = "api.openai.com"
        @port = 443
      end
    end
  end
  let(:turn_span_id) { "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa" }
  let(:agent_tracer) { LLM::Tracer::Langsmith.new(LLM::OpenAI.new, parent_span_id: turn_span_id) }
  let(:retrieval_tracer) { LLM::Tracer::Langsmith.new(LLM::OpenAI.new, parent_span_id: turn_span_id) }

  before { stub_const("LLM::OpenAI", openai) }

  around { |example| Fiber.new(storage: {}) { example.run }.resume }

  def tool(name, &body)
    LLM::Function.new(name).tap do |fn|
      fn.id = "call_#{name}"
      fn.arguments = {}
      fn.model = "gpt-4.1"
      fn.tracer = agent_tracer
      fn.define { body.call }
    end
  end

  def retrieve
    retrieval_tracer.on_request_start(operation: "retrieval").tap(&:finish)
  end

  def tool_span(name)
    agent_tracer.spans.find { _1.name == "execute_tool #{name}" }
  end

  def run_id(name)
    tool_span(name).attributes["langsmith.span.id"]
  end

  def parent_of(span)
    span.attributes["langsmith.span.parent_id"]
  end

  it "gives the tool span a LangSmith run id of its own, parented on the turn" do
    tool("search") { nil }.call

    expect(run_id("search")).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    expect(parent_of(tool_span("search"))).to eq(turn_span_id)
  end

  it "parents a span another tracer starts during the call on the tool span" do
    span = nil
    tool("search") { span = retrieve }.call

    expect(parent_of(span)).to eq(run_id("search"))
  end

  it "parents spans started in a fiber the tool starts on the tool span" do
    span = nil
    tool("search") { span = Fiber.new { retrieve }.resume }.call

    expect(parent_of(span)).to eq(run_id("search"))
  end

  it "parents spans started in a thread the tool starts on the tool span" do
    span = nil
    tool("search") { span = Thread.new { retrieve }.value }.call

    expect(parent_of(span)).to eq(run_id("search"))
  end

  it "keeps the tracer's parent for spans started outside a tool call" do
    expect(parent_of(retrieve)).to eq(turn_span_id)
  end

  it "restores the tracer's parent after the tool call returns" do
    tool("search") { nil }.call

    expect(parent_of(retrieve)).to eq(turn_span_id)
  end

  it "restores the tracer's parent after the tool body raises" do
    tool("search") { raise "boom" }.call

    expect(parent_of(retrieve)).to eq(turn_span_id)
  end

  it "restores the tracer's parent after a tool call error" do
    span = agent_tracer.on_tool_start(id: "call_1", name: "search", arguments: {}, model: "gpt-4.1")
    agent_tracer.on_tool_error(ex: RuntimeError.new("boom"), span:)

    expect(parent_of(retrieve)).to eq(turn_span_id)
  end

  it "keeps concurrent tool calls apart" do
    spans = {}
    threads = %w[kb sourcebook].map do |name|
      Thread.new { tool(name) { spans[name] = retrieve }.call }
    end
    threads.each(&:join)

    expect(spans.transform_values { parent_of(_1) }).to eq("kb" => run_id("kb"), "sourcebook" => run_id("sourcebook"))
  end

  context "when a tool runs inside another tool's call" do
    it "parents the inner tool span on the outer tool" do
      tool("outer") { tool("inner") { nil }.call }.call

      expect(parent_of(tool_span("inner"))).to eq(run_id("outer"))
    end

    it "parents spans on the inner tool, then on the outer tool again" do
      spans = {}
      tool("outer") do
        tool("inner") { spans[:inner] = retrieve }.call
        spans[:outer] = retrieve
      end.call

      expect(parent_of(spans[:inner])).to eq(run_id("inner"))
      expect(parent_of(spans[:outer])).to eq(run_id("outer"))
    end
  end

  describe "LLM::Tracer.with_span_label" do
    it "appends the label to request span names started in the block" do
      span = LLM::Tracer.with_span_label("BR") { retrieve }

      expect(span.name).to eq("retrieval BR")
    end

    it "labels spans started in a fiber the block starts" do
      span = LLM::Tracer.with_span_label("BR") { Fiber.new { retrieve }.resume }

      expect(span.name).to eq("retrieval BR")
    end

    it "keeps the plain name without a label" do
      expect(retrieve.name).to eq("retrieval")
    end

    it "keeps the plain name for a blank label" do
      span = LLM::Tracer.with_span_label(" ") { retrieve }

      expect(span.name).to eq("retrieval")
    end

    it "restores the outer label after a nested block" do
      span = LLM::Tracer.with_span_label("BR") do
        LLM::Tracer.with_span_label("MX") { nil }
        retrieve
      end

      expect(span.name).to eq("retrieval BR")
    end

    it "keeps labels of concurrent threads apart" do
      names = %w[BR MX].to_h do |code|
        [code, Thread.new { LLM::Tracer.with_span_label(code) { retrieve.name } }]
      end.transform_values(&:value)

      expect(names).to eq("BR" => "retrieval BR", "MX" => "retrieval MX")
    end

    it "does not label tool spans" do
      LLM::Tracer.with_span_label("BR") { tool("search") { nil }.call }

      expect(tool_span("search")).not_to be_nil
    end
  end
end
