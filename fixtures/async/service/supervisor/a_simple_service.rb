# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/a_server"

module Async
	module Service
		module Supervisor
			ASimpleService = Sus::Shared("a simple service") do
				include_context AServer
				
				let(:worker) do
					Worker.new(
						process_id: Process.pid,
						endpoint: endpoint,
						state: {name: "simple"},
					)
				end
				
				let(:connection_id) {@registration.supervisor_controller.id}
				
				before do
					@worker_task = worker.run
					@registration = registration_monitor.pop(timeout: 5)
				end
				
				after do
					GC::Profiler.disable
					
					if worker_task = @worker_task
						@worker_task = nil
						worker_task.stop
					end
				end
			end
		end
	end
end
