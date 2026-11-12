# frozen_string_literal: true

require "setup"
require "llm/providers/anthropic"

RSpec.describe "LLM::Anthropic::StreamParser" do
  def sse(*events)
    events.map { "event: #{_1["type"]}\ndata: #{LLM.json.dump(_1)}\n\n" }.join
  end

  def error_event(type, message)
    {"type" => "error", "error" => {"type" => type, "message" => message}}
  end

  let(:message_start) do
    {"type" => "message_start", "message" => {"id" => "msg_1", "role" => "assistant", "content" => []}}
  end
  let(:text_start) do
    {"type" => "content_block_start", "index" => 0, "content_block" => {"type" => "text", "text" => +""}}
  end
  let(:text_delta) do
    {"type" => "content_block_delta", "index" => 0, "delta" => {"type" => "text_delta", "text" => "Hello"}}
  end

  context "when an SSE body has text before an error event" do
    let(:sink) { +"" }
    let(:decoder) do
      LLM::Provider::Transport::HTTP::StreamDecoder.new(LLM::Anthropic::StreamParser.new(sink))
    end

    {
      "rate_limit_error" => LLM::RateLimitError,
      "authentication_error" => LLM::UnauthorizedError,
      "invalid_request_error" => LLM::InvalidRequestError,
      "api_error" => LLM::ServerError,
      "overloaded_error" => LLM::ServerError,
      "unknown_error" => LLM::Error
    }.each do |type, error_class|
      it "raises #{error_class} for #{type}" do
        body = sse(message_start, text_start, text_delta, error_event(type, "Nope"))
        expect { decoder << body }.to raise_error(error_class, "#{type}: Nope") { expect(_1.class).to eq(error_class) }
      end
    end

    it "has already sent the text before the error to the sink" do
      body = sse(message_start, text_start, text_delta, error_event("overloaded_error", "Overloaded"))
      expect { decoder << body }.to raise_error(LLM::ServerError)
      expect(sink).to eq("Hello")
    end
  end

  context "when an SSE body has a tool call before an error event" do
    let(:stream) do
      Class.new(LLM::Stream) do
        def calls = @calls ||= []

        def on_tool_call(tool, error)
          calls << tool.name
        end
      end.new
    end
    let(:decoder) do
      LLM::Provider::Transport::HTTP::StreamDecoder.new(LLM::Anthropic::StreamParser.new(stream))
    end
    let(:tool_events) do
      [
        {"type" => "content_block_start", "index" => 0,
         "content_block" => {"type" => "tool_use", "id" => "toolu_1", "name" => "search", "input" => {}}},
        {"type" => "content_block_delta", "index" => 0,
         "delta" => {"type" => "input_json_delta", "partial_json" => "{\"q\":\"x\"}"}},
        {"type" => "content_block_stop", "index" => 0}
      ]
    end

    it "raises after the tool call has been sent to the stream" do
      body = sse(message_start, *tool_events, error_event("overloaded_error", "Overloaded"))
      expect { decoder << body }.to raise_error(LLM::ServerError)
      expect(stream.calls).to eq(["search"])
    end
  end

  context "when a streamed completion gets an error event after HTTP 200" do
    let(:provider) { LLM.anthropic(key: "TOKEN") }
    let(:tracer) { LLM::Tracer::Telemetry.new(provider) }
    let(:span) { tracer.spans.last }

    before do
      provider.tracer = tracer
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          body: sse(message_start, text_start, text_delta, error_event("rate_limit_error", "Slow down")),
          headers: {"Content-Type" => "text/event-stream"}
        )
    end

    it "raises the typed error from Provider#complete" do
      expect { provider.complete("hi", stream: +"") }
        .to raise_error(LLM::RateLimitError, "rate_limit_error: Slow down")
    end

    it "finishes the request span with the error" do
      expect { provider.complete("hi", stream: +"") }.to raise_error(LLM::RateLimitError)
      expect(span.attributes["error.type"]).to eq("LLM::RateLimitError")
      expect(span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    end
  end
end
