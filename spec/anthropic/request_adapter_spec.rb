# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Anthropic" do
  let(:provider) { LLM.anthropic(key: "TOKEN") }
  let(:url) { "https://api.anthropic.com/v1/messages" }
  let(:response_body) do
    {
      id: "msg_123",
      type: "message",
      role: "assistant",
      model: provider.default_model,
      content: [{type: "text", text: "pong"}],
      usage: {input_tokens: 1, output_tokens: 1}
    }
  end

  context "when given system messages" do
    let(:prompt) do
      LLM::Prompt.new(provider) do
        system "Be terse."
        user "ping"
      end
    end

    before do
      stub_request(:post, url)
        .to_return(
          status: 200,
          body: LLM.json.dump(response_body),
          headers: {"Content-Type" => "application/json"}
        )
      provider.chat(prompt)
    end

    it "sends them in the top-level system field" do
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        expect(body["system"]).to eq([{"type" => "text", "text" => "Be terse."}])
        expect(body["messages"]).to eq(
          [{"role" => "user", "content" => [{"type" => "text", "text" => "ping"}]}]
        )
      }
    end
  end
end
