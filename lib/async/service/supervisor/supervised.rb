# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/service/environment"
require "async/utilization"

module Async
	module Service
		module Supervisor
			# An environment mixin for supervised worker services.
			#
			# Enables workers to connect to and be supervised by the supervisor.
			module Supervised
				# The IPC path to use for communication with the supervisor.
				# @returns [String]
				def supervisor_ipc_path
					::File.expand_path("supervisor.ipc", root)
				end
				
				# The endpoint the supervisor will bind to.
				# @returns [::IO::Endpoint::Generic]
				def supervisor_endpoint
					::IO::Endpoint.unix(supervisor_ipc_path)
				end
				
				# The state to associate with the supervised worker.
				# @returns [Hash]
				def supervisor_worker_state
					{name: self.name}
				end
				
				# A default schema for utilization metrics.
				# @returns [Hash | Nil] The utilization schema or nil if utilization is disabled.
				def utilization_schema
					{
						connections_active: :u32,
						connections_total: :u64,
						requests_active: :u32,
						requests_total: :u64,
					}
				end
				
				# Get the utilization registry for this service.
				#
				# Creates a new registry instance for tracking utilization metrics.
				# This registry is used by workers to emit metrics that can be collected
				# by the supervisor's utilization monitor.
				#
				# @returns [Async::Utilization::Registry] A new utilization registry instance.
				def utilization_registry
					Async::Utilization::Registry.new
				end
				
				# The supervised worker for the current process.
				# @returns [Worker] The worker client.
				def supervisor_worker
					Worker.new(
						process_id: Process.pid,
						endpoint: supervisor_endpoint,
						state: self.supervisor_worker_state,
						utilization_schema: self.utilization_schema,
						utilization_registry: self.utilization_registry,
					)
				end
				
				# Create a supervised worker for the given instance.
				#
				# @parameter instance [Async::Container::Instance] The container instance.
				# @returns [Worker] The worker client.
				def prepare!(instance)
					super(instance)
					
					supervisor_worker.run
				end
			end
		end
	end
end
