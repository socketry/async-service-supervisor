# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "monitor"
require "async/utilization"

module Async
	module Service
		module Supervisor
			# Monitors worker utilization metrics aggregated by service name.
			#
			# Uses shared memory to efficiently collect utilization metrics from workers
			# and aggregates them by service name for monitoring and reporting.
			class UtilizationMonitor < Monitor
				# @deprecated Use {Async::Utilization::SegmentAllocator} instead.
				SegmentAllocator = Async::Utilization::SegmentAllocator
				
				# Initialize a new utilization monitor.
				#
				# @parameter path [String] Path to the shared memory file.
				# @parameter interval [Integer] Interval in seconds to aggregate and update metrics.
				# @parameter size [Integer] Total size of the shared memory buffer.
				# @parameter segment_size [Integer] Size of each allocation segment (default: 512 bytes).
				def initialize(path: "utilization.shm", interval: 10, size: IO::Buffer::PAGE_SIZE * 8, segment_size: 512)
					super(interval: interval)
					@path = path
					@segment_size = segment_size
					
					@allocator = Async::Utilization::SegmentAllocator.open(path, size: size, segment_size: segment_size, replace: true)
					
					# Track workers: worker_id => supervisor_controller
					@workers = {}
					
					@guard = Mutex.new
				end
				
				# Register a worker with the utilization monitor.
				#
				# Allocates a segment of shared memory and instructs the worker
				# to map the shared memory file and expose utilization information at the allocated offset.
				# The worker maps the file independently and returns its schema.
				#
				# @parameter supervisor_controller [SupervisorController] The supervisor controller for the worker.
				def register(supervisor_controller)
					@guard.synchronize do
						worker_id = supervisor_controller.id
						return unless worker_id
						
						# Allocate a segment first (we'll get schema from worker)
						offset = @allocator.allocate(worker_id, [])
						
						unless offset
							Console.warn(self, "Failed to allocate utilization segment", worker_id: worker_id)
							return
						end
						
						# Inform worker of the shared memory path, size, and allocated offset
						# The worker will map the file itself and return its schema
						begin
							worker = supervisor_controller.worker
							
							if worker
								# Pass the segment size - observer will handle page alignment and file mapping
								schema = worker.setup_utilization_observer(@path, @segment_size, offset)
								
								# Update the allocation with the actual schema
								if schema && !schema.empty?
									@allocator.update_schema(worker_id, schema)
									@workers[worker_id] = supervisor_controller
									
									Console.info(self, "Registered worker utilization", worker_id: worker_id, offset: offset, schema: schema)
								else
									# Worker didn't provide schema, free the allocation
									@allocator.free(worker_id)
									Console.info(self, "Worker did not provide utilization schema", worker_id: worker_id)
								end
							end
						rescue => error
							Console.error(self, "Error setting up worker utilization", worker_id: worker_id, exception: error)
							@allocator.free(worker_id)
						end
					end
				end
				
				# Remove a worker from the utilization monitor.
				#
				# Returns the allocated segment back to the free list.
				#
				# @parameter supervisor_controller [SupervisorController] The supervisor controller for the worker.
				def remove(supervisor_controller)
					@guard.synchronize do
						worker_id = supervisor_controller.id
						return unless worker_id
						
						@workers.delete(worker_id)
						@allocator.free(worker_id)
						
						Console.debug(self, "Freed utilization segment", worker_id: worker_id)
					end
				end
				
				# The key used when this monitor's status is aggregated with others.
				def self.monitor_type
					:utilization_monitor
				end
				
				# Sample aggregated utilization data.
				#
				# @returns [Hash] Hash mapping service names to aggregated utilization metrics.
				def sample
					aggregated = {}
					
					sample_by_worker.each_value do |worker|
						service_name = worker[:state][:name] || "unknown"
						
						data = worker[:utilization]
						
						# Initialize service aggregation if needed
						aggregated[service_name] ||= {}
						
						# Sum up all numeric fields
						data.each do |key, value|
							if value.is_a?(Numeric)
								aggregated[service_name][key] ||= 0
								aggregated[service_name][key] += value
							else
								# For non-numeric values, we could handle differently
								# For now, just store the last value
								aggregated[service_name][key] = value
							end
						end
						
						# Count workers per service (for utilization denominator)
						aggregated[service_name][:worker_count] = (aggregated[service_name][:worker_count] || 0) + 1
					end
					
					aggregated
				end
				
				# Sample utilization data for each registered worker.
				#
				# @returns [Hash] An immutable hash keyed by worker ID, with supervisor state and utilization values.
				def sample_by_worker
					@guard.synchronize do
						@workers.each_with_object({}) do |(worker_id, supervisor_controller), workers|
							if utilization = @allocator.read(worker_id)
								workers[worker_id] = {
									state: supervisor_controller.state.dup.freeze,
									utilization: utilization.freeze,
								}.freeze
							end
						end.freeze
					end
				end
				
				# Serialize utilization data for JSON.
				#
				# @returns [Hash] Hash mapping service names to aggregated utilization metrics.
				def as_json
					self.sample
				end
				
				# Emit the utilization metrics.
				#
				# @parameter status [Hash] The utilization metrics.
				def emit(metrics)
					Console.info(self, "Utilization:", metrics: metrics)
				end
				
				# Run one iteration of the utilization monitor.
				def run_once
					self.emit(self.as_json)
				end
			end
		end
	end
end
