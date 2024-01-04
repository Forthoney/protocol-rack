# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2022-2023, by Samuel Williams.

require 'rack'

require_relative 'adapter/rack2'
require_relative 'adapter/rack3'

module Protocol
	module Rack
		module Adapter
			if ::Rack.release >= "3"
				IMPLEMENTATION = Rack3
			else
				IMPLEMENTATION = Rack2
			end
			
			def self.new(app, console)
				IMPLEMENTATION.wrap(app, console)
			end
			
			def self.make_response(env, response)
				IMPLEMENTATION.make_response(env, response)
			end
		end
	end
end
