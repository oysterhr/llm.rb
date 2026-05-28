# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Fork::Group} class wraps an array of
  # {LLM::Function::Task} objects that are running in forked child processes.
  class Fork::Group
    ##
    # @param [Array<LLM::Function::Task>] tasks
    # @return [LLM::Function::Fork::Group]
    def initialize(tasks)
      @tasks = tasks
    end

    ##
    # @return [Boolean]
    def alive?
      @tasks.any?(&:alive?)
    end

    ##
    # @return [nil]
    def interrupt!
      @tasks.each(&:interrupt!)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @return [Array<LLM::Function::Return>]
    def wait
      @tasks.map(&:wait)
    end
    alias_method :value, :wait
  end
end
