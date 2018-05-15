class Ubiquity::Wiredrive::API::V3::Client::Paginator

  attr_accessor :api_client

  attr_reader :total_results, :last_page_number, :next_page_number, :prev_page_number, :page_size

  def initialize(api_client)
    @api_client = api_client

    process_response
  end

  def logger
    api_client.logger
  end

  def http_client
    api_client.http_client
  end

  def process_response
    http_response = http_client.response

    @total_results = http_response['total']
    @paginated = !!total_results

    process_link_header(http_response['links']) if paginated?
  end

  def process_link_header(link)
    links = link.split(',')
    @next_page_number = nil
    @prev_page_number = nil

    links.map! do |k, v|
      # href, rel = l.split('; ')
      # rel = rel.match(/"(\w*)/)[1]
      # href = href.match(/<(.*)>/)[1]
      # _, query = href.split('?')
      # query_as_hash = Hash[ query.split('&').map { |v| v.split('=') } ]
      # @page_size = query_as_hash['_pageSize']
      #
      # case rel
      #   when 'next'
      #     @next_page_number = query_as_hash['_page']
      #     @next_page_href = href
      #   when 'last'
      #     @last_page_number = query_as_hash['_page']
      #     @last_page_href = href
      #   when 'prev'
      #     @prev_page_number = query_as_hash['_page']
      #     @prev_page_href = href
      # end
      #
      # [ rel, href ]
      [ k, v ]
    end
    @has_next_page = !!@next_page_number
    @has_prev_page = !!@prev_page_number

    Hash[links]
  end

  def request
    @request ||= api_client.request
  end

  def request_args_out
    @request_args_out ||= request.initial_arguments.dup
  end

  def request_options_out
    @request_options_out ||= { :client => api_client }.merge request.initial_options.dup
  end

  def paginated?
    @paginated
  end

  def next_page?
    @has_next_page
  end

  def next_page_get(_next_page_number = @next_page_number)
    page_get(_next_page_number)
  end

  def page_get(page_number)
    logger.debug { "Getting Page #{page_number} of #{last_page_number}" }
    new_request = request.class.new(request_args_out.merge('_page' => page_number), request_options_out)
    _response = new_request.execute
    process_response
    _response
  end

  def pages_get(pages, options = { })
    consolidate = options.fetch(:consolidate, true)
    pages = pages.to_a if pages.respond_to?(:to_a)
    pages_out = pages.map { |v| page_get(v) }
    pages_out.flatten! if consolidate
    pages_out
  end

  def prev_page?
    @has_prev_page
  end

  def prev_page_get(_prev_page_number = @prev_page_number)
    return [ ] unless paginated?
    page_get(_prev_page_number)
  end

  def include_remaining_pages
    response = api_client.response.dup
    response.concat(remaining_pages_get)
  end

  def remaining_pages_get
    return [ ] unless paginated? && next_page?
    _next_page_number = @next_page_number
    remaining_results = [ ]

    loop do
      response = next_page_get(_next_page_number)
      break unless response.is_a?(Array)
      remaining_results.concat(response)

      break unless next_page?
      _next_page_number = next_page_number
    end
    remaining_results
  end

end