# frozen_string_literal: true

module LLM
  ##
  # LangSmith-specific tracer built on top of Telemetry. Supports extra
  # inputs/outputs and metadata on traces and spans via {#merge_extra} and
  # {#start_trace}(metadata:).
  #
  # @example Constructor metadata and tags
  #   llm.tracer = LLM::Tracer::Langsmith.new(
  #     llm,
  #     session_id: "123e4567-e89b-12d3-a456-426614174000",
  #     metadata: {env: "dev"},
  #     tags: ["changelog"]
  #   )
  #
  # @example Per-request extra metadata and inputs (e.g. from chatbot)
  #   tracer.merge_extra(
  #     metadata: { turn_id: turn.id, component: "chatbot_message_stream" },
  #     inputs: { "gen_ai.input.messages" => messages_json }
  #   )
  #   bot.chat(prompt)
  #
  # @example Trace-level metadata via start_trace
  #   tracer.start_trace(trace_group_id: turn.id, name: "chatbot.turn", metadata: { turn_id: turn.id })
  class Tracer::Langsmith < Tracer::Telemetry
    THREAD_EXTRA_KEY = :llm_langsmith_extra

    UUID = /\A
      [0-9a-f]{8}-
      [0-9a-f]{4}-
      [1-5][0-9a-f]{3}-
      [89ab][0-9a-f]{3}-
      [0-9a-f]{12}
    \z/ix

    def initialize(provider, options = {})
      super
      setup_langsmith!(options)
    end

    def start_trace(trace_group_id: nil, name: "llm", attributes: {}, metadata: nil)
      merge_extra(metadata: metadata) if metadata && !metadata.empty?
      super
    end

    def stop_trace
      clear_thread_extra!
      super
    end

    def merge_extra(metadata: nil, inputs: nil, outputs: nil)
      store = thread_extra
      store[:metadata].merge!(metadata) if metadata && !metadata.empty?
      store[:inputs].merge!(inputs) if inputs && !inputs.empty?
      store[:outputs].merge!(outputs) if outputs && !outputs.empty?
      self
    end

    def current_extra
      store = thread_extra
      {
        metadata: store[:metadata].dup,
        inputs: store[:inputs].dup,
        outputs: store[:outputs].dup
      }
    end

    def consume_extra_inputs
      thread_extra[:inputs].tap { thread_extra[:inputs] = {} }
    end

    def consume_extra_outputs
      thread_extra[:outputs].tap { thread_extra[:outputs] = {} }
    end

    private

    def trace_attributes(span_kind:)
      attributes = {}
      unless @langsmith_session_id.to_s.empty?
        attributes["langsmith.trace.session_id"] = @langsmith_session_id
      end
      merged_metadata = @langsmith_metadata.merge(thread_extra[:metadata])
      merged_metadata.each do |key, value|
        next if value.nil?

        attr_key = key.to_s.start_with?("langsmith.metadata.") ? key.to_s : "langsmith.metadata.#{key}"
        attributes[attr_key] = serialize_langsmith_value(value)
      end
      unless @langsmith_tags.empty?
        attributes["langsmith.span.tags"] = @langsmith_tags.map(&:to_s).join(",")
      end
      attributes["langsmith.span.kind"] = span_kind
      attributes
    end

    def thread_extra
      Thread.current[THREAD_EXTRA_KEY] ||= {
        metadata: {},
        inputs: {},
        outputs: {}
      }
    end

    def clear_thread_extra!
      Thread.current[THREAD_EXTRA_KEY] = nil
    end

    def setup_langsmith!(options)
      options ||= {}
      @langsmith_metadata = options[:metadata] || {}
      @langsmith_session_id = normalize_langsmith_session_id(
        options[:session_id],
        metadata: @langsmith_metadata
      )
      @langsmith_tags = options[:tags] || []
    end

    def serialize_langsmith_value(value)
      case value
      when String, Numeric, TrueClass, FalseClass
        value
      else
        LLM.json.dump(value)
      end
    end

    def normalize_langsmith_session_id(session_id, metadata:)
      raw = session_id&.to_s
      return nil if raw.to_s.empty?
      return raw if uuid?(raw)

      # Keep arbitrary identifiers in metadata instead of forcing
      # them into langsmith.trace.session_id, which expects a UUID.
      metadata[:session_id] ||= raw
      nil
    end

    def uuid?(value)
      value.match?(UUID)
    end
  end
end
