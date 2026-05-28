# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Fork::Job} class represents a single fork-backed
  # function call inside the child process.
  #
  # It is executed in the forked process and is responsible for running the
  # resolved tool instance, handling control messages such as interrupts, and
  # writing the final result back to the parent process.
  class Fork::Job
    ##
    # @param [LLM::Function] function
    # @param [LLM::Object] ch
    # @return [LLM::Function::Fork::Job]
    def initialize(function, ch)
      @function = function
      @ch = ch
    end

    ##
    # @return [void]
    def call
      runner = @function.runner
      controller = setup(runner)
      @ch.result.write([:result, call!(runner)])
    rescue => ex
      @ch.result.write([:result, error(ex)])
    ensure
      controller&.kill
      [@ch.control, @ch.result].each { _1.close unless _1.closed? }
    end

    private

    def call!(runner)
      kwargs = if Hash === @function.arguments
        @function.arguments.transform_keys(&:to_sym)
      else
        @function.arguments
      end
      {id: @function.id, name: @function.name, value: runner.call(**kwargs)}
    end

    def error(ex)
      {
        id: @function.id,
        name: @function.name,
        value: {error: true, type: ex.class.name, message: ex.message}
      }
    end

    def setup(runner)
      ready = Queue.new
      thread = Thread.new do
        ready << true
        kind = @ch.control.recv
        next unless kind == :interrupt
        hook = %i[on_cancel on_interrupt].find { runner.respond_to?(_1) }
        runner.public_send(hook) if hook
      rescue IOError, ArgumentError
      end
      ready.pop
      thread
    end
  end
end
