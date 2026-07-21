# frozen_string_literal: true

require "setup"
require "timeout"
require "tmpdir"

RSpec.describe LLM::Function do
  let(:tool_class) do
    Class.new(LLM::Tool) do
      name "system"
      def call(command:)
        {"ok" => command == "date"}
      end
    end
  end
  let(:tool) do
    tool_class.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {"command" => "date"}
    end
  end

  describe "#spawn" do
    subject(:task) { tool.spawn(strategy) }

    let(:strategy) { :ractor }

    describe "#value" do
      subject { task.value.to_h }
      it { is_expected.to eq(id: "call_1", name: "system", value: {"ok" => true}) }
    end

    describe "#alive?" do
      slow_tool = Class.new(LLM::Tool) do
        name "slow"
        def call
          sleep 0.5
          {"ok" => true}
        end
      end.function.dup.tap do |fn|
        fn.id = "call_2"
        fn.arguments = {}
      end

      it "tracks task liveness" do
        task = slow_tool.spawn(:ractor)
        sleep 0.01 until task.alive?
        expect(task.alive?).to be(true)
        task.wait
        expect(task.alive?).to be(false)
      end
    end

    it "rejects proc-defined functions" do
      fn = LLM::Function.new("echo")
      fn.arguments = {"value" => "hello"}
      fn.define { |value:| {value:} }
      expect { fn.spawn(:ractor) }.to raise_error(
        LLM::RactorError,
        "Ractor concurrency only supports class-based tools"
      )
    end

    context "when configured with a tracer" do
      let(:tracer) { double("tracer", on_tool_start: :span, on_tool_finish: nil) }

      before do
        tool.tracer = tracer
        tool.model = "gpt-4.1"
      end

      it "traces the ractor-backed tool call" do
        expect(task.wait.to_h).to eq(id: "call_1", name: "system", value: {"ok" => true})
        expect(tracer).to have_received(:on_tool_start).with(
          id: "call_1",
          name: "system",
          arguments: {"command" => "date"},
          model: "gpt-4.1"
        )
        expect(tracer).to have_received(:on_tool_finish).with(
          result: have_attributes(id: "call_1", name: "system", value: {"ok" => true}),
          span: :span
        )
      end
    end

    context "when using fork concurrency" do
      let(:strategy) { :fork }

      it "returns the tool result" do
        expect(task.wait.to_h).to eq(id: "call_1", name: "system", value: {"ok" => true})
      end

      describe "error handling" do
        let(:error_tool) do
          tool_class.function.dup.tap do |fn|
            fn.id = "call_4"
            fn.arguments = {"paths" => ["CHANGELOG.md"]}
          end
        end

        it "returns tool errors without hanging" do
          result = Timeout.timeout(1) { error_tool.spawn(:fork).wait.to_h }
          expect(result).to eq(
            id: "call_4",
            name: "system",
            value: {error: true, type: "ArgumentError", message: "missing keyword: :command"}
          )
        end
      end

      context "when configured with a tracer" do
        let(:tracer) { double("tracer", on_tool_start: :span, on_tool_finish: nil) }

        before do
          tool.tracer = tracer
          tool.model = "gpt-4.1"
        end

        it "traces the fork-backed tool call" do
          expect(task.wait.to_h).to eq(id: "call_1", name: "system", value: {"ok" => true})
          expect(tracer).to have_received(:on_tool_start).with(
            id: "call_1",
            name: "system",
            arguments: {"command" => "date"},
            model: "gpt-4.1"
          )
          expect(tracer).to have_received(:on_tool_finish).with(
            result: have_attributes(id: "call_1", name: "system", value: {"ok" => true}),
            span: :span
          )
        end
      end

      let(:ch) { xchan(:marshal) }
      let(:interrupt_ch) { ch }

      let(:interrupt_tool) do
        ch = interrupt_ch
        tool_class = Class.new(LLM::Tool) do
          name "interruptible"

          define_method(:call) do
            ch.recv
            {"ok" => true}
          end

          define_method(:on_interrupt) do
            ch.write(true)
          end
        end
        tool_class.function.dup.tap do |fn|
          fn.id = "call_3"
          fn.arguments = {}
        end
      end

      it "delivers interrupts to the child tool" do
        task = interrupt_tool.spawn(:fork)
        sleep 0.05 until task.alive?
        task.interrupt!
        expect(task.wait.to_h).to eq(id: "call_3", name: "interruptible", value: {"ok" => true})
      end
    end

    context "when using fiber concurrency without a scheduler" do
      it "raises a clear error" do
        expect { tool.spawn(:fiber) }.to raise_error(
          ArgumentError,
          "Fiber concurrency requires Fiber.scheduler"
        )
      end
    end

    context "when using thread concurrency" do
      let(:strategy) { :thread }

      it "returns the tool result" do
        expect(task.wait.to_h).to eq(id: "call_1", name: "system", value: {"ok" => true})
      end

      context "with ActiveRecord loaded" do
        require "active_record"
        require "sqlite3"

        around do |example|
          ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:", pool: 1, checkout_timeout: 1)
          example.run
        ensure
          ActiveRecord::Base.connection_handler.clear_all_connections!
        end

        let(:ar_tool_class) do
          Class.new(LLM::Tool) do
            name "ar_tool"
            def call
              ActiveRecord::Base.connection.execute("SELECT 1")
              {"ok" => true}
            end
          end
        end

        def spawn_ar_tool
          fn = ar_tool_class.function.dup
          fn.id = "call_ar"
          fn.arguments = {}
          fn.spawn(:thread).wait
        end

        it "releases the connection back to the pool so a single-connection pool " \
           "is never exhausted across repeated dispatches" do
          5.times { spawn_ar_tool }
          expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(0)
        end
      end
    end
  end

  describe "#spawn with :thread concurrency and ActiveRecord" do
    require "active_record"
    require "sqlite3"

    around do |example|
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:", pool: 1)
      example.run
    ensure
      ActiveRecord::Base.connection_handler.clear_all_connections!
    end

    describe "#with_active_record_connection" do
      it "releases a connection the block checked out" do
        tool.send(:with_active_record_connection) { ActiveRecord::Base.connection.execute("SELECT 1") }
        expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(0)
      end

      it "releases the connection even when the block raises" do
        expect {
          tool.send(:with_active_record_connection) do
            ActiveRecord::Base.connection.execute("SELECT 1")
            raise "boom"
          end
        }.to raise_error("boom")
        expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(0)
      end

      it "is a no-op when the block never checks out a connection" do
        expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(0)
        tool.send(:with_active_record_connection) { 1 + 1 }
        expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(0)
      end
    end
  end

  describe LLM::Function::Array do
    subject { [tool].extend(LLM::Function::Array).wait(:ractor).map(&:to_h) }
    it { is_expected.to eq([{id: "call_1", name: "system", value: {"ok" => true}}]) }

    it "waits on forked work" do
      expect([tool].extend(LLM::Function::Array).wait(:fork).map(&:to_h)).to eq(
        [{id: "call_1", name: "system", value: {"ok" => true}}]
      )
    end
  end
end
