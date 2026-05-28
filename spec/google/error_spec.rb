# frozen_string_literal: true

require "setup"
require "llm/providers/google"

RSpec.describe LLM::Google::ErrorHandler do
  subject(:handler) { described_class.new(tracer, span, response) }

  let(:tracer) { LLM::Tracer::Null.new(nil) }
  let(:span) { nil }

  context "when response is a server error" do
    let(:response) { Net::HTTPServerError.new("1.1", "500", "Internal Server Error") }

    before { allow(response).to receive(:body).and_return("{}") }

    it "raises LLM::ServerError" do
      expect { handler.raise_error! }.to raise_error(LLM::ServerError)
    end
  end

  context "when response is rate limited" do
    let(:response) { Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests") }

    before { allow(response).to receive(:body).and_return("{}") }

    it "raises LLM::RateLimitError" do
      expect { handler.raise_error! }.to raise_error(LLM::RateLimitError)
    end
  end

  context "when response is a bad request with an invalid API key" do
    let(:response) { Net::HTTPBadRequest.new("1.1", "400", "Bad Request") }
    let(:body) do
      LLM::Object.from(
        "error" => {
          "details" => [
            {"reason" => "API_KEY_INVALID"}
          ]
        }
      )
    end

    before { allow(response).to receive(:body).and_return(body) }

    it "raises LLM::UnauthorizedError" do
      expect { handler.raise_error! }.to raise_error(LLM::UnauthorizedError)
    end
  end

  context "when response is a bad request with another error" do
    let(:response) { Net::HTTPBadRequest.new("1.1", "400", "Bad Request") }

    before { allow(response).to receive(:body).and_return('{"error":{"details":[{"reason":"OTHER"}]}}') }

    it "raises LLM::Error" do
      expect { handler.raise_error! }.to raise_error(LLM::Error)
    end
  end
end
