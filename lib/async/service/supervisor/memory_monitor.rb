# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "memory/leak/cluster"
require "set"

require_relative "monitor"

module Async
	module Service
		module Supervisor
			# Monitors worker memory usage and restarts workers that exceed limits.
			#
			# Uses the `memory` gem to track process memory and detect leaks.
			class MemoryMonitor < Monitor
				# Create a new memory monitor.
				#
				# @parameter interval [Integer] The interval at which to check for memory leaks.
				# @parameter total_size_limit [Integer] The total size limit of all processes, or nil for no limit.
				# @parameter free_size_minimum [Integer] The minimum free memory threshold, or nil for no threshold.
				# @parameter options [Hash] Options to pass to the cluster when adding processes.
				def initialize(interval: 10, total_size_limit: nil, free_size_minimum: nil, **options)
					super(interval: interval)
					@cluster = Memory::Leak::Cluster.new(total_size_limit: total_size_limit, free_size_minimum: free_size_minimum)
					
					# We use these options when adding processes to the cluster:
					@options = options
					
					@processes = Hash.new{|hash, key| hash[key] = Set.new.compare_by_identity}
					
					# Queue to serialize cluster modifications to prevent race conditions:
					@guard = Mutex.new
				end
				
				# @attribute [Memory::Leak::Cluster] The cluster of processes being monitored.
				attr_reader :cluster
				
				# Add a process to the memory monitor. You may override this to control how processes are added to the cluster.
				#
				# @parameter process_id [Integer] The process ID to add.
				def add(process_id)
					@cluster.add(process_id, **@options)
				end
				
				# Register a worker with the memory monitor.
				#
				# @parameter supervisor_controller [SupervisorController] The supervisor controller for the worker.
				def register(supervisor_controller)
					process_id = supervisor_controller.process_id
					return unless process_id
					
					Console.debug(self, "Registering worker.", supervisor_controller: supervisor_controller, process_id: process_id)
					
					@guard.synchronize do
						controllers = @processes[process_id]
						
						if controllers.empty?
							Console.debug(self, "Registering process.", child: {process_id: process_id})
							self.add(process_id)
						end
						
						controllers.add(supervisor_controller)
					end
				end
				
				# Remove a worker from the memory monitor.
				#
				# @parameter supervisor_controller [SupervisorController] The supervisor controller for the worker.
				def remove(supervisor_controller)
					process_id = supervisor_controller.process_id
					return unless process_id
					
					@guard.synchronize do
						controllers = @processes[process_id]
						
						controllers.delete(supervisor_controller)
						
						if controllers.empty?
							Console.debug(self, "Removing process.", child: {process_id: process_id})
							@cluster.remove(process_id)
							@processes.delete(process_id)
						end
					end
				end
				
				# Serialize memory cluster data for JSON.
				def as_json
					@cluster.as_json
				end
				
				# Invoked when a memory leak is detected.
				#
				# @parameter process_id [Integer] The process ID of the process that has a memory leak.
				# @parameter monitor [Memory::Leak::Monitor] The monitor that detected the memory leak.
				# @returns [Boolean] True if the process was killed.
				def memory_leak_detected(process_id, monitor)
					Console.warn(self, "Memory leak detected!", child: {process_id: process_id}, monitor: monitor)
					
					# Kill the process gently:
					begin
						Console.info(self, "Killing process!", child: {process_id: process_id})
						Process.kill(:INT, process_id)
					rescue Errno::ESRCH
						# No such process - he's dead Jim.
					rescue => error
						Console.warn(self, "Failed to kill process!", child: {process_id: process_id}, exception: error)
					end
					
					true
				end
				
				# Run one iteration of the memory monitor.
				def run_once
					@guard.synchronize do
						# This block must return true if the process was killed.
						@cluster.check! do |process_id, monitor|
							begin
								memory_leak_detected(process_id, monitor)
							rescue => error
								Console.error(self, "Failed to handle memory leak!", child: {process_id: process_id}, exception: error)
							end
						end
					end
				end
			end
		end
	end
end

