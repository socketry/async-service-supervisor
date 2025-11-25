# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/controller"

module Async
	module Service
		module Supervisor
			# Controller for supervisor operations.
			#
			# Handles registration of workers, worker lookup, restarting process groups, and status queries.
			class SupervisorController < Async::Bus::Controller
				def initialize(server, connection)
					@server = server
					@connection = connection
					
					@id = nil
					@process_id = nil
					@worker = nil
				end
				
				# @attribute [Server] The server instance.
				attr :server
				
				# @attribute [Connection] The connection instance.
				attr :connection
				
				# @attribute [Integer] The ID assigned to this worker.
				attr :id
				
				# @attribute [Integer] The process ID of the worker.
				attr :process_id
				
				# @attribute [Proxy] The proxy to the worker controller.
				attr :worker
				
				# Register a worker connection with the supervisor.
				#
				# Allocates a unique sequential ID, stores the worker controller proxy,
				# and notifies all monitors of the new connection.
				#
				# @parameter worker [Proxy] The proxy to the worker controller.
				# @parameter process_id [Integer] The process ID of the worker.
				# @returns [Integer] The connection ID assigned to the worker.
				def register(worker, process_id:)
					raise RuntimeError, "Already registered" if @id
					
					@id = @server.next_id
					@process_id = process_id
					@worker = worker
					
					@server.add(self)
					
					return @id
				end
				
				# Get a worker controller proxy by connection ID.
				#
				# Returns a proxy to the worker controller that can be used to invoke
				# operations directly on the worker. The proxy uses multi-hop forwarding
				# to route calls through the supervisor to the worker.
				#
				# @example Accessing a worker
				#   supervisor = connection[:supervisor]
				#   worker = supervisor[id]
				#   worker.memory_sample(duration: 10)
				#
				# @parameter id [Integer] The ID of the worker.
				# @returns [Proxy] A proxy to the worker controller.
				# @raises [ArgumentError] If the connection ID is not found.
				def [](id)
					unless id
						raise ArgumentError, "Missing 'id' parameter"
					end
					
					supervisor_controller = @server.controllers[id]
					
					unless supervisor_controller
						raise ArgumentError, "Connection not found: #{id}"
					end
					
					worker = supervisor_controller.worker
					
					unless worker
						raise ArgumentError, "Worker controller not found for connection: #{id}"
					end
					
					return worker
				end
				
				# List all registered worker IDs.
				#
				# @returns [Array(Integer)] An array of  IDs for all registered workers.
				def keys
					@server.controllers.keys
				end
				
				# Restart the current process group, usually including the supervisor and any other processes.
				#
				# @parameter signal [Symbol] The signal to send to the process group.
				def restart(signal: :INT)
					# We are going to terminate the process group, including *this* process
					::Process.kill(signal, ::Process.ppid)
				end
				
				# Query the status of the supervisor and all connected workers.
				#
				# Returns an array of status information from each monitor.
				# Each monitor provides its own status representation.
				#
				# @returns [Array] An array of status information from each monitor.
				def status
					@server.monitors.map do |monitor|
						begin
							monitor.status
						rescue => error
							error
						end
					end.compact
				end
			end
		end
	end
end

