# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/service/environment"

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
				
				# The supervised worker for the current process.
				# @returns [Worker] The worker client.
				def supervisor_worker
					Worker.new(process_id: Process.pid, endpoint: supervisor_endpoint)
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
