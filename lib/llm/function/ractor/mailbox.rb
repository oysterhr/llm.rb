# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Mailbox} class manages the mailbox protocol
  # for a single ractor-backed function call.
  class Ractor::Mailbox
    ##
    # @return [::Ractor]
    attr_reader :task

    ##
    # @param [::Ractor] task
    # @return [LLM::Function::Ractor::Mailbox]
    def initialize(task)
      @task = task
    end

    ##
    # @return [Boolean]
    def alive?
      request(:alive?)
    end

    ##
    # @return [Array]
    def wait
      request(:wait)
    end

    private

    def request(type)
      reply = ::Ractor.new { ::Ractor.receive }
      task.send([type, reply])
      reply.respond_to?(:take) ? reply.take : ::Ractor.select(reply).last
    end
  end
end
