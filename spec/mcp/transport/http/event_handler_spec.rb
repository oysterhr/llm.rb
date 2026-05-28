# frozen_string_literal: true

require "setup"
require "llm/mcp"

RSpec.describe LLM::MCP::Transport::HTTP::EventHandler do
  let(:messages) { [] }
  let(:handler) { described_class.new { messages << _1 } }
  let(:parser) do
    LLM::EventStream::Parser.new.tap do |instance|
      instance.register(handler)
    end
  end

  after { parser.free }

  it "parses a single-line sse data event" do
    parser << "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n"
    expect(messages).to eq([{"jsonrpc" => "2.0", "id" => 1, "result" => {}}])
  end

  it "joins multiline data payloads before parsing" do
    parser << "data: {\"jsonrpc\":\"2.0\",\n"
    parser << "data: \"id\":1,\n"
    parser << "data: \"result\":{}}\n\n"
    expect(messages).to eq([{"jsonrpc" => "2.0", "id" => 1, "result" => {}}])
  end
end
