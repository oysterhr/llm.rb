# frozen_string_literal: true

require "securerandom"

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
  #     reference_example_id: "123e4567-e89b-12d3-a456-426614174001",
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
  #
  # Spans started while a tool call runs are nested under that tool's
  # span, across tracer instances and in the fibers and threads the tool
  # starts. The tool span gets its own LangSmith run id
  # (`langsmith.span.id`), and every other span started during the call
  # names it as `langsmith.span.parent_id`.
  class Tracer::Langsmith < Tracer::Telemetry
    THREAD_EXTRA_KEY = :llm_langsmith_extra
    TOOL_RUN_KEY = :llm_langsmith_tool_run
    private_constant :TOOL_RUN_KEY

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

    attr_accessor :parent_span_id

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

    ##
    # Starts the tool span with a LangSmith run id of its own, and makes
    # it the parent of the spans started until the tool call ends.
    # @param (see LLM::Tracer::Telemetry#on_tool_start)
    # @return (see LLM::Tracer::Telemetry#on_tool_start)
    def on_tool_start(**)
      span = super
      run_id = SecureRandom.uuid
      span.set_attribute("langsmith.span.id", run_id)
      Fiber[TOOL_RUN_KEY] = [run_id, Fiber[TOOL_RUN_KEY]].freeze
      span
    end

    ##
    # Finishes the tool span and restores the outer tool call's run as
    # the parent, if there is one.
    # @param (see LLM::Tracer::Telemetry#on_tool_finish)
    # @return (see LLM::Tracer::Telemetry#on_tool_finish)
    def on_tool_finish(**)
      super
    ensure
      end_tool_run
    end

    ##
    # Fails the tool span and restores the outer tool call's run as the
    # parent, if there is one.
    # @param (see LLM::Tracer::Telemetry#on_tool_error)
    # @return (see LLM::Tracer::Telemetry#on_tool_error)
    def on_tool_error(**)
      super
    ensure
      end_tool_run
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
        attributes["langsmith.span.tags"] = @langsmith_tags.join(",")
      end
      attributes["langsmith.span.kind"] = span_kind
      unless @langsmith_reference_example_id.to_s.empty?
        attributes["langsmith.reference_example_id"] = @langsmith_reference_example_id
      end
      parent_id = Fiber[TOOL_RUN_KEY]&.first || @parent_span_id
      unless parent_id.to_s.empty?
        attributes["langsmith.span.parent_id"] = parent_id
      end
      attributes
    end

    def end_tool_run
      Fiber[TOOL_RUN_KEY] = Fiber[TOOL_RUN_KEY]&.last
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
      @langsmith_reference_example_id = options[:reference_example_id]
      @langsmith_tags = options[:tags] || []
      @parent_span_id = options[:parent_span_id]
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
