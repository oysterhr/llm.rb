# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Provider do
  before do
    provider.class.module_eval do
      public :headers, :execute
    end
  end

  after do
    provider.class.module_eval do
      private :headers, :execute
    end
  end

  let(:tracer) do
    Class.new do
      attr_reader :finishes

      def initialize
        @finishes = []
      end

      def on_request_start(operation:, model: nil, inputs: nil)
        {operation:, model:, inputs:}
      end

      def on_request_finish(operation:, res:, model: nil, span: nil)
        @finishes << {operation:, model:, res:, span:}
        nil
      end
    end
  end

  let(:provider) { LLM.openai(key: "test") }

  describe "#headers" do
    let(:count) { 50 }
    let(:errors) { Queue.new }
    let(:writers) do
      count.times.map do |i|
        Thread.new do
          provider.with(headers: {"X-Thread-#{i}" => i.to_s})
        end
      end
    end
    let(:readers) do
      count.times.map do
        Thread.new do
          25.times { provider.headers }
        rescue => ex
          errors << ex
        end
      end
    end

    it "keeps all writes" do
      writers.each(&:join)
      headers = provider.headers
      count.times do |i|
        expect(headers["X-Thread-#{i}"]).to eq(i.to_s)
      end
    end

    it "handles reads while writing" do
      [*writers, *readers].each(&:join)
      expect(errors).to be_empty
      headers = provider.headers
      count.times do |i|
        expect(headers["X-Thread-#{i}"]).to eq(i.to_s)
      end
    end
  end

  describe "#tracer" do
    let(:started) { Queue.new }
    let(:release) { Queue.new }
    let(:tracer1) { tracer.new }
    let(:tracer2) { tracer.new }

    before do
      stub_request(:get, "https://api.openai.com/v1/models")
        .to_return do
          started << true
          release.pop
          {status: 200, body: "{}", headers: {"Content-Type" => "application/json"}}
        end
    end

    describe "#tracer=" do
      it "replaces the provider default tracer" do
        provider.tracer = tracer1
        provider.tracer = tracer2
        expect(provider.tracer).to equal(tracer2)
      end

      let(:count) { 20 }
      let(:errors) { Queue.new }
      let(:mutators) do
        count.times.map do
          Thread.new do
            local_tracer = tracer.new
            20.times do |i|
              provider.tracer = (i.even? ? local_tracer : nil)
            end
          rescue => ex
            errors << ex
          end
        end
      end

      it "does not raise errors under concurrent writes" do
        mutators.each(&:join)
        expect(errors).to be_empty
      end

      it "assigns the provider default tracer" do
        mutators.each(&:join)
        expect([tracer.class, LLM::Tracer::Null]).to include(provider.tracer.class)
      end
    end

    describe "#with_tracer" do
      it "overrides the tracer inside the block" do
        provider.tracer = tracer1
        provider.with_tracer(tracer2) do
          expect(provider.tracer).to equal(tracer2)
        end
        expect(provider.tracer).to equal(tracer1)
      end

      it "restores an existing override" do
        provider.with_tracer(tracer1) do
          provider.with_tracer(tracer2) do
            expect(provider.tracer).to equal(tracer2)
          end
          expect(provider.tracer).to equal(tracer1)
        end
      end

      it "does not leak the override into another thread" do
        provider.tracer = tracer1
        _res, _span, request_tracer = run_in_flight_request do
          provider.with_tracer(tracer2) do
            release << true
          end
        end
        expect(request_tracer).to equal(tracer1)
      end

      it "restores the default tracer after the block" do
        provider.tracer = tracer1
        provider.with_tracer(tracer2) {}
        expect(provider.tracer).to equal(tracer1)
      end
    end

    describe "request execution" do
      it "uses the provider default tracer across threads" do
        provider.tracer = tracer1
        _res, _span, request_tracer = run_in_flight_request
        expect(request_tracer).to equal(tracer1)
      end

      it "uses null tracer when no default or override is set" do
        _res, _span, request_tracer = run_in_flight_request
        expect(request_tracer).to be_a(LLM::Tracer::Null)
      end
    end

    def run_in_flight_request
      t = Thread.new do
        req = Net::HTTP::Get.new("/v1/models", provider.headers)
        provider.execute(request: req, operation: "chat", model: "gpt-test")
      end
      started.pop
      yield if block_given?
      release << true
      t.value
    end
  end
end
