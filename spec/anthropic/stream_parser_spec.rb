# frozen_string_literal: true

require "setup"
require "llm/providers/anthropic"

RSpec.describe "LLM::Anthropic::StreamParser" do
  let(:parser) { LLM::Anthropic::StreamParser.new(+"") }

  context "when the stream sends an error event" do
    let(:chunk) do
      {"type" => "error", "error" => {"type" => "overloaded_error", "message" => "Overloaded"}}
    end

    it "raises LLM::ServerError with the error type and message" do
      expect { parser.parse!(chunk) }
        .to raise_error(LLM::ServerError, "overloaded_error: Overloaded")
    end
  end
end
