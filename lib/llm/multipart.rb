# encoding: ascii-8bit
# frozen_string_literal: true

##
# @private
class LLM::Multipart
  require "securerandom"
  require_relative "multipart/enumerator_io"
  CHUNK_SIZE = 16 * 1024

  ##
  # @return [String]
  attr_reader :boundary

  ##
  # @param [Hash] params
  #  Request parameters
  # @return [LLM::Multipart]
  def initialize(params)
    @boundary = "BOUNDARY__#{SecureRandom.hex(16)}"
    @params = params
  end

  ##
  # Returns the multipart content type
  # @return [String]
  def content_type
    "multipart/form-data; boundary=#{@boundary}"
  end

  ##
  # Returns the multipart request body as a stream
  # @return [LLM::Multipart::EnumeratorIO]
  def body
    LLM::Multipart::EnumeratorIO.new(enum_for(:each_part))
  end

  private

  attr_reader :params

  def each_part
    params.each do |key, value|
      locals = {key: key.to_s.b, boundary: boundary.to_s.b}
      if value.respond_to?(:path)
        locals = locals.merge(attributes(value))
        yield file_header(locals)
        File.open(value.path, "rb") do |io|
          while (chunk = io.read(CHUNK_SIZE))
            yield chunk
          end
        end
        yield "\r\n".b
      else
        locals = locals.merge(value:)
        yield form_header(locals)
        yield value.to_s.b
        yield "\r\n".b
      end
    end
    yield "--#{@boundary}--\r\n".b
  end

  def attributes(file)
    {
      filename: File.basename(file.path).b,
      content_type: LLM::Mime[file].b
    }
  end

  def file_header(locals)
    "--#{locals[:boundary]}\r\n" \
      "Content-Disposition: form-data; name=\"#{locals[:key]}\";" \
      "filename=\"#{locals[:filename]}\"\r\n" \
      "Content-Type: #{locals[:content_type]}\r\n\r\n"
  end

  def form_header(locals)
    "--#{locals[:boundary]}\r\n" \
      "Content-Disposition: form-data; name=\"#{locals[:key]}\"\r\n\r\n"
  end
end
