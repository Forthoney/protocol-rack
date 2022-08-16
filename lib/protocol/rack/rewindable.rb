# frozen_string_literal: true

# Copyright, 2018, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'protocol/http/body/rewindable'
require 'protocol/http/middleware'

module Protocol
	module Rack
		# Content-type driven input buffering, specific to the needs of `rack`.
		class Rewindable < ::Protocol::HTTP::Middleware
			# Media types that require buffering.
			BUFFERED_MEDIA_TYPES = %r{
				application/x-www-form-urlencoded|
				multipart/form-data|
				multipart/related|
				multipart/mixed
			}x
			
			POST = 'POST'
			
			# Initialize the rewindable middleware.
			# @parameter app [Protocol::HTTP::Middleware] The middleware to wrap.
			def initialize(app)
				super(app)
			end
			
			# Determine whether the request needs a rewindable body.
			# @parameter request [Protocol::HTTP::Request]
			# @returns [Boolean]
			def needs_rewind?(request)
				content_type = request.headers['content-type']
				
				if request.method == POST and content_type.nil?
					return true
				end
				
				if BUFFERED_MEDIA_TYPES =~ content_type
					return true
				end
				
				return false
			end
			
			def make_environment(request)
				@delegate.make_environment(request)
			end
			
			# Wrap the request body in a rewindable buffer if required.
			# @parameter request [Protocol::HTTP::Request]
			# @returns [Protocol::HTTP::Response] the response.
			def call(request)
				if body = request.body and needs_rewind?(request)
					request.body = Protocol::HTTP::Body::Rewindable.new(body)
				end
				
				return super
			end
		end
	end
end