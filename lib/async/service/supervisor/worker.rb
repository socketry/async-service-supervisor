# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require_relative "client"
require_relative "worker_controller"

module Async
	module Service
		module Supervisor
			# A worker represents a long running process that can be controlled by the supervisor.
			#
			# There are various tasks that can be executed by the worker, such as dumping memory, threads, and garbage collection profiles.
			class Worker < Client
				# Run a worker with the given process ID.
				#
				# @parameter process_id [Integer] The process ID to register with the supervisor.
				# @parameter endpoint [IO::Endpoint] The supervisor endpoint to connect to.
				def self.run(process_id: Process.pid, endpoint: Supervisor.endpoint)
					self.new(process_id: process_id, endpoint: endpoint).run
				end
				
				# Initialize a new worker.
				#
				# @parameter process_id [Integer] The process ID to register with the supervisor.
				# @parameter endpoint [IO::Endpoint] The supervisor endpoint to connect to.
				def initialize(process_id: Process.pid, endpoint: Supervisor.endpoint)
					super(endpoint: endpoint)
					
					@id = nil
					@process_id = process_id
				end
				
				# @attribute [Integer] The ID assigned by the supervisor.
				attr :id
				
				# @attribute [Integer] The process ID of the worker.
				attr :process_id
				
				protected def connected!(connection)
					super
					
					# Create and bind worker controller
					worker_controller = WorkerController.new(self)
					worker_proxy = connection.bind(:worker, worker_controller)
					
					# Register the worker with the supervisor
					# The supervisor allocates a unique ID and returns it
					# This is a synchronous RPC call that will complete before returning
					supervisor = connection[:supervisor]
					@id = supervisor.register(worker_proxy, process_id: @process_id)
				end
			end
		end
	end
end

