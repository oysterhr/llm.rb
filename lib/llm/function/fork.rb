# frozen_string_literal: true

class LLM::Function
  module Fork
    require_relative "fork/job"
    require_relative "fork/task"
  end
end
