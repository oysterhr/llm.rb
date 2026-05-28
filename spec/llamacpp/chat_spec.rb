# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: llamacpp" do
  let(:provider) { LLM.llamacpp(host:) }
  let(:host) { ENV["LLAMACPP_HOST"] || "localhost" }
  let(:ctx) { LLM::Context.new(provider, params.merge(model: "qwen3")) }
  let(:params) { {} }
  vcr = lambda { {vcr: {cassette_name: "llamacpp/chat/#{_1}"}} }

  context LLM::Context do
    include_examples "LLM::Context: completions", :llamacpp

    context "when the model returns reasoning content", vcr.call("llm_function_class") do
      it "exposes reasoning content on the assistant message" do
        ctx.talk("What is the date?")
        expect(ctx.messages.find(&:assistant?).reasoning_content).to be_a(String)
      end
    end

    context "with streams" do
      include_examples "LLM::Context: text stream", :llamacpp

      context "when tool calls are not supported", vcr.call("llm_chat_stream_tool") do
        let(:params) { {stream: true, tools: [tool]} }
        let(:tool) do
          LLM.function(:system) do |fn|
            fn.description "Runs system commands"
            fn.params { _1.object(command: _1.string.required) }
            fn.define { {success: Kernel.system(_1.command)} }
          end
        end

        it "emits an error" do
          ctx.talk "Run the tool"
          expect(false).to be_true
        rescue => ex
          expect(ex.message).to match(/Cannot use tools with stream/)
        end
      end
    end
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :llamacpp
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :llamacpp
  end
end
