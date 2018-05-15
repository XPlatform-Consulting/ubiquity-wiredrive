require 'cgi'

class Ubiquity::Wiredrive::API::V2::Client::Requests::BaseRequest

  HTTP_METHOD = :get
  HTTP_BASE_PATH = ''
  HTTP_PATH = ''
  HTTP_SUCCESS_CODE = 200

  DEFAULT_PARAMETER_SEND_IN_VALUE = :query

  PARAMETERS = [ ]

  attr_accessor :client, :arguments, :options, :initial_arguments, :initial_options, :missing_required_arguments,
                :default_parameter_send_in_value, :processed_parameters, :initialized, :response

  attr_writer :parameters, :path, :body, :query

  def self.normalize_argument_hash_keys(hash)
    return hash unless hash.is_a?(Hash)
    Hash[ hash.dup.map { |k,v| [ normalize_parameter_name(k), v ] } ]
  end

  def self.normalize_parameter_name(name)
    (name || '').respond_to?(:to_s) ? name.to_s.gsub('_', '').gsub('-', '').downcase : name
  end

  def self.process_parameter(param, args = { }, args_out = { }, missing_required_arguments = [ ], processed_parameters = { }, default_parameter_send_in_value = DEFAULT_PARAMETER_SEND_IN_VALUE, options = { })
    args = normalize_argument_hash_keys(args) || { } if options.fetch(:normalize_argument_hash_keys, false)

    _k = param.is_a?(Hash) ? param : { :name => param, :required => false, :send_in => default_parameter_send_in_value }
    _k[:send_in] ||= default_parameter_send_in_value

    proper_parameter_name = _k[:name]
    param_name = normalize_parameter_name(proper_parameter_name)
    arg_key = (has_key = args.has_key?(param_name)) ?
        param_name :
        ( (_k[:aliases] || [ ]).map { |a| normalize_parameter_name(a) }.find { |a| has_key = args.has_key?(a) } || param_name )

    value = has_key ? args[arg_key] : _k[:default_value]
    is_set = has_key || _k.has_key?(:default_value)

    processed_parameters[proper_parameter_name] = _k.merge(:value => value, :is_set => is_set)

    unless is_set
      missing_required_arguments << proper_parameter_name if _k[:required]
    else
      args_out[proper_parameter_name] = value
    end

    { :arguments_out => args_out, :processed_parameters => processed_parameters, :missing_required_arguments => missing_required_arguments }
  rescue => e
    raise e, "Error Processing Parameter: #{param.inspect} Args: #{args.inspect}. #{e.message}"
  end

  def self.process_parameters(params, args, options = { })
    args = normalize_argument_hash_keys(args) || { }
    args_out = options[:arguments_out] || { }
    default_parameter_send_in_value = options[:default_parameter_send_in_value] || DEFAULT_PARAMETER_SEND_IN_VALUE
    processed_parameters = options[:processed_parameters] || { }
    missing_required_arguments = options[:missing_required_arguments] || [ ]

    params.each do |param|
      process_parameter(param, args, args_out, missing_required_arguments, processed_parameters, default_parameter_send_in_value)
    end
    { :arguments_out => args_out, :processed_parameters => processed_parameters, :missing_required_arguments => missing_required_arguments }
  end

  def initialize(args = { }, options = { })
    @initial_arguments = args.dup
    @initial_options = options.dup

    @options = options.dup

    initialize_attributes if options.fetch(:initialize_attributes, true)
    after_initialize
  end

  def after_initialize
    process_parameters if initialized
  end

  def initialize_attributes
    @client = options[:client]
    @missing_required_arguments = [ ]
    @default_parameter_send_in_value = options[:default_parameter_send_in_value] || self.class::DEFAULT_PARAMETER_SEND_IN_VALUE
    @processed_parameters = { }
    @arguments = { }
    @eval_http_path = options.fetch(:eval_http_path, true)
    @base_path = options[:base_path]

    @parameters = options[:parameters]
    @http_method = options[:http_method]
    @http_path = options[:http_path] ||= options[:path_raw]

    @path = options[:path]
    @path_arguments = nil
    @path_only = nil

    @query = options[:query]
    @query_arguments = nil

    @body = options[:body]
    @body_arguments = nil

    @response = nil

    @http_success_code = options[:http_success_code] || HTTP_SUCCESS_CODE

    @initialized = true
  end
  alias :reset_attributes :initialize_attributes

  def process_parameters(params = parameters, args = @initial_arguments, _options = @options)
    before_process_parameters unless _options.fetch(:skip_before_process_parameters, false)
    self.class.process_parameters(params, args, _options.merge(:processed_parameters => processed_parameters, :missing_required_arguments => missing_required_arguments, :default_parameter_send_in_value => default_parameter_send_in_value, :arguments_out => arguments))
    after_process_parameters unless _options.fetch(:skip_after_process_parameters, false)
  end

  def before_process_parameters
    # TO BE IMPLEMENTED IN CHILD CLASS
  end

  def after_process_parameters
    # TO BE IMPLEMENTED IN CHILD CLASS
  end
  alias :post_process_arguments :after_process_parameters

  # @!group Attribute Readers

  def http_success_code
    @http_success_code
  end

  def arguments
    @arguments ||= { }
  end

  def base_path
    @base_path ||= self.class::HTTP_BASE_PATH
  end

  def body_arguments
    @body_arguments ||= arguments.dup.delete_if { |k,_| processed_parameters[k][:send_in] != :body }
  end

  def body
    @body ||= body_arguments.empty? ? nil : body_arguments
  end

  def client
    @client ||= options[:client]
  end

  def eval_http_path?
    @eval_http_path
  end

  def http_path
    @http_path ||= self.class::HTTP_PATH
  end

  def http_method
    @http_method ||= self.class::HTTP_METHOD
  end

  def parameters
    @parameters ||= self.class::PARAMETERS.dup
  end

  def relative_path
    @relative_path ||= (path.start_with?('/') ? path[1..-1] : path)
  end

  # The URI Path
  def path
    @path ||= File.join(base_path, (eval_http_path? ? eval(%("#{http_path}"), binding, __FILE__, __LINE__) : http_path))
  end

  def path_arguments
    @path_arguments ||= Hash[
        arguments.dup.delete_if { |k, _| processed_parameters[k][:send_in] != :path }.
            map { |k,v| [ k, CGI.escape(v.respond_to?(:to_s) ? v.to_s : '').gsub('+', '%20') ] }
    ]
  end

  def query
    @query ||= begin
      query_arguments.is_a?(Hash) ? query_arguments.map { |k,v| "#{CGI.escape(k.to_s).gsub('+', '%20')}=#{CGI.escape([*v].join(',')).gsub('+', '%20')}" }.join('&') : query_arguments
    end
  end

  def query_arguments
    @query_arguments ||= arguments.dup.delete_if { |k,_| processed_parameters[k][:send_in] != :query }
  end

  def uri_request_path
    [ path ].concat( [*query].delete_if { |v| v.respond_to?(:empty?) and v.empty? } ).join('?')
  end

  # @!endgroup

  # def response
  #   client.response if client
  # end

  def http_client
    client.http_client
  end

  def http_response
    @http_response ||= http_client.response.dup rescue nil
  end

  def execute
    @response = http_client.call_method(http_method, { :path => relative_path, :query => query, :body => body }, options) if client
  end

  def success?
    _response = http_response and ([*http_success_code].include?(http_response.code))
    _response
  end

end

