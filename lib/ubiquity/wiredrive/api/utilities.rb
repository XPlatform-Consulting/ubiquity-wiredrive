# require 'ubiquity/wiredrive/api/v2'

module Ubiquity
  module Wiredrive
    module API
      class Utilities

        def self.new(args = { })
          version = '2'
          require "ubiquity/wiredrive/api/v#{version}"
          Ubiquity::Wiredrive::API::V2::Utilities.new(args)
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