# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: xai" do
  let(:provider) { LLM.xai(key:) }
  let(:key) { ENV["XAI_SECRET"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM::Context do
    include_examples "LLM::Context: completions", :xai
    include_examples "LLM::Context: text stream", :xai
    include_examples "LLM::Context: tool stream", :xai
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :xai
  end

  context LLM::File do
    include_examples "LLM::Context: files", :xai
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :xai
  end
end
