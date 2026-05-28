# frozen_string_literal: true

require "setup"

RSpec.describe LLM::MCP::Router do
  describe "#register" do
    let(:router) { described_class.new }

    it "allocates request ids sequentially" do
      id1, _mailbox1 = router.register
      id2, _mailbox2 = router.register
      expect(id1).to eq(0)
      expect(id2).to eq(1)
    end

    it "returns a mailbox for each request" do
      _id1, mailbox1 = router.register
      _id2, mailbox2 = router.register
      expect(mailbox1).to be_a(LLM::MCP::Mailbox)
      expect(mailbox2).to be_a(LLM::MCP::Mailbox)
    end
  end

  describe "#route" do
    let(:router) { described_class.new }

    it "delivers a response to the matching mailbox" do
      id, mailbox = router.register
      router.route({"id" => id, "result" => {"ok" => true}})
      expect(mailbox.pop).to eq({"id" => id, "result" => {"ok" => true}})
    end

    it "raises on an unknown response id" do
      expect do
        router.route({"id" => 9, "result" => {"ok" => true}})
      end.to raise_error(LLM::MCP::MismatchError, /mismatched MCP response id 9/)
    end
  end

  describe "#write" do
    let(:router) { described_class.new }

    it "serializes writes to the shared transport" do
      transport = Class.new do
        attr_reader :writes

        def initialize
          @writes = []
          @entered = Queue.new
          @release = Queue.new
        end

        def write(message)
          @entered << message
          @release.pop
          @writes << message
        end

        def entered_count
          @entered.size
        end

        def release
          @release << true
        end
      end.new

      threads = 2.times.map do |i|
        Thread.new { router.write(transport, {id: i}) }
      end

      sleep 0.01 until transport.entered_count == 1
      expect(transport.entered_count).to eq(1)
      transport.release
      sleep 0.01 until transport.entered_count == 2
      expect(transport.entered_count).to eq(2)
      transport.release
      threads.each(&:join)
      expect(transport.writes).to contain_exactly({id: 0}, {id: 1})
    end
  end
end
