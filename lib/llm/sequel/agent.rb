# frozen_string_literal: true

module LLM::Sequel
  ##
  # Sequel plugin for persisting {LLM::Agent LLM::Agent} state.
  #
  # This wrapper reuses the same record-backed runtime surface as
  # {LLM::Sequel::Plugin}, but builds an {LLM::Agent LLM::Agent} instead of an
  # {LLM::Context LLM::Context}. Agent defaults such as model, tools, schema,
  # instructions, and concurrency are configured on the model class and
  # forwarded to an internal agent subclass.
  module Agent
    require_relative "plugin"
    EMPTY_HASH = LLM::Sequel::Plugin::EMPTY_HASH
    DEFAULTS = LLM::Sequel::Plugin::DEFAULTS
    Utils = LLM::Sequel::Plugin::Utils

    def self.apply(model, **)
      model.extend ClassMethods
      model.include LLM::Sequel::Plugin::InstanceMethods
      model.include InstanceMethods
    end

    def self.configure(model, options = EMPTY_HASH, &block)
      options = DEFAULTS.merge(options)
      model.db.extension :pg_json if %i[json jsonb].include?(options[:format])
      model.instance_variable_set(:@llm_agent_options, options.freeze)
      model.instance_exec(&block) if block
    end

    module ClassMethods
      def llm_plugin_options
        @llm_agent_options || Agent::DEFAULTS
      end

      def model(model = nil)
        return agent.model if model.nil?
        agent.model(model)
      end

      def tools(*tools)
        return agent.tools if tools.empty?
        agent.tools(*tools)
      end

      def schema(schema = nil)
        return agent.schema if schema.nil?
        agent.schema(schema)
      end

      def instructions(instructions = nil)
        return agent.instructions if instructions.nil?
        agent.instructions(instructions)
      end

      def concurrency(concurrency = nil)
        return agent.concurrency if concurrency.nil?
        agent.concurrency(concurrency)
      end

      def tracer(tracer = nil, &block)
        return agent.tracer if tracer.nil? && !block
        agent.tracer(tracer, &block)
      end

      def agent
        @agent ||= Class.new(LLM::Agent)
      end
    end

    module InstanceMethods
      private

      def ctx
        @ctx ||= begin
          options = self.class.llm_plugin_options
          columns = Agent::Utils.columns(options)
          params = Agent::Utils.resolve_options(self, options[:context], Agent::EMPTY_HASH).dup
          ctx = self.class.agent.new(llm, params.compact)
          data = self[columns[:data_column]]
          if data.nil? || data == ""
            ctx
          else
            case options[:format]
            when :string then ctx.restore(string: data)
            when :json, :jsonb then ctx.restore(data:)
            else raise ArgumentError, "Unknown format: #{options[:format].inspect}"
            end
          end
        end
      end
    end
  end
end
