# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async"
require "async/service/managed/service"
require "io/endpoint/bound_endpoint"

module Async
	module Service
		module Supervisor
			# The supervisor service implementation.
			#
			# Manages the lifecycle of the supervisor server and its monitors.
			class Service < Async::Service::Managed::Service
				# Initialize the supervisor using the given environment.
				# @parameter environment [Build::Environment]
				def initialize(...)
					super
					
					@bound_endpoint = nil
				end
				
				# The endpoint which the supervisor will bind to.
				# Typically a unix pipe in the same directory as the host.
				def endpoint
					@evaluator.endpoint
				end
				
				# Bind the supervisor to the specified endpoint.
				def start
					@bound_endpoint = self.endpoint.bound
					
					super
				end
				
				# Format the process title for the supervisor.
				#
				# @parameter evaluator [Environment::Evaluator] The environment evaluator.
				# @parameter server [Server] The supervisor server instance.
				# @returns [String] The formatted process title.
				private def format_title(evaluator, server)
					"#{evaluator.name} (#{server.controllers.size} workers)"
				end
				
				# Run the supervisor server.
				#
				# @parameter instance [Async::Container::Instance] The container instance.
				# @parameter evaluator [Environment::Evaluator] The environment evaluator.
				# @returns [Server] The supervisor server instance.
				def run(instance, evaluator)
					server = evaluator.make_server(@bound_endpoint)
					
					Async do |task|
						server.run
					end
					
					# Return the server for health checking and process title formatting
					server
				end
				
				# Release the bound endpoint.
				def stop
					@bound_endpoint&.close
					@bound_endpoint = nil
					
					super
				end
			end
		end
	end
end

