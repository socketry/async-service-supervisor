# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "traces/provider"

require_relative "../../../../../async/service/supervisor/server"

Traces::Provider(Async::Service::Supervisor::Server) do
	def remove(controller)
		return super unless controller.id
		
		attributes = {
			"worker.id" => controller.id,
			"worker.process_id" => controller.process_id,
			"service.name" => controller.state[:name],
			"monitor.count" => @monitors.size,
		}
		
		Traces.trace("async.service.supervisor.worker.remove", attributes: attributes) do
			super
		end
	end
end
