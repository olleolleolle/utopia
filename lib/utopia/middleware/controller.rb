#	This file is part of the "Utopia Framework" project, and is licensed under the GNU AGPLv3.
#	Copyright 2010 Samuel Williams. All rights reserved.
#	See <utopia.rb> for licensing details.

require 'utopia/middleware'
require 'utopia/path'
require 'utopia/http_status_codes'

class Rack::Request
	def controller(&block)
		if block_given?
			env["utopia.controller"].instance_eval(&block)
		else
			env["utopia.controller"]
		end
	end
end

module Utopia
	module Middleware

		class Controller
			CONTROLLER_RB = "controller.rb"

			class Variables
				def [](key)
					instance_variable_get("@#{key}")
				end
				
				def []=(key, value)
					instance_variable_set("@#{key}", value)
				end
			end

			class Base
				def initialize(controller)
					@controller = controller
					@actions = {}

					methods.each do |method_name|
						next unless method_name.match(/on_(.*)$/)

						action($1.split("_")) do |path, request|
							# LOG.debug("Controller: #{method_name}")
							self.send(method_name, path, request)
						end
					end
				end

				def action(path, options = {}, &block)
					cur = @actions

					path.reverse.each do |name|
						cur = cur[name] ||= {}
					end

					cur[:action] = Proc.new(&block)
				end

				def lookup(path)
					cur = @actions

					path.components.reverse.each do |name|
						cur = cur[name]

						return nil if cur == nil

						if action = cur[:action]
							return action
						end
					end
				end

				# Given a request, call an associated action if one exists
				def passthrough(path, request)
					action = lookup(path)

					if action
						return respond_with(action.call(path, request))
					end

					return nil
				end

				def call(env)
					@controller.app.call(env)
				end

				def redirect(target, status = 302)
					{:redirect => target, :status => status}
				end

				def respond_with(*args)
					return args[0] if args[0] == nil || Array === args[0]

					status = 200
					options = nil

					if Numeric === args[0] || Symbol === args[0]
						status = args[0]
						options = args[1] || {}
					else
						options = args[0]
						status = options[:status] || status
					end

					status = Utopia::HTTP_STATUS_CODES[status] || status
					headers = options[:headers] || {}

					if options[:type]
						headers['Content-Type'] ||= options[:type]
					end

					if options[:redirect]
						headers["Location"] = options[:redirect]
						status = 302 if status < 300 || status >= 400
					end

					body = []
					if options[:body]
						body = options[:body]
					elsif options[:content]
						body = [options[:content]]
					elsif status >= 300
						body = [Utopia::HTTP_STATUS_DESCRIPTIONS[status] || 'Status #{status}']
					end

					# Utopia::LOG.debug([status, headers, body].inspect)
					return [status, headers, body]
				end

				def process!(path, request)
					passthrough(path, request)
				end
				
				def self.require_local(path)
					require(File.join(const_get('BASE_PATH'), path))
				end
			end

			def initialize(app, options = {})
				@app = app
				@root = options[:root] || Utopia::Middleware::default_root

				LOG.info "** #{self.class.name}: Running in #{@root}"

				@controllers = {}
				@cache_controllers = (UTOPIA_ENV == :production)

				if options[:controller_file]
					@controller_file = options[:controller_file]
				else
					@controller_file = "controller.rb"
				end
			end

			attr :app

			def lookup(path)
				if @cache_controllers
					return @controllers.fetch(path.to_s) do |key|
						@controllers[key] = load_file(path)
					end
				else
					return load_file(path)
				end
			end

			def load_file(path)
				if path.directory?
					uri_path = path
					base_path = File.join(@root, uri_path.components)
				else
					uri_path = path.dirname
					base_path = File.join(@root, uri_path.components)
				end

				controller_path = File.join(base_path, CONTROLLER_RB)

				if File.exist?(controller_path)
					klass = Class.new(Base)
					klass.const_set('BASE_PATH', base_path)
					klass.const_set('URI_PATH', uri_path)
					
					$LOAD_PATH.unshift(base_path)
					
					klass.class_eval(File.read(controller_path), controller_path)
					
					$LOAD_PATH.delete(base_path)
					
					return klass.new(self)
				else
					return nil
				end
			end

			def fetch_controllers(path)
				controllers = []
				path.ascend do |parent_path|
					controllers << lookup(parent_path)
				end

				return controllers.compact.reverse
			end

			def call(env)
				env["utopia.controller"] ||= Variables.new
				
				request = Rack::Request.new(env)

				path = Path.create(request.path_info)
				fetch_controllers(path).each do |controller|
					if result = controller.process!(path, request)
						return result
					end
				end

				return @app.call(env)
			end
		end

	end
end
