# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "metrics/provider"
require "metrics/tags"

require_relative "../../../../../async/service/supervisor/utilization_monitor"

class Async::Service::Supervisor::UtilizationMonitor
	Metrics::Provider(self) do
		UTILIZATION = Metrics.metric("async.utilization", :gauge, description: "Active requests per worker.")
		UTILIZATION_CONNECTIONS_ACTIVE = Metrics.metric("async.utilization.connections.active", :gauge, description: "The number of active connections.")
		UTILIZATION_CONNECTIONS_TOTAL = Metrics.metric("async.utilization.connections.total", :gauge, description: "The total number of connections.")
		UTILIZATION_REQUESTS_ACTIVE = Metrics.metric("async.utilization.requests.active", :gauge, description: "The number of active requests.")
		UTILIZATION_REQUESTS_TOTAL = Metrics.metric("async.utilization.requests.total", :gauge, description: "The total number of requests.")
		UTILIZATION_WORKERS = Metrics.metric("async.utilization.workers", :gauge, description: "The number of workers contributing utilization metrics.")
		
		def emit(metrics)
			metrics.each do |service_name, fields|
				tags = Metrics::Tags.normalize(service: service_name)
				
				if connections_active = fields[:connections_active]
					UTILIZATION_CONNECTIONS_ACTIVE.emit(connections_active, tags: tags)
				end
				
				if connections_total = fields[:connections_total]
					UTILIZATION_CONNECTIONS_TOTAL.emit(connections_total, tags: tags)
				end
				
				if requests_active = fields[:requests_active]
					UTILIZATION_REQUESTS_ACTIVE.emit(requests_active, tags: tags)
				end
				
				if requests_total = fields[:requests_total]
					UTILIZATION_REQUESTS_TOTAL.emit(requests_total, tags: tags)
				end
				
				if worker_count = fields[:worker_count]
					UTILIZATION_WORKERS.emit(worker_count, tags: tags)
					
					if worker_count > 0 and requests_active = fields[:requests_active]
						UTILIZATION.emit(requests_active.to_f / worker_count, tags: tags)
					end
				end
			end
			
			super
		end
	end
end
