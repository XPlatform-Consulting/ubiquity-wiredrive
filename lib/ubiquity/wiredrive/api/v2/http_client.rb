require 'cgi'
require 'json'
require 'logger'
require 'net/http'
require 'net/https'
require 'net/http/post/multipart'

require 'ubiquity/wiredrive/version'

module Ubiquity
  module Wiredrive
    module API
      module V2
        class HTTPClient

          class RateLimitException < StandardError; end

          # Ruby uses all lower case headers but Jetty uses case sensitive headers
          class CaseSensitiveHeaderKey < String
            def downcase; self end
            def capitalize; self end
          end


          attr_accessor :logger, :http, :http_host_address, :http_host_port, :base_uri
          attr_accessor :hostname, :username, :password

          attr_accessor :default_request_headers

          attr_accessor :log_request_body, :log_response_body, :log_pretty_print_body

          attr_accessor :request, :response

          DEFAULT_HTTP_HOST_ADDRESS = 'api.wiredrive.rc'
          DEFAULT_HTTP_HOST_PORT = 443

          def initialize(args = { })
            args = args.dup
            initialize_logger(args)
            initialize_http(args)

            @auth_token = args[:auth_token]
            @base_uri = args[:base_uri] || "http#{http.use_ssl? ? 's' : ''}://#{http.address}:#{http.port}/v2/"

            @user_agent_default = "Ubiquity Wiredrive Ruby SDK Version #{Ubiquity::Wiredrive::VERSION}"

            authorization_header_name = CaseSensitiveHeaderKey.new('Authorization')
            authorization_header_value = "Bearer #{@auth_token}"


            @default_request_headers = {
                'user-agent' => @user_agent_default,
                'Content-Type' => 'application/json; charset=utf-8',
                'Accept' => 'application/json',
                authorization_header_name => authorization_header_value,
            }

            @log_request_body = args.fetch(:log_request_body, true)
            @log_response_body = args.fetch(:log_response_body, true)
            @log_pretty_print_body = args.fetch(:log_pretty_print_body, true)

            @cancelled = false
            @parse_response = args.fetch(:parse_response, true)
          end

          def initialize_logger(args = { })
            @logger = args[:logger] ||= Logger.new(args[:log_to] || STDOUT)
            log_level = args[:log_level]
            if log_level
              @logger.level = log_level
              args[:logger] = @logger
            end
            @logger
          end

          def initialize_http(args = { })
            @http_host_address = args[:http_host_address] ||= DEFAULT_HTTP_HOST_ADDRESS
            @http_host_port = args[:http_host_port] ||= DEFAULT_HTTP_HOST_PORT
            @http = Net::HTTP.new(http_host_address, http_host_port)
            http.use_ssl = true

            # TODO Add SSL Patch
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE

            http
          end

          # Formats a HTTPRequest or HTTPResponse body for log output.
          # @param [HTTPRequest|HTTPResponse] obj
          # @return [String]
          def format_body_for_log_output(obj)
            if obj.content_type == 'application/json'
              if @log_pretty_print_body
                _body = obj.body
                output = "\n" << JSON.pretty_generate(JSON.parse(_body)) rescue _body
                return output
              else
                return obj.body
              end
            else
              return obj.body.inspect
            end
          end

          # @param [Net::HTTPRequest] request
          def send_request(request)
            @response_parsed = nil
            @request = request

            begin
              logger.debug { %(REQUEST: #{request.method} http#{http.use_ssl? ? 's' : ''}://#{http.address}:#{http.port}#{request.path} HEADERS: #{request.to_hash.inspect} #{log_request_body and request.request_body_permitted? ? "BODY: #{format_body_for_log_output(request)}" : ''}) }

              @response = http.request(request)
              logger.debug { %(RESPONSE: #{response.inspect} HEADERS: #{response.to_hash.inspect} #{log_response_body and response.respond_to?(:body) ? "BODY: #{format_body_for_log_output(response)}" : ''}) }
              raise RateLimitException, "#{response.to_hash.inspect}" if response.code == '420'
            rescue RateLimitException => e
              logger.warn { "Rate Limited. Will retry in #{@delay_between_rate_limit_retries} seconds." }
              sleep_break @delay_between_rate_limit_retries
              retry unless @cancelled
            end

            @parse_response ? response_parsed : response.body
          end

          def sleep_break(seconds)
            while (seconds > 0)
              sleep(1)
              seconds -= 1
              break if @cancelled
            end
          end

          def response_parsed
            @response_parsed ||= begin
              response_content_type = response.content_type
              logger.debug { "Parsing Response: #{response_content_type}" }

              case response_content_type
                when 'application/json'
                  JSON.parse(response.body) rescue response
                # when 'text/html'
                # when 'text/plain'
                else
                  response.body
              end
            end
          end

          def build_uri(path = '', query = nil)
            _query = query.is_a?(Hash) ? query.map { |k,v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v)}" }.join('&') : query
            _path = "#{path}#{_query and _query.respond_to?(:empty?) and !_query.empty? ? "?#{_query}" : ''}"
            URI.parse(File.join(base_uri, _path))
          end

          if RUBY_VERSION.start_with? '1.8.'
            def request_method_name_to_class_name(method_name)
              method_name.to_s.capitalize
            end
          else
            def request_method_name_to_class_name(method_name)
              method_name.to_s.capitalize.to_sym
            end
          end

          # @param [Symbol] method_name (:get)
          # @param [Hash] args
          # @option args [Hash] :headers ({})
          # @option args [String] :path ('')
          # @option args [Hash] :query ({})
          # @option args [Any] :body (nil)
          # @param [Hash] options
          # @option options [Hash] :default_request_headers (@default_request_headers)
          def call_method(method_name = :get, args = { }, options = { })
            headers = args[:headers] || options[:headers] || { }
            path = args[:path] || ''
            query = args[:query] || { }
            body = args[:body]

            # Allow the default request headers to be overridden
            _default_request_headers = options.fetch(:default_request_headers, default_request_headers)
            _default_request_headers ||= { }
            _headers = _default_request_headers.merge(headers)

            @uri = build_uri(path, query)
            klass_name = request_method_name_to_class_name(method_name)
            klass = Net::HTTP.const_get(klass_name)

            request = klass.new(@uri.request_uri, _headers)

            if request.request_body_permitted?
              _body = (body and !body.is_a?(String)) ? JSON.generate(body) : body
              logger.debug { "Processing Body: '#{_body}'" }
              request.body = _body if _body
            end

            send_request(request)
          end

          def delete(path, options = { })
            query = options.fetch(:query, { })
            @uri = build_uri(path, query)


            request = Net::HTTP::Delete.new(@uri.request_uri, default_request_headers)
            body = options[:body]
            if body
              body = JSON.generate(body) unless body.is_a?(String)
              request.body = body
            end

            send_request(request)
          end

          def get(path, query = nil, options = { })
            query ||= options.fetch(:query, { })
            @uri = build_uri(path, query)
            request = Net::HTTP::Get.new(@uri.request_uri, default_request_headers)
            send_request(request)
          end

          def put(path, body, options = { })
            query = options.fetch(:query, { })
            @uri = build_uri(path, query)
            body = JSON.generate(body) unless body.is_a?(String)

            request = Net::HTTP::Put.new(@uri.request_uri, default_request_headers)
            request.body = body
            send_request(request)
          end

          def post(path, body, options = { })
            query = options.fetch(:query, { })
            @uri = build_uri(path, query)
            body = JSON.generate(body) unless body.is_a?(String)

            request = Net::HTTP::Post.new(@uri.request_uri, default_request_headers)
            request.body = body
            send_request(request)
          end

        end

      end
    end
  end
end
