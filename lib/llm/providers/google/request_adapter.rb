# frozen_string_literal: true

class LLM::Google
  ##
  # @private
  module RequestAdapter
    require_relative "request_adapter/completion"

    ##
    # @param [Array<LLM::Message>] messages
    #  The messages to adapt
    # @return [Array<Hash>]
    def adapt(messages, mode: nil)
      messages.filter_map do |message|
        Completion.new(message).adapt
      end
    end

    private

    ##
    # @param [Hash] params
    # @return [Hash]
    def adapt_generation_config(params)
      return {} unless params

      config = {}
      if params[:schema]
        schema = params.delete(:schema)
        schema = schema.respond_to?(:object) ? schema.object : schema
        config.merge!(
          response_mime_type: "application/json",
          response_schema: schema
        )
      end
      config[:temperature] = params.delete(:temperature) if params.key?(:temperature)
      config[:topP] = params.delete(:top_p) if params.key?(:top_p)
      config[:topK] = params.delete(:top_k) if params.key?(:top_k)
      config[:maxOutputTokens] = params.delete(:max_tokens) if params[:max_tokens]
      config[:stopSequences] = params.delete(:stop) if params[:stop]
      config.empty? ? {} : {generationConfig: config}
    end

    ##
    # @param [Hash] params
    # @return [Hash]
    def adapt_tools(tools)
      return {} unless tools&.any?
      platform, functions = [tools.grep(LLM::ServerTool), tools.grep(LLM::Function)]
      {tools: [*platform, {functionDeclarations: functions.map { _1.adapt(self) }}]}
    end
  end
end
