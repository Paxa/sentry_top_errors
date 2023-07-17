module SentryTopErrors::ApiResponse
  def self.new_from_res(http_res)
    if http_res.status == 429 || http_res.status >= 500
      raise "Failed response #{http_res.status} - #{http_res.body}"
    end

    new_obj = begin
      if http_res.body.start_with?('[') && http_res.body.end_with?(']')
        SentryTopErrors::ApiResponse::FromArray.new.concat(JSON.parse(http_res.body))
      else
        SentryTopErrors::ApiResponse::FromHash.new().merge!(JSON.parse(http_res.body))
      end
    rescue JSON::ParserError => error
      puts "Failed to parse response #{http_res.body}"
    end

    new_obj.response = http_res
    new_obj
  end

  module ExtMethods
    def http_success?
      @response.status < 400
    end

    def status
      @response.status
    end

    def headers
      @response.headers
    end
  end

  class FromArray < ::Array
    attr_accessor :response
    include SentryTopErrors::ApiResponse::ExtMethods
  end

  class FromHash < ::Hash
    attr_accessor :response
    include SentryTopErrors::ApiResponse::ExtMethods
  end

end
