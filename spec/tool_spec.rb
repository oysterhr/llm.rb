# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tool do
  before(:each) do
    described_class.clear_registry!
  end

  let(:shell) do
    Class.new(described_class) do
      name "shell"
      description "run shell commands"
    end
  end

  let(:weather) do
    Class.new(described_class) do
      name "weather"
      description "show a weather report"
    end
  end

  describe ".registry" do
    subject { described_class.registry }

    context "when given the shell tool" do
      before { shell }
      it { is_expected.to eq([shell]) }
    end

    context "when given the weather tool" do
      before { weather }
      it { is_expected.to eq([weather]) }
    end

    context "when given the weather and shell tools" do
      before { [weather, shell] }
      it { is_expected.to eq([weather, shell]) }
    end

    context "when given an inheritance chain" do
      let(:base) { Class.new(described_class) }
      let(:shell) do
        Class.new(base) do
          name "shell"
          description "run shell commands"
        end
      end

      before { [base, shell] }

      it "includes the tool with a definition" do
        is_expected.to eq([shell])
      end
    end

    context "when given an MCP tool" do
      let(:mcp) do
        described_class.mcp(Object.new, {
          "name" => "list_directory",
          "description" => "list a directory",
          "inputSchema" => {type: "object", properties: {}}
        })
      end

      before { mcp }

      it "includes it in the registry" do
        is_expected.to eq([mcp])
      end
    end
  end

  describe ".unregister" do
    before { [weather, shell] }

    it "removes a tool from the registry" do
      described_class.unregister(shell)
      expect(described_class.registry).to eq([weather])
    end

    it "does nothing when the tool is not registered" do
      tool = Class.new(described_class)
      described_class.unregister(tool)
      expect(described_class.registry).to eq([weather, shell])
    end

    it "returns the unregistered tool" do
      expect(described_class.unregister(shell)).to eq(shell)
    end

    it "returns the given tool when it is not registered" do
      tool = Class.new(described_class)
      expect(described_class.unregister(tool)).to eq(tool)
    end
  end

  describe ".find_by_name" do
    before { [weather, shell] }

    it "returns a tool when found" do
      expect(described_class.find_by_name("shell")).to eq(shell)
    end

    it "returns nil when not found" do
      expect(described_class.find_by_name("missing")).to be_nil
    end
  end

  describe ".find_by_name!" do
    before { [weather, shell] }

    it "returns a tool when found" do
      expect(described_class.find_by_name!("shell")).to eq(shell)
    end

    it "raises when not found" do
      expect { described_class.find_by_name!("missing") }
        .to raise_error(LLM::NoSuchToolError, 'no such tool "missing"')
    end
  end

  describe ".function" do
    it "adapts a no-arg tool for xai with an object schema" do
      provider = LLM.xai(key: "TOKEN")
      payload = shell.function.adapt(provider)

      expect(payload).to eq(
        type: "function",
        name: "shell",
        function: {
          name: "shell",
          description: "run shell commands",
          parameters: {type: "object", properties: {}}
        }
      )
    end
  end

  describe "#function" do
    let(:tool_class) do
      Class.new(described_class) do
        name "echo"

        def initialize(prefix:)
          @prefix = prefix
        end

        def call(value:)
          {"value" => "#{@prefix}: #{value}"}
        end
      end
    end
    let(:tool) { tool_class.new(prefix: "stateful") }

    it "returns a function bound to the tool instance" do
      result = tool.function.tap { _1.arguments = {"value" => "hello"} }.call
      expect(result.to_h).to eq(
        id: nil,
        name: "echo",
        value: {"value" => "stateful: hello"}
      )
    end
  end
end
