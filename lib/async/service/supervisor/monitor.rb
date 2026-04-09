# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/loop"

module Async
	module Service
		module Supervisor
			# Base class for supervisor monitors that run periodically within the supervisor process.
			#
			# Subclasses should override {#run_once} to implement specific monitoring logic.
			class Monitor
				# Initialize a new monitor.
				#
				# @parameter interval [Numeric] The interval in seconds between each invocation of {#run_once}.
				def initialize(interval: 1.0)
					@interval = interval
				end
				
				# Serialize the monitor state for JSON representation.
				#
				# @returns [Hash] An empty hash by default; subclasses should override to include relevant state.
				def as_json(...)
					{}
				end
				
				# Serialize to JSON string.
				def to_json(...)
					as_json.to_json(...)
				end
				
				# Get aggregated utilization status by service name.
				#
				# Reads utilization data from all registered workers and aggregates it
				# by service name (from supervisor_controller.state[:name]).
				#
				# @returns [Hash] Hash with type and data keys.
				def status
					{type: self.class.name, data: as_json}
				end
				
				# Run one iteration of the monitor.
				def run_once
					# This method can be overridden by subclasses to implement specific monitoring logic.
				end
				
				# Run the utilization monitor.
				#
				# Periodically aggregates utilization data from all workers.
				#
				# @returns [Async::Task] The task that is running the utilization monitor.
				def run(parent: Async::Task.current)
					parent.async do
						Loop.periodic(interval: @interval) do
							self.run_once
						end
					end
				end
			end
		end
	end
end
