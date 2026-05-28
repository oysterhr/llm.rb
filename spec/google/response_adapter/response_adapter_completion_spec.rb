# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Google::ResponseAdapter::Completion" do
  let!(:provider) { LLM.google(key: "test") }
  let(:body) { LLM::Object.from(candidates: [], usageMetadata:, modelVersion: "gemini-2.5-flash", responseId:) }
  let(:http_response) { Struct.new(:body).new(body) }
  let(:response) { LLM::Response.new(http_response) }
  let(:completion) { LLM::Google::ResponseAdapter.adapt(response, type: :completion) }

  context "when responseId is present" do
    let(:usageMetadata) { nil }
    let(:responseId) { "google-response-123" }

    it "returns the response id" do
      expect(completion.id).to eq("google-response-123")
    end
  end

  context "when responseId is missing" do
    let(:usageMetadata) { nil }
    let(:responseId) { nil }

    it "returns nil" do
      expect(completion.id).to be_nil
    end
  end
end
