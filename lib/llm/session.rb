# frozen_string_literal: true

require_relative "context"

module LLM
  # Backward-compatible alias for LLM::Context
  # @deprecated Use {LLM::Context} instead. Scheduled for removal in v6.0.
  Session = Context

  # Scheduled for removal in v6.0
  deprecate_constant :Session
end
