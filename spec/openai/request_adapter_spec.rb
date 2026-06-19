# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::OpenAI" do
  let(:provider) { LLM.openai(key: "TOKEN") }
  let(:url) { "https://api.openai.com/v1/chat/completions" }
  let(:response_body) do
    {
      id: "chatcmpl_123",
      object: "chat.completion",
      created: 1,
      model: provider.default_model,
      choices: [{index: 0, message: {role: "assistant", content: "pong"}, finish_reason: "stop"}],
      usage: {prompt_tokens: 1, completion_tokens: 1, total_tokens: 2}
    }
  end

  context "when given temperature" do
    before do
      stub_request(:post, url)
        .to_return(
          status: 200,
          body: LLM.json.dump(response_body),
          headers: {"Content-Type" => "application/json"}
        )
      provider.complete("ping", temperature: 0.3)
    end

    it "sends temperature in the request body" do
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        expect(body["temperature"]).to eq(0.3)
      }
    end
  end
end
