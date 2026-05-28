# frozen_string_literal: true

class LLM::MCP
  ##
  # A per-request mailbox for routing a JSON-RPC response back to the
  # caller waiting on that request id.
  class Mailbox
    def initialize
      @queue = Queue.new
    end

    def <<(message)
      @queue << message
      self
    end

    def pop
      @queue.pop(true)
    rescue ThreadError
      nil
    end
  end
end
