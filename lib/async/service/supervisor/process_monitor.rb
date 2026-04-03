# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "process/metrics"
require_relative "monitor"

module Async
	module Service
		module Supervisor
			# Monitors process metrics and logs them periodically.
			#
			# Uses the `process-metrics` gem to capture CPU and memory metrics for a process tree.
			# Unlike {MemoryMonitor}, this monitor captures metrics for the entire process tree
			# by tracking the parent process ID (ppid), which is more efficient than tracking
			# individual processes.
			class ProcessMonitor < Monitor
				# Create a new process monitor.
				#
				# @parameter interval [Integer] The interval in seconds at which to log process metrics.
				# @parameter ppid [Integer] The parent process ID to monitor. If nil, uses the current process to capture its children.
				def initialize(interval: 60, ppid: nil)
					super(interval: interval)
					@ppid = ppid || Process.ppid
				end
				
				# @attribute [Integer] The parent process ID being monitored.
				attr :ppid
				
				# Register a worker with the process monitor.
				#
				# This is provided for consistency with {MemoryMonitor}, but since we monitor
				# the entire process tree via ppid, we don't need to track individual workers.
				#
				# @parameter supervisor_controller [SupervisorController] The supervisor controller for the worker.
				def register(supervisor_controller)
					process_id = supervisor_controller.process_id
					Console.debug(self, "Worker registered.", supervisor_controller: supervisor_controller, process_id: process_id)
				end
				
				# Remove a worker from the process monitor.
				#
				# This is provided for consistency with {MemoryMonitor}, but since we monitor
				# the entire process tree via ppid, we don't need to track individual workers.
				#
				# @parameter supervisor_controller [SupervisorController] The supervisor controller for the worker.
				def remove(supervisor_controller)
					process_id = supervisor_controller.process_id
					Console.debug(self, "Worker removed.", supervisor_controller: supervisor_controller, process_id: process_id)
				end
				
				# Capture current process metrics for the entire process tree.
				#
				# @returns [Hash] A hash mapping process IDs to their metrics.
				def metrics
					Process::Metrics::General.capture(ppid: @ppid).transform_values!(&:as_json)
				end
				
				# The key used when this monitor's status is aggregated with others.
				def self.monitor_type
					:process_monitor
				end
				
				# Serialize process metrics for JSON.
				def as_json
					{ppid: @ppid, metrics: self.metrics}
				end
				
				# Run one iteration of the process monitor.
				def run_once
					metrics = self.metrics
					
					# Log each process individually for better searchability in log platforms:
					metrics.each do |process_id, general|
						Console.info(self, "Process metrics captured.", general: general)
					end
				end
			end
		end
	end
end

