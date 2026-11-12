# frozen_string_literal: true

class LLM::Anthropic
  ##
  # @private
  class ErrorHandler
    ##
    # Maps the error type of an in-stream error event to an error class
    STREAM_ERRORS = {
      "rate_limit_error" => LLM::RateLimitError,
      "authentication_error" => LLM::UnauthorizedError,
      "invalid_request_error" => LLM::InvalidRequestError,
      "api_error" => LLM::ServerError,
      "overloaded_error" => LLM::ServerError
    }.freeze

    ##
    # Builds the error for an in-stream error event, which can arrive
    # after an HTTP 200 response
    # @param [Hash] error
    #  The "error" object of the event
    # @return [LLM::Error]
    def self.stream_error(error)
      message = [error["type"], error["message"]].compact.join(": ")
      STREAM_ERRORS.fetch(error["type"], LLM::Error).new(message)
    end

    ##
    # @return [Net::HTTPResponse]
    #  Non-2XX response from the server
    attr_reader :res

    ##
    # @return [Object, nil]
    #  The span
    attr_reader :span

    ##
    # @param [LLM::Tracer] tracer
    #  The tracer
    # @param [Object, nil] span
    #  The span
    # @param [Net::HTTPResponse] res
    #  The response from the server
    # @return [LLM::Anthropic::ErrorHandler]
    def initialize(tracer, span, res)
      @tracer = tracer
      @span = span
      @res = res
    end

    ##
    # @raise [LLM::Error]
    #  Raises a subclass of {LLM::Error LLM::Error}
    def raise_error!
      ex = error
      @tracer.on_request_error(ex:, span:)
    ensure
      raise(ex) if ex
    end

    private

    ##
    # @return [LLM::Error]
    def error
      case res
      when Net::HTTPServerError
        LLM::ServerError.new("Server error").tap { _1.response = res }
      when Net::HTTPUnauthorized
        LLM::UnauthorizedError.new("Authentication error").tap { _1.response = res }
      when Net::HTTPTooManyRequests
        LLM::RateLimitError.new("Too many requests").tap { _1.response = res }
      else
        LLM::Error.new("Unexpected response").tap { _1.response = res }
      end
    end
  end
end
