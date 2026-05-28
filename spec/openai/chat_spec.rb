# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: openai" do
  let(:provider) { LLM.openai(key:) }
  let(:llm) { provider }
  let(:key) { ENV["OPENAI_SECRET"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM do
    include_examples "LLM: web search", :openai
  end

  context LLM::Context do
    include_examples "LLM::Context: completions", :openai
    include_examples "LLM::Context: completions contract", :openai
    include_examples "LLM::Context: text stream", :openai
    include_examples "LLM::Context: tool stream", :openai
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :openai
  end

  context LLM::File do
    include_examples "LLM::Context: files", :openai
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :openai
  end
end
