# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Google" do
  let(:provider) { LLM.google(key: "TOKEN") }
  let(:model) { "gemini-2.5-flash" }
  let(:url) { "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=TOKEN" }
  let(:response_body) do
    {
      candidates: [
        {
          content: {parts: [{text: "pong"}], role: "model"},
          finishReason: "STOP",
          index: 0
        }
      ],
      usageMetadata: {promptTokenCount: 1, candidatesTokenCount: 1, totalTokenCount: 2},
      modelVersion: model
    }
  end
  let(:schema_builder) { provider.schema }
  let(:schema) do
    schema_builder.object(
      name: schema_builder.string.required
    )
  end

  before do
    stub_request(:post, url)
      .to_return(
        status: 200,
        body: LLM.json.dump(response_body),
        headers: {"Content-Type" => "application/json"}
      )
  end

  context "when given temperature" do
    before { provider.complete("ping", model:, temperature: 0.3) }

    it "sends temperature in generationConfig" do
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        expect(body.dig("generationConfig", "temperature")).to eq(0.3)
      }
    end
  end

  context "when given temperature and schema" do
    before { provider.complete("Return JSON.", model:, temperature: 0.3, schema:) }

    it "merges temperature and schema into generationConfig" do
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        config = body["generationConfig"]
        expect(config["temperature"]).to eq(0.3)
        expect(config["response_mime_type"]).to eq("application/json")
        expect(config["response_schema"]).to include("type" => "object", "properties" => include("name" => anything))
      }
    end
  end
end
