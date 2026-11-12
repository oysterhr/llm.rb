# frozen_string_literal: true

require "setup"
require "llm/providers/openai"

RSpec.describe LLM::OpenAI::Responses::StreamParser do
  let(:stream) do
    Class.new(LLM::Stream) do
      attr_reader :content, :reasoning_content, :calls

      def initialize
        @content = +""
        @reasoning_content = +""
        @calls = []
      end

      def on_content(value)
        @content << value
      end

      def on_reasoning_content(value)
        @reasoning_content << value
      end

      def on_tool_call(fn, error)
        @calls << [fn, error]
      end

      def tool_not_found(fn)
        {id: fn.id, name: fn.name, value: {error: true}}
      end
    end.new
  end

  subject(:parser) { described_class.new(stream) }

  after { parser.free }
  before { LLM::Tool.clear_registry! }

  it "accumulates reasoning summaries and output text deltas" do
    parser.parse!(
      "type" => "response.output_item.added",
      "output_index" => 0,
      "item" => {"id" => "rs_1", "type" => "reasoning", "summary" => []}
    )
    parser.parse!(
      "type" => "response.reasoning_summary_text.delta",
      "output_index" => 0,
      "summary_index" => 0,
      "delta" => "Think"
    )
    parser.parse!(
      "type" => "response.output_item.added",
      "output_index" => 1,
      "item" => {"id" => "msg_1", "type" => "message", "content" => []}
    )
    parser.parse!(
      "type" => "response.content_part.added",
      "output_index" => 1,
      "content_index" => 0,
      "part" => {"type" => "output_text", "text" => +""}
    )
    parser.parse!(
      "type" => "response.output_text.delta",
      "output_index" => 1,
      "content_index" => 0,
      "delta" => "Answer"
    )
    expect(parser.body.dig("output", 0, "summary", 0, "text")).to eq("Think")
    expect(parser.body.dig("output", 1, "content", 0, "text")).to eq("Answer")
    expect(stream.reasoning_content).to eq("Think")
    expect(stream.content).to eq("Answer")
  end

  it "refreshes cached content when an output item is replaced" do
    parser.parse!(
      "type" => "response.output_item.added",
      "output_index" => 0,
      "item" => {"id" => "msg_1", "type" => "message", "content" => []}
    )
    parser.parse!(
      "type" => "response.content_part.added",
      "output_index" => 0,
      "content_index" => 0,
      "part" => {"type" => "output_text", "text" => +""}
    )
    parser.parse!(
      "type" => "response.output_text.delta",
      "output_index" => 0,
      "content_index" => 0,
      "delta" => "A"
    )
    parser.parse!(
      "type" => "response.output_item.done",
      "output_index" => 0,
      "item" => {
        "id" => "msg_1",
        "type" => "message",
        "content" => [{"type" => "output_text", "text" => +"B"}]
      }
    )
    parser.parse!(
      "type" => "response.output_text.delta",
      "output_index" => 0,
      "content_index" => 0,
      "delta" => "C"
    )
    expect(parser.body.dig("output", 0, "content", 0, "text")).to eq("BC")
  end

  it "emits tool calls when response function arguments complete" do
    stream.extra[:tracer] = Object.new
    stream.extra[:model] = "deepseek-chat"
    parser.parse!(
      "type" => "response.output_item.added",
      "output_index" => 0,
      "item" => {
        "id" => "fc_1",
        "type" => "function_call",
        "status" => "in_progress",
        "arguments" => +"",
        "call_id" => "call_1",
        "name" => "missing"
      }
    )
    parser.parse!(
      "type" => "response.function_call_arguments.delta",
      "output_index" => 0,
      "delta" => +"{\"command\""
    )
    parser.parse!(
      "type" => "response.function_call_arguments.done",
      "output_index" => 0,
      "arguments" => "{\"command\":\"date\"}"
    )
    fn, error = stream.calls.fetch(0)
    expect(fn.id).to eq("call_1")
    expect(fn.name).to eq("missing")
    expect(fn.arguments).to eq({"command" => "date"})
    expect(fn.tracer).to equal(stream.extra[:tracer])
    expect(fn.model).to eq("deepseek-chat")
    expect(error).to eq(id: "call_1", name: "missing", value: {error: true})
  end

  def failed_event(code, message)
    {"type" => "response.failed", "response" => {"id" => "resp_1", "status" => "failed", "error" => {"code" => code, "message" => message}}}
  end

  def sse(*events)
    events.map { "event: #{_1["type"]}\ndata: #{LLM.json.dump(_1)}\n\n" }.join
  end

  context "when the response fails inside the stream" do
    {
      "server_error" => LLM::ServerError,
      "server_is_overloaded" => LLM::ServerError,
      "vector_store_timeout" => LLM::ServerError,
      "rate_limit_exceeded" => LLM::RateLimitError,
      "slow_down" => LLM::RateLimitError,
      "invalid_prompt" => LLM::InvalidRequestError,
      "context_length_exceeded" => LLM::ContextWindowError,
      "unknown_code" => LLM::Error
    }.each do |code, error_class|
      it "raises #{error_class} for #{code}" do
        expect { parser.parse!(failed_event(code, "Nope")) }
          .to raise_error(error_class, "#{code}: Nope") { expect(_1.class).to eq(error_class) }
      end
    end

    it "raises after the tool call has been sent to the stream" do
      item = {"id" => "fc_1", "type" => "function_call", "call_id" => "call_1", "name" => "missing", "arguments" => "{}"}
      parser.parse!("type" => "response.output_item.added", "output_index" => 0, "item" => item.merge("arguments" => ""))
      parser.parse!("type" => "response.function_call_arguments.done", "output_index" => 0, "item_id" => "fc_1", "arguments" => "{}")

      expect { parser.parse!(failed_event("server_error", "No healthy upstream")) }.to raise_error(LLM::ServerError)
      expect(stream.calls.map { _1.first.name }).to eq(["missing"])
    end
  end

  context "when the stream sends an error event" do
    it "raises the typed error" do
      expect { parser.parse!("type" => "error", "code" => "rate_limit_exceeded", "message" => "Slow down") }
        .to raise_error(LLM::RateLimitError, "rate_limit_exceeded: Slow down")
    end

    it "reads an error nested under the error key" do
      expect { parser.parse!("type" => "error", "error" => {"code" => "server_error", "message" => "Oops"}) }
        .to raise_error(LLM::ServerError, "server_error: Oops")
    end

    it "uses the error type when the error has no code" do
      expect { parser.parse!("type" => "error", "error" => {"type" => "server_error", "message" => "Oops"}) }
        .to raise_error(LLM::ServerError, "server_error: Oops")
    end
  end

  context "when the response is incomplete" do
    it "keeps the response id and status" do
      parser.parse!("type" => "response.incomplete", "response" => {"id" => "resp_1", "status" => "incomplete", "output" => []})

      expect(parser.body).to include("id" => "resp_1", "status" => "incomplete")
    end
  end

  context "when a streamed response is sent over HTTP" do
    let(:provider) { LLM.openai(key: "TOKEN") }
    let(:tracer) { LLM::Tracer::Telemetry.new(provider) }
    let(:span) { tracer.spans.last }
    let(:created) { {"type" => "response.created", "response" => {"id" => "resp_1", "status" => "in_progress", "output" => []}} }

    before { provider.tracer = tracer }

    def stub_stream(*events)
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: sse(*events), headers: {"Content-Type" => "text/event-stream"})
    end

    context "when the response fails after HTTP 200" do
      before { stub_stream(created, failed_event("server_error", "No healthy upstream")) }

      it "raises the typed error from Responses#create" do
        expect { provider.responses.create("hi", stream: +"") }
          .to raise_error(LLM::ServerError, "server_error: No healthy upstream")
      end

      it "finishes the request span with the error" do
        expect { provider.responses.create("hi", stream: +"") }.to raise_error(LLM::ServerError)
        expect(span.attributes["error.type"]).to eq("LLM::ServerError")
        expect(span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
      end
    end

    context "when the stream ends with no terminal event" do
      before { stub_stream(created) }

      it "raises a server error and finishes the span with it" do
        expect { provider.responses.create("hi", stream: +"") }
          .to raise_error(LLM::ServerError, "stream ended with no terminal event")
        expect(span.attributes["error.type"]).to eq("LLM::ServerError")
      end
    end

    context "when the response is incomplete" do
      let(:incomplete) do
        response = {
          "id" => "resp_1", "status" => "incomplete", "output" => [], "service_tier" => "default",
          "incomplete_details" => {"reason" => "max_output_tokens"}, "usage" => {"input_tokens" => 5, "output_tokens" => 10}
        }
        {"type" => "response.incomplete", "response" => response}
      end

      before { stub_stream(created, incomplete) }

      it "returns the response" do
        expect(provider.responses.create("hi", stream: +"").id).to eq("resp_1")
      end
    end
  end
end
