# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Anthropic::ResponseAdapter::Completion" do
  let(:body) { LLM::Object.from(content: [], usage:, model: "test-model") }
  let(:http_response) { Struct.new(:body).new(body) }
  let(:response) { LLM::Response.new(http_response) }
  let(:completion) { LLM::Anthropic::ResponseAdapter.adapt(response, type: :completion) }

  context "when usage is nil" do
    let(:usage) { nil }

    it "returns 0 for input tokens" do
      expect(completion.input_tokens).to eq(0)
    end

    it "returns 0 for output tokens" do
      expect(completion.output_tokens).to eq(0)
    end

    it "returns 0 for total tokens" do
      expect(completion.total_tokens).to eq(0)
    end
  end

  context "when usage is provided" do
    let(:usage) { LLM::Object.from(input_tokens: 10, output_tokens: 20) }

    it "returns correct input tokens" do
      expect(completion.input_tokens).to eq(10)
    end

    it "returns correct output tokens" do
      expect(completion.output_tokens).to eq(20)
    end

    it "returns correct total tokens" do
      expect(completion.total_tokens).to eq(30)
    end
  end

  describe "#choices" do
    let(:usage) { nil }

    context "when the response has text blocks around a tool call" do
      let(:body) do
        LLM::Object.from(
          role: "assistant", model: "test-model", usage:,
          content: [
            {type: "text", text: "First part. "},
            {type: "tool_use", id: "toolu_1", name: "search", input: {q: "x"}},
            {type: "text", text: "Second part."}
          ]
        )
      end

      it "joins all text blocks into one choice" do
        expect(completion.choices.map(&:content)).to eq(["First part. Second part."])
      end

      it "attaches the tool calls once" do
        completion.choices => [choice]
        expect(choice.extra[:tool_calls].map { _1[:id] }).to eq(["toolu_1"])
      end
    end

    context "when the response has a tool call and no text" do
      let(:body) do
        LLM::Object.from(
          role: "assistant", model: "test-model", usage:,
          content: [{type: "tool_use", id: "toolu_1", name: "search", input: {}}]
        )
      end

      it "returns one choice with empty text" do
        expect(completion.choices.map(&:content)).to eq([""])
      end
    end
  end
end
