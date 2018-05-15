require 'ubiquity/wiredrive/api/v2/http_client'

class Ubiquity::Wiredrive::API::V2::Client

  attr_accessor :logger

  attr_accessor :http_client, :request, :response, :http_response

  def initialize(args = { })
    require 'ubiquity/wiredrive/api/v2/client/requests'

    initialize_logger(args)
    initialize_http_client(args)
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
    @http_client = Ubiquity::Wiredrive::API::V2::HTTPClient.new(args)
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

  # ################################################################################################################## #
  # @!group API METHODS

  def asset_create(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'assets',
        :http_method => :post,
        :default_parameter_send_in_value => :body,
        :parameters => [
          :name,
          :description,
          :workflow,
          :is_folder,
          { :name => :parent, :aliases => [ :parentid ] },
          { :name => :project, :aliases => [ :projectid ] },
        ]
      }
    )
    # http_client.get('assets')
    _response = process_request(_request, options)

    _response.first if _response.is_a?(Array)
  end

  def asset_primary_file_init(args = { }, options = { })
    args = { :id => args } if args.is_a?(String)
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'assets/#{arguments[:id]}/primary_file',
        :http_success_code => 202,
        :http_method => :post,
        :parameters => [
          { :name => :id, :aliases => [ :assetid ], :send_in => :path }
        ]
      }
    )
    process_request(_request, options)
    http_client.response['location']
  end
  alias :asset_upload_session_get :asset_primary_file_init

  def asset_delete(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'assets/#{arguments[:id]}',
        :http_method => :delete,
        :parameters => [
          { :name => :id, :aliases => [ :assetid ], :send_in => :path },
        ]
      }
    )
    response = process_request(_request, options)
    response
  end

  def asset_get(args = { }, options = { })

  end

  def assets_get(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'assets',
        :parameters => [
          :limit,
          :offset,
          :id,
          :name,
          :workflow,
          :is_folder,
          :is_active,
          :has_default_thumbs,
          :date_created,
          :date_modified,
          :created_by,
          { :name => :parent, :aliases => [ :parentid ] },
          { :name => :project, :aliases => [ :projectid ] },
          :height,
          :width,
          :mime_type,
          :include
        ]
      }
    )

    name = _request.arguments[:name]
    _request.arguments[:name] = CGI.escapeHTML(name) if name

    # http_client.get('assets')
    response = process_request(_request, options)
    response
  end

  def file_upload(args = { }, options = { })
    file_path = args[:file_path]
    file_name = args[:file_name] || File.basename(file_path)

    uri = args[:destination_uri]
    uri = URI(uri) if uri.is_a?(String)

    res = nil
    File.open(file_path) do |file|
      req = Net::HTTP::Post::Multipart.new uri.path,
                                           'file' => UploadIO.new(file, 'application/octet-stream', file_name)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      res = http.request(req)
    end

    res ? res.code.start_with?('2') : false
  end

  def project_create(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'projects',
        :http_method => :post,
        :default_parameter_send_in_value => :body,
        :parameters => [
          :name,
          :description,
          :code,
          :manager,
          :notify_manager,
          :is_active,
        ]
      }
    )
    _response = process_request(_request, options)

    _response.first if _response.is_a?(Array)
  end

  def project_delete(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'projects/#{arguments[:id]}',
        :http_method => :delete,
        :parameters => [
          { :name => :id, :aliases => [ :projectid ], :send_in => :path },
        ]
      }
    )
    response = process_request(_request, options)
    response
  end

  def project_get(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'projects/#{arguments[:id]}',
        :parameters => [
          { :name => :id, :send_in => :path },
          :q,
          :include
        ]
      }
    )
    response = process_request(_request, options)
    response
  end

  def projects_get(args = { }, options = { })
    _request = Requests::BaseRequest.new(
      args,
      {
        :http_path => 'projects',
        :parameters => [
          :id,
          :name,
          :code,
          :notify_manager,
          :is_active,
          :date_last_accessed,
          :date_created,
          :date_modified,
          :date_deleted,
          :manager
        ]
      }
    )

    name = _request.arguments[:name]
    _request.arguments[:name] = CGI.escapeHTML(name) if name

    response = process_request(_request, options)
    response
  end

  # @!endgroup API METHODS

end