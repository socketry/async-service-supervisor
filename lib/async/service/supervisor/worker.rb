# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

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
				# @parameter state [Hash] Optional state to associate with this worker (e.g., service name).
				# @parameter utilization_schema [Hash | Nil] Optional utilization schema definition.
				# @parameter utilization_registry [Registry, nil] Optional utilization registry. If nil, a new registry is created.
				def initialize(process_id: Process.pid, endpoint: Supervisor.endpoint, state: {}, utilization_schema: nil, utilization_registry: nil)
					super(endpoint: endpoint)
					
					@id = nil
					@process_id = process_id
					@state = state
					
					@utilization_schema = utilization_schema
					@utilization_registry = utilization_registry || require("async/utilization") && Async::Utilization::Registry.new
				end
				
				# @attribute [Integer] The ID assigned by the supervisor.
				attr :id
				
				# @attribute [Integer] The process ID of the worker.
				attr :process_id
				
				# @attribute [Hash] State associated with this worker (e.g., service name).
				attr_accessor :state
				
				# @attribute [Hash | Nil] Utilization schema definition.
				attr :utilization_schema
				
				# @attribute [Registry] The utilization registry for this worker.
				attr :utilization_registry
				
				# Setup utilization observer for this worker.
				#
				# Delegates to WorkerController to set up the shared memory observer.
				# This method is called by the supervisor to inform the worker of the shared memory
				# file path and allocated offset.
				#
				# @parameter path [String] Path to the shared memory file that the worker should map.
				# @parameter size [Integer] Size of the shared memory region to map.
				# @parameter offset [Integer] Offset into the shared memory buffer allocated for this worker.
				# @returns [Array] Array of [key, type, offset] tuples describing the utilization schema.
				#   Returns empty array if no utilization schema is configured.
				def setup_utilization_observer(path, size, offset)
					controller = WorkerController.new(self)
					controller.setup_utilization_observer(path, size, offset)
				end
				
				protected def connected!(connection)
					super
					
					# Create and bind worker controller
					worker_controller = WorkerController.new(self)
					worker_proxy = connection.bind(:worker, worker_controller)
					
					# Register the worker with the supervisor
					# The supervisor allocates a unique ID and returns it
					# This is a synchronous RPC call that will complete before returning
					supervisor = connection[:supervisor]
					@id = supervisor.register(worker_proxy, process_id: @process_id, state: @state)
				end
			end
		end
	end
end
