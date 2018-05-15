# require 'ubiquity/wiredrive/api/v2'

module Ubiquity
  module Wiredrive
    module API
      class Client

        def self.new(args = { })
          new_v2(args)
        end

        def self.new_v2(args)
          version = '2'
          require "ubiquity/wiredrive/api/v#{version}"
          Ubiquity::Wiredrive::API::V2::Client.new(args)
        end

        def self.new_v3(args)
          version = '3'
          require "ubiquity/wiredrive/api/v#{version}"
          Ubiquity::Wiredrive::API::V3::Client.new(args)
        end

      end
    end
  end
end
# class Ubiquity::Wiredrive::API::Client
#
#   # def self.new(args = { })
#   #   # Ubiquity::Wiredrive::API::V2::Client.new(args)
#   # end
#
#
# end