# frozen_string_literal: true

require_relative "setup"

RSpec.describe LLM::Contract do
  let(:contract) do
    Module.new do
      extend LLM::Contract
      def foo = nil
      def bar = nil
    end
  end

  context "when a module implements a contract" do
    let(:impl) do
      Module.new do
        def foo = nil
        def bar = nil
      end
    end

    it "does not raise an error" do
      expect { impl.include(contract) }.not_to raise_error
    end
  end

  context "when a module does not implement all contract methods" do
    let(:impl) do
      Module.new do
        def foo = nil
      end
    end

    it "raises a ContractError" do
      expect { impl.include(contract) }
        .to raise_error(described_class::ContractError, /bar/)
    end
  end
end
