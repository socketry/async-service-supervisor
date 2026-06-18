# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "traces/provider"

require_relative "../../../../../async/service/supervisor/supervisor_controller"

Traces::Provider(Async::Service::Supervisor::SupervisorController) do
	def register(worker, process_id:, state: {})
		attributes = {
			"worker.process_id" => process_id,
			"service.name" => state[:name],
			"monitor.count" => @server.monitors.size,
		}
		
		Traces.trace("async.service.supervisor.worker.register", attributes: attributes) do |span|
			super.tap do |id|
				span["worker.id"] = id
			end
		end
	end
end
