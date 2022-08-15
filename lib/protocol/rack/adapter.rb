# frozen_string_literal: true

# Copyright, 2017, by Samuel G. D. Williams. <http://www.codeotaku.com>
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

require 'console'

require_relative 'constants'
require_relative 'input'
require_relative 'response'

module Protocol
	module Rack
		class Adapter
			PROTOCOL_HTTP_REQUEST = "protocol.http.request"
		
			# Header constants:
			HTTP_X_FORWARDED_PROTO = 'HTTP_X_FORWARDED_PROTO'
		
			# Initialize the rack adaptor middleware.
			# @parameter app [Object] The rack middleware.
			def initialize(app)
				@app = app
				
				raise ArgumentError, "App must be callable!" unless @app.respond_to?(:call)
			end
			
			def logger
				Console.logger
			end

			# Unwrap raw HTTP headers into the CGI-style expected by Rack middleware.
			#
			# Rack separates multiple headers with the same key, into a single field with multiple lines.
			#
			# @parameter headers [Protocol::HTTP::Headers] The raw HTTP request headers.
			# @parameter env [Hash] The rack request `env`.
			def unwrap_headers(headers, env)
				headers.each do |key, value|
					http_key = "HTTP_#{key.upcase.tr('-', '_')}"
					
					if current_value = env[http_key]
						env[http_key] = "#{current_value};#{value}"
					else
						env[http_key] = value
					end
				end
			end
			
			# Process the incoming request into a valid rack `env`.
			#
			# - Set the `env['CONTENT_TYPE']` and `env['CONTENT_LENGTH']` based on the incoming request body. 
			# - Set the `env['HTTP_HOST']` header to the request authority.
			# - Set the `env['HTTP_X_FORWARDED_PROTO']` header to the request scheme.
			# - Set `env['REMOTE_ADDR']` to the request remote adress.
			#
			# @parameter request [Protocol::HTTP::Request] The incoming request.
			# @parameter env [Hash] The rack `env`.
			def unwrap_request(request, env)
				if content_type = request.headers.delete('content-type')
					env[CONTENT_TYPE] = content_type
				end
				
				# In some situations we don't know the content length, e.g. when using chunked encoding, or when decompressing the body.
				if body = request.body and length = body.length
					env[CONTENT_LENGTH] = length.to_s
				end
				
				self.unwrap_headers(request.headers, env)
				
				# HTTP/2 prefers `:authority` over `host`, so we do this for backwards compatibility.
				env[HTTP_HOST] ||= request.authority
				
				# This is the HTTP/1 header for the scheme of the request and is used by Rack. Technically it should use the Forwarded header but this is not common yet.
				# https://tools.ietf.org/html/rfc7239#section-5.4
				# https://github.com/rack/rack/issues/1310
				env[HTTP_X_FORWARDED_PROTO] ||= request.scheme
				
				if remote_address = request.remote_address
					env[REMOTE_ADDR] = remote_address.ip_address if remote_address.ip?
				end
			end
			
			# Build a rack `env` from the incoming request and apply it to the rack middleware.
			#
			# @parameter request [Protocol::HTTP::Request] The incoming request.
			def call(request)
				request_path, query_string = request.path.split('?', 2)
				server_name, server_port = (request.authority || '').split(':', 2)
				
				env = {
					PROTOCOL_HTTP_REQUEST => request,
					
					RACK_INPUT => Input.new(request.body),
					RACK_ERRORS => $stderr,
					RACK_LOGGER => self.logger,

					# The request protocol, either from the upgrade header or the HTTP/2 pseudo header of the same name.
					RACK_PROTOCOL => request.protocol,
					
					# The HTTP request method, such as “GET” or “POST”. This cannot ever be an empty string, and so is always required.
					CGI::REQUEST_METHOD => request.method,
					
					# The initial portion of the request URL's “path” that corresponds to the application object, so that the application knows its virtual “location”. This may be an empty string, if the application corresponds to the “root” of the server.
					CGI::SCRIPT_NAME => '',
					
					# The remainder of the request URL's “path”, designating the virtual “location” of the request's target within the application. This may be an empty string, if the request URL targets the application root and does not have a trailing slash. This value may be percent-encoded when originating from a URL.
					CGI::PATH_INFO => request_path,
					CGI::REQUEST_PATH => request_path,
					CGI::REQUEST_URI => request.path,

					# The portion of the request URL that follows the ?, if any. May be empty, but is always required!
					CGI::QUERY_STRING => query_string || '',
					
					# The server protocol (e.g. HTTP/1.1):
					CGI::SERVER_PROTOCOL => request.version,
					
					# The request scheme:
					RACK_URL_SCHEME => request.scheme,
					
					# I'm not sure what sane defaults should be here:
					CGI::SERVER_NAME => server_name,
					CGI::SERVER_PORT => server_port,
				}
				
				self.unwrap_request(request, env)
				
				status, headers, body = @app.call(env)
				
				return Response.wrap(request, status, headers, body)
			rescue => exception
				Console.logger.error(self) {exception}
				
				body&.close if body.respond_to?(:close)

				return failure_response(exception)
			end
			
			private

			# Generate a suitable response for the given exception.
			# @parameter exception [Exception]
			# @returns [Protocol::HTTP::Response]
			def failure_response(exception)
				Protocol::HTTP::Response.for_exception(exception)
			end
		end
	end
end
