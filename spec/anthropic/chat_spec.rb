# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: anthropic" do
  let(:provider) { LLM.anthropic(key:) }
  let(:llm) { provider }
  let(:key) { ENV["ANTHROPIC_SECRET"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM do
    include_examples "LLM: web search", :anthropic
  end

  context LLM::Context do
    include_examples "LLM::Context: completions", :anthropic
    include_examples "LLM::Context: completions contract", :anthropic
    include_examples "LLM::Context: text stream", :anthropic
    include_examples "LLM::Context: tool stream", :anthropic
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :anthropic
  end

  context LLM::File do
    include_examples "LLM::Context: files", :anthropic
  end
end
