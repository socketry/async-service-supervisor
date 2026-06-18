# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "metrics/provider"

require_relative "../../../../../async/service/supervisor/process_monitor"

class Async::Service::Supervisor::ProcessMonitor
	Metrics::Provider(self) do
		PROCESS_METRICS_GENERAL_PROCESSOR_UTILIZATION = Metrics.metric("process.metrics.general.processor_utilization", :gauge, description: "Processor utilization for a supervised process.")
		PROCESS_METRICS_GENERAL_TOTAL_SIZE = Metrics.metric("process.metrics.general.total_size", :gauge, description: "Total memory size for a supervised process.", unit: "bytes")
		PROCESS_METRICS_GENERAL_VIRTUAL_SIZE = Metrics.metric("process.metrics.general.virtual_size", :gauge, description: "Virtual memory size for a supervised process.", unit: "bytes")
		PROCESS_METRICS_GENERAL_RESIDENT_SIZE = Metrics.metric("process.metrics.general.resident_size", :gauge, description: "Resident memory size for a supervised process.", unit: "bytes")
		
		def emit(metrics)
			metrics.each_value do |general|
				if value = general[:processor_utilization]
					PROCESS_METRICS_GENERAL_PROCESSOR_UTILIZATION.emit(value)
				end
				
				if value = general[:total_size]
					PROCESS_METRICS_GENERAL_TOTAL_SIZE.emit(value)
				end
				
				if value = general[:virtual_size]
					PROCESS_METRICS_GENERAL_VIRTUAL_SIZE.emit(value)
				end
				
				if value = general[:resident_size]
					PROCESS_METRICS_GENERAL_RESIDENT_SIZE.emit(value)
				end
			end
			
			super
		end
	end
end
