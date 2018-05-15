require 'yaml'

require 'ubiquity/wiredrive/api/v3/http_client'
require 'ubiquity/wiredrive/api/v3/client/requests'

class Ubiquity::Wiredrive::API::V3::Client

  attr_accessor :logger

  attr_accessor :http_client, :request, :response, :http_response, :client_code

  def initialize(args = { })
    _token_cache = args.fetch(:token_cache_allow, false)

    _token = args[:auth_token] || _token_cache ? token_cache_read(args) : nil
    args[:auth_token] = _token if _token.is_a?(String) # _token.is_a?(String) ? Token.new(_token, self) : _token if _token

    initialize_logger(args)
    initialize_http_client(args)

    unless _token
      _do_login = args.fetch(:do_login, true)
      if _do_login
        _token = login_and_set_token(args)
        args[:auth_token] = _token
        token_cache_write(args) if _token_cache && _token
      end
    end
  end

  def token_cache_read(args)
    _token_path = args[:token_cache_path] || '_token.yaml'
    _token_path = File.expand_path(_token_path)
    _token = File.exists?(_token_path) ? YAML.load_file(_token_path) : nil
    _token
  end

  def token_cache_write(args)
    _token = args[:auth_token]
    return unless _token
    _token_path = args[:token_cache_path] || '_token.yaml'
    _token_path = File.expand_path(_token_path)
    logger.debug { "Writing Token Cache - '#{_token_path}'" }
    File.open(_token_path, 'w') { |f| f.write(YAML.dump(_token)) }
  end

  def login_and_set_token(args)
    _credentials = args[:credentials] || args
    _client_code = _credentials[:client_code]
    _username = _credentials[:username]
    _password = _credentials[:password]
    if _client_code && _username && _password
      token_data = auth_token(_credentials)
      self.auth_token = token_data
    end
    token_data
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

  def initialize_http_client(args = { })
    @http_client = Ubiquity::Wiredrive::API::V3::HTTPClient.new(args)
  end

  # @param [Requests::BaseRequest] request
  # @param [Hash, nil] options
  # @option options [Boolean] :execute_request (true) Will execute the request
  # @option options [Boolean] :return_request (true) Will return the request instance instead of nil. Only applies if
  #   execute_request is false.
  def process_request(request, options = nil)
    # @paginator = nil
    @response = nil
    @request = request
    logger.warn { "Request is Missing Required Arguments: #{request.missing_required_arguments.inspect}" } unless request.missing_required_arguments.empty?

    # if ([:all, 'all'].include?(request.arguments[:_page]))
    #   request.arguments[:_page] = 1
    #   include_remaining_pages = true
    # else
    #   include_remaining_pages = false
    # end

    request.client = self unless request.client
    options ||= request.options

    return (options.fetch(:return_request, true) ? request : nil) unless options.fetch(:execute_request, true)

    #@response = http_client.call_method(request.http_method, { :path => request.path, :query => request.query, :body => request.body }, options)
    @response = request.execute

    # if include_remaining_pages
    #   return paginator.include_remaining_pages
    # end

    if @response.is_a?(Hash)
      _results = @response['results']
      return _results if _results
    end

    @response
  end

  # Exposes HTTP Methods
  # @example http(:get, '/')
  def http(method, *args)
    @request = nil
    @response = http_client.send(method, *args)
    @request = http_client.request
    response
  end

  # def paginator
  #   @paginator ||= Paginator.new(self) if @response
  # end

  def process_request_using_class(request_class, args = { }, options = { })
    @response = nil
    @request = request_class.new(args, options)
    process_request(request, options)
  end

  def error
    _error = errors.first
    return _error.inspect if _error.is_a?(Hash)
    _error
  end

  def error_message
    _error = error
    _error.is_a?(Hash) ? (_error['message'] || _error) : _error
  end

  def errors
    return (response['errors'] || [ ]) if response.is_a?(Hash)
    [ ]
  end

  def success?
    return unless request
    return request.success? if request.respond_to?(:success?)

    _code = http_client.response.code
    _code and _code.start_with?('2')
  end

  def auth_token=(value)
    http_client.auth_token = value
  end

  # ################################################################################################################## #
  # @!group API METHODS

  def auth_token(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'auth/api-token-auth',
        :http_method => :post,
        :default_parameter_send_in_value => :body,
        :parameters => [
          { :name => :client_code, :required => true, :default_value => client_code },
          { :name => :username, :required => true },
          { :name => :password, :required => true }
        ]
      }.merge(options)
    )
    _initial_http_host_address = http_client.http_host_address
    client_code = _request.arguments[:client_code]
    _http_host_address = "#{client_code}.wiredrive.com"

    http_client.http_host_address = _http_host_address
    _response = process_request(_request, options)
    http_client.http_host_address = _initial_http_host_address
    _token = http_client.response['Authorization']
    _token || _response
  end

  def invitations_get(args = { }, options = { })

  end

  def presentation_authorize_get(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'presentation-orch-api/api/authorize/#{path_arguments[:invite_token]}',
        :default_parameter_send_in_value => :path,
        :parameters => [
          { :name => :invite_token, :aliases => [ :token ], :required => true },
          { :name => :password, :required => true, :send_in => :query }
        ]
      }.merge(options)
    )
    _response = process_request(_request, options)
    _token = http_client.response['Authorization']
    _token || _response
  end

  def presentation_get(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'presentation-orch-api/api/presentations/#{path_arguments[:presentation_id]}',
        :default_parameter_send_in_value => :path,
        :parameters => [
          { :name => :presentation_id, :aliases => [ :id ], :required => true }
        ]
      }.merge(options)
    )
    process_request(_request, options)
  end

  def users_get(args = { }, options = { })
    http(:get, 'user-orch-api/api/users')
  end

  def users_projects_get(args = { }, options = { })
    http(:get, 'user-orch-api/api/users/projects')
  end

  # @!endgroup API METHODS

end