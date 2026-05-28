# frozen_string_literal: true

module Sequel
  module Plugins
    require "llm/sequel/agent"
    Agent = LLM::Sequel::Agent
  end
end
