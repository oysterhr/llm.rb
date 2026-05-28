# frozen_string_literal: true

require_relative "setup"

RSpec.describe LLM::Buffer do
  let(:provider) { LLM.openai(key: "test") }
  let(:buffer) { described_class.new(provider) }

  describe "#rindex" do
    before do
      buffer << LLM::Message.new("user", "first")
      buffer << LLM::Message.new("assistant", "second")
      buffer << LLM::Message.new("user", "third")
    end

    it "returns the last matching index" do
      expect(buffer.rindex(&:user?)).to eq(2)
    end

    it "returns nil when no message matches" do
      expect(buffer.rindex(&:system?)).to be_nil
    end
  end
end
