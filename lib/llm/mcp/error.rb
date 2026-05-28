# frozen_string_literal: true

class LLM::MCP
  Error = Class.new(LLM::Error) do
    attr_reader :code, :data

    ##
    # @param [Hash] response
    #  The full response from the MCP process, including the error object
    # @return [LLM::MCP::Error]
    def self.from(response:)
      error = response.fetch("error")
      new(*error.values_at("message", "code", "data"))
    end

    ##
    # @param [String] message
    #  The error message
    # @param [Integer] code
    #  The error code
    # @param [Object] data
    #  Additional error data provided by the MCP process
    def initialize(message, code = nil, data = nil)
      super(message)
      @code = code
      @data = data
    end
  end

  MismatchError = Class.new(Error) do
    ##
    # @return [Integer, String]
    #  The request id the client was waiting for
    attr_reader :expected_id

    ##
    # @return [Integer, String]
    #  The response id received from the server
    attr_reader :actual_id

    ##
    # @param [Integer, String] expected_id
    #  The request id the client was waiting for
    # @param [Integer, String] actual_id
    #  The response id received from the server instead
    def initialize(expected_id:, actual_id:)
      @expected_id = expected_id
      @actual_id = actual_id
      super(message)
    end

    ##
    # @return [String]
    def message
      "mismatched MCP response id #{actual_id.inspect} " \
      "while waiting for #{expected_id.inspect}"
    end
  end

  TimeoutError = Class.new(Error)
end
