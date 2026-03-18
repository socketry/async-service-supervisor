# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "memory/leak/cluster"
require "set"

require_relative "loop"

module Async
	module Service
		module Supervisor
			# Monitors worker memory usage and restarts workers that exceed limits.
			#
			# Uses the `memory` gem to track process memory and detect leaks.
			class MemoryMonitor
				# Create a new memory monitor.
				#
				# @parameter interval [Integer] The interval at which to check for memory leaks.
				# @parameter total_size_limit [Integer] The total size limit of all processes, or nil for no limit.
				# @parameter free_size_minimum [Integer] The minimum free memory threshold, or nil for no threshold.
				# @parameter options [Hash] Options to pass to the cluster when adding processes.
				def initialize(interval: 10, total_size_limit: nil, free_size_minimum: nil, **options)
					@interval = interval
					@cluster = Memory::Leak::Cluster.new(total_size_limit: total_size_limit, free_size_minimum: free_size_minimum)
					
					# We use these options when adding processes to the cluster:
					@options = options
					
					@processes = Hash.new{|hash, key| hash[key] = Set.new.compare_by_identity}
					
					@exceeded = Set.new
					
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
							@exceeded.delete(process_id)
						end
					end
				end
				
				# The key used when this monitor's status is aggregated with others.
				def self.monitor_type
					:memory_monitor
				end
				
				# Serialize memory cluster data for JSON.
				def as_json
					@cluster.as_json
				end
				
				# Serialize to JSON string.
				def to_json(...)
					as_json.to_json(...)
				end
				
				# Get status for the memory monitor.
				#
				# @returns [Hash] Hash with type and data keys.
				def status
					{type: self.class.monitor_type, data: as_json}
				end
				
				protected def invoke_garbage_collection(process_id)
					Console.info(self, "Invoking garbage collection!", child: {process_id: process_id})
					
					controllers = @processes[process_id]
					supervisor_controller = controllers&.to_a&.first
					if supervisor_controller&.worker
						supervisor_controller.worker.garbage_collect(full_mark: true, immediate_sweep: true)
						
						return true
					end
					
					return false
				rescue => error
					Console.error(self, "Failed to invoke garbage collection!", child: {process_id: process_id}, exception: error)
					
					return false
				end
				
				protected def kill_process(process_id)
					Process.kill(:INT, process_id)
				rescue Errno::ESRCH
					# No such process - he's dead Jim.
					return true
				rescue => error
					Console.warn(self, "Failed to kill process!", child: {process_id: process_id}, exception: error)
					
					return false
				end
				
				# Invoked when a leaking process is detected. Implements two-phase response: first
				# invokes GC via RPC (if worker is registered); on the next check, kills the process.
				#
				# @parameter process_id [Integer] The process ID of the process that has a memory leak.
				# @parameter monitor [Memory::Leak::Monitor] The monitor that detected the memory leak.
				def handle_leaking_process(process_id, monitor)
					# First time exceeded, run garbage collection:
					@exceeded.add(process_id)
					
					if !invoke_garbage_collection(process_id)
						memory_leak_detected(process_id, monitor)
					end
					
					# Always return true as we have processed the memory leak:
					return true
				rescue => error
					Console.warn(self, "Failed to handle memory leak!", child: {process_id: process_id}, exception: error)
					
					# For whatever reason, we failed to process the memory leak, the cluster should move on to the next process:
					return false
				end
				
				# Invoked when a process must be killed. Performs the actual termination.
				#
				# @parameter process_id [Integer] The process ID of the process that has a memory leak.
				# @parameter monitor [Memory::Leak::Monitor] The monitor that detected the memory leak.
				# @returns [Boolean] True if the process was killed.
				def memory_leak_detected(process_id, monitor)
					Console.warn(self, "Memory leak detected!", child: {process_id: process_id}, monitor: monitor)
					
					return kill_process(process_id)
				end
				
				# Run one check iteration (used by #run, exposed for testing).
				def check_cluster
					checked = Set.new
					
					@cluster.check! do |process_id, monitor|
						checked.add(process_id)
						
						if @exceeded.include?(process_id)
							memory_leak_detected(process_id, monitor)
						else
							handle_leaking_process(process_id, monitor)
						end
					end
					
					@exceeded &= checked
					
					return @exceeded
				end
				
				# Run the memory monitor.
				#
				# @returns [Async::Task] The task that is running the memory monitor.
				def run
					Async do
						Loop.run(interval: @interval) do
							@guard.synchronize{check_cluster}
						end
					end
				end
			end
		end
	end
end

