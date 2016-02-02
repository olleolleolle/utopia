# Copyright, 2016, by Samuel G. D. Williams. <http://www.codeotaku.com>
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

require_relative '../http'
require_relative '../path/matcher'

module Utopia
	class Controller
		module Respond
			def self.prepended(base)
				base.extend(ClassMethods)
			end
			
			# A specific conversion to a given content_type, e.g. 'application/json'.
			class Converter
				def initialize(content_type, block)
					@content_type = content_type
					@block = block
					
					self.freeze
				end
				
				def freeze
					@content_type.freeze
					@block.freeze
					
					super
				end
				
				attr :content_type
				attr :block
				
				def apply(context, response)
					status, headers, body = response
					
					# Generate a new body:
					body = body.collect{|content| context.instance_exec(content, &@block)}
					
					# Update the headers with the requested content type:
					headers = headers.merge(HTTP::CONTENT_TYPE => @content_type)
					
					return [status, headers, body]
				end
			end
			
			# Contains a set of converters which can be queried 
			class Converters
				WILDCARD = '*'.freeze
				
				def initialize
					@media_types = Hash.new{|h,k| h[k] = {}}
				end
				
				def freeze
					@media_types.freeze
					@media_types.each{|key,value| value.freeze}
					
					super
				end
				def for(patterns)
					patterns.each do |pattern|
						type, subtype = pattern.split('/')
						
						if converter = @media_types[type][subtype]
							return converter
						end
					end
					
					return nil
				end
				
				def << converter
					type, subtype = converter.content_type.split('/')
					
					if @media_types.empty?
						@media_types[WILDCARD][WILDCARD] = converter
					end
					
					if @media_types[type].empty?
						@media_types[type][WILDCARD] = converter
					end
					
					@media_types[type][subtype] = converter
				end
			end
			
			class Responder
				HTTP_ACCEPT = 'HTTP_ACCEPT'.freeze
				NOT_ACCEPTABLE_RESPONSE = [406, {}, []].freeze
				
				def initialize
					@converters = Converters.new
				end
				
				def freeze
					@converters.freeze
					@otherwise.freeze
					
					super
				end
				def browser_preferred_content_types(env)
					if accept_content_types = env[HTTP_ACCEPT]
						return HTTP::prioritised_list(accept_content_types)
					else
						return []
					end
				end
				
				def with(content_type, &block)
					@converters << Converter.new(content_type, block)
				end
				
				def invoke!(context, request, path, response)
					content_types = browser_preferred_content_types(request.env)
					
					converter = @converters.for(content_types)
					
					if converter
						return converter.apply(context, response)
					else
						LOG.debug(self.class.name) {"Could not find valid converter. Client requested #{content_types.inspect}."}
						# No converter could be found
						return NOT_ACCEPTABLE_RESPONSE
					end
				end
			end
			
			module ClassMethods
				def respond
					@responder ||= Responder.new
				end
				
				def response_for(context, request, path, response)
					if @responder
						@responder.invoke!(context, request, path, response)
					end
				end
			end
			
			# Rewrite the path before processing the request if possible.
			def passthrough(request, path)
				if response = super
					self.class.response_for(self, request, path, response) || response
				end
			end
		end
	end
end