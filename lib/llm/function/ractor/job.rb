# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Job} class manages execution and mailbox
  # coordination for a single ractor-backed function call.
  class Ractor::Job
    ##
    # @param [::Ractor] mailbox
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @return [LLM::Function::Ractor::Job]
    def initialize(mailbox, runner_class, id, name, arguments)
      @mailbox = mailbox
      @runner_class = runner_class
      @id = id
      @name = name
      @arguments = arguments
    end

    ##
    # @return [void]
    def call
      spawn
      wait
    end

    private

    def wait
      done = false
      result = nil
      waiters = []
      loop do
        case ::Ractor.receive
        in [:done, *result]
          done = true
          waiters.each { _1.send(result) }
          waiters.clear
        in [:alive?, reply]
          reply.send(!done)
        in [:wait, reply]
          done ? reply.send(result) : waiters << reply
        end
      end
    end

    def spawn
      ::Ractor.new(@mailbox, @runner_class, @id, @name, @arguments) do |mailbox, runner_class, id, name, arguments|
        kwargs = Hash === arguments ? arguments.transform_keys(&:to_sym) : arguments
        mailbox.send([:done, id, name, runner_class.new.call(**kwargs)])
      rescue => ex
        mailbox.send([:done, id, name, {error: true, type: ex.class.name, message: ex.message}])
      end
    end
  end
end
