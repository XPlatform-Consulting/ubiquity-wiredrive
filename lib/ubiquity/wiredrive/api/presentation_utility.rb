require 'cgi'
require 'logger'
require 'uri'

require 'ubiquity/wiredrive/api/v3/client'
module Ubiqity::Wiredrive

  class PresentationUtility

    attr_accessor :initial_args, :logger, :api_client

    def initialize(args = { })
      @initial_args = args

      initialize_logger(args)
      initialize_api_client(args)
    end

    def initialize_logger(args = { })
      @logger = args[:logger] || Logger.new(STDOUT)
    end

    def initialize_api_client(args = { })
      client_args = {  }
      @api_client = Ubiquity::Wiredrive::API::V3::Client.new(client_args)
    end

    def presentation_assets_download(args = { }, options = { })
      assets = args[:assets] || begin
        invitation_token = args[:presentation_invitation_token] || args[:invitation_token]
        invitation_password = args[:presentation_password] || args[:password]
        presentation_assets_get_using_token(invitation_token, invitation_password)
      end
      destination_path = args[:destination_path]
      assets.map do |a|
        r = presentation_asset_download(a, destination_path, options).merge(asset: a)
        yield r if block_given?
        r
      end
    end

    def presentation_asset_download(asset, destination_path, options = { })
      destination_dir = destination_path
      overwrite = options.fetch(:overwrite, false)

      media_elements = asset['media']
      # media_elements.concat asset['thumbnails']
      media_elements_download_responses = media_elements.map do |media|
        url = media['downloadUrl'] || media['url']
        uri = URI(url)
        file_name = CGI.unescape(File.basename(uri.path))
        destination_file_path = File.join(destination_dir, file_name)
        download_file(url, destination_file_path, overwrite).merge(media: media, asset: asset)
      end

      thumbnails = asset['thumbnails']
      thumbnails_download_responses = thumbnails.map do |media|
        url = media['downloadUrl'] || media['url']
        uri = URI(url)
        file_name = CGI.unescape(File.basename(uri.path)) + "_thumbnail_#{media['category']}.#{media['extension']}"
        destination_file_path = File.join(destination_dir, file_name)
        download_file(url, destination_file_path, overwrite).merge(media: media, asset: asset)
      end

      { media_element_download_responses: media_elements_download_responses, thumbnail_download_responses: thumbnails_download_responses }
    end

    # Downloads a file from a URI or file location and saves it to a local path
    #
    # @param [String] download_file_path The source path of the file being downloaded
    # @param [String] destination_file_path The destination path for the file being downloaded
    # @param [Boolean] overwrite Determines if the destination file will be overwritten if it is found to exist
    #
    # @return [Hash]
    #   * :download_file_path [String] The source path of the file being downloaded
    #   * :overwrite [Boolean] The value of the overwrite parameter when the method was called
    #   * :file_downloaded [Boolean] Indicates if the file was downloaded, will be false if overwrite was true and the file existed
    #   * :destination_file_existed [String|Boolean] The value will be 'unknown' if overwrite is true because the file exist check will not have been run inside of the method
    #   * :destination_file_path [String] The destination path for the file being downloaded
    def download_file(download_file_path, destination_file_path, overwrite = false)
      logger.debug { "Downloading '#{download_file_path}' -> '#{destination_file_path}' Overwrite: #{overwrite}" }
      file_existed = 'unknown'
      if overwrite or not (file_existed = File.exists?(destination_file_path))
        File.open(destination_file_path, 'wb') { |tf|
          open(download_file_path) { |sf| tf.write sf.read }
        }
        file_downloaded = true
      else
        file_downloaded = false
      end
      { :download_file_path => download_file_path, :overwrite => overwrite, :file_downloaded => file_downloaded, :destination_file_existed => file_existed, :destination_file_path => destination_file_path }
    end


    def presentation_assets_get_using_token(presentation_invitation_token, presentation_password = nil)
      r = presentation_get_using_token(presentation_invitation_token, presentation_password)
      r['assets']
    end

    # @param [Object]  presentation_invitation_token
    # @param [Object]  presentation_password
    # @return [Object]
    def presentation_get_using_token(presentation_invitation_token, presentation_password = nil)
      auth_token = api_client.presentation_authorize_get(token: presentation_invitation_token, password: presentation_password)
      presentation_id = api_client.response['presentation']['id']
      api_client.auth_token = auth_token
      presentation_elements = api_client.presentation_get(:id => presentation_id)
    end


  end

end
