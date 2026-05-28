# frozen_string_literal: true

require "setup"

RSpec.describe LLM::MCP::Mailbox do
  describe "#pop" do
    it "returns nil when empty" do
      expect(described_class.new.pop).to be_nil
    end

    it "returns the next enqueued message" do
      mailbox = described_class.new
      mailbox << {"id" => 1, "result" => {"ok" => true}}
      expect(mailbox.pop).to eq({"id" => 1, "result" => {"ok" => true}})
    end
  end
end
