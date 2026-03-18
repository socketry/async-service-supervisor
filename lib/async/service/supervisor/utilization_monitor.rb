# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "set"

require_relative "loop"
require "async/utilization"

module Async
	module Service
		module Supervisor
			# Monitors worker utilization metrics aggregated by service name.
			#
			# Uses shared memory to efficiently collect utilization metrics from workers
			# and aggregates them by service name for monitoring and reporting.
			class UtilizationMonitor
				# Allocates and manages shared memory segments for worker utilization data.
				#
				# Manages a shared memory file that workers can write utilization metrics to.
				# Allocates segments to workers and maintains a free list for reuse.
				# Each process (supervisor and workers) maps the shared memory file independently.
				class SegmentAllocator
					# Initialize a new shared memory manager.
					#
					# Creates and maps the shared memory file. Workers will map the same file
					# independently using the provided path.
					#
					# @parameter path [String] Path to the shared memory file.
					# @parameter size [Integer] Total size of the shared memory buffer.
					# @parameter segment_size [Integer] Size of each allocation segment (default: 512 bytes).
					# @parameter growth_factor [Integer, Float] Factor to grow by when resizing (default: 2, doubles the size).
					#   Can be less than 2 or a floating point value; the result will be page-aligned to an integer.
					def initialize(path, size: IO::Buffer::PAGE_SIZE * 8, segment_size: 512, growth_factor: 2)
						@path = path
						@size = size
						@segment_size = segment_size
						@growth_factor = growth_factor
						
						File.unlink(path) rescue nil
						@file = File.open(path, "w+b")
						@file.truncate(size)
						# Supervisor maps the file for reading worker data
						@buffer = IO::Buffer.map(@file, size)
						
						# Track allocated segments: worker_id => {offset: Integer, schema: Array}
						@allocations = {}
						
						# Free list of segment offsets
						@free_list = []
						
						# Initialize free list with all segments
						(0...(@size / @segment_size)).each do |segment_index|
							@free_list << (segment_index * @segment_size)
						end
					end
					
					# Allocate a segment for a worker.
					#
					# Automatically resizes the shared memory file if no segments are available.
					#
					# @parameter worker_id [Integer] The ID of the worker.
					# @parameter schema [Array] Array of [key, type, offset] tuples describing the data layout.
					# @returns [Integer] The offset into the shared memory buffer, or nil if allocation fails.
					def allocate(worker_id, schema)
						# Try to resize if we're out of segments
						if @free_list.empty?
							unless resize(@size * @growth_factor)
								return nil
							end
						end
						
						offset = @free_list.shift
						@allocations[worker_id] = {offset: offset, schema: schema}
						
						return offset
					end
					
					# Free a segment allocated to a worker.
					#
					# @parameter worker_id [Integer] The ID of the worker.
					def free(worker_id)
						if allocation = @allocations.delete(worker_id)
							@free_list << allocation[:offset]
						end
					end
					
					# Get the allocation information for a worker.
					#
					# @parameter worker_id [Integer] The ID of the worker.
					# @returns [Hash] Allocation info with :offset and :schema, or nil if not allocated.
					def allocation(worker_id)
						@allocations[worker_id]
					end
					
					# Get the current size of the shared memory file.
					#
					# @returns [Integer] The current size of the shared memory file.
					def size
						@size
					end
					
					# Update the schema for an existing allocation.
					#
					# @parameter worker_id [Integer] The ID of the worker.
					# @parameter schema [Array] Array of [key, type, offset] tuples describing the data layout.
					def update_schema(worker_id, schema)
						if allocation = @allocations[worker_id]
							allocation[:schema] = schema
						end
					end
					
					# Read utilization data from a worker's allocated segment.
					#
					# @parameter worker_id [Integer] The ID of the worker.
					# @returns [Hash] Hash mapping keys to their values, or nil if not allocated.
					def read(worker_id)
						allocation = @allocations[worker_id]
						return nil unless allocation
						
						offset = allocation[:offset]
						schema = allocation[:schema]
						
						result = {}
						schema.each do |key, type, field_offset|
							absolute_offset = offset + field_offset
							
							# Use IO::Buffer type symbols directly (i32, u32, i64, u64, f32, f64)
							# IO::Buffer accepts both lowercase and uppercase versions
							begin
								result[key] = @buffer.get_value(type, absolute_offset)
							rescue => error
								Console.warn(self, "Failed to read value", type: type, key: key, offset: absolute_offset, exception: error)
							end
						end
						
						return result
					end
					
					# Resize the shared memory file.
					#
					# Extends the file to the new size, remaps the buffer, and adds new segments
					# to the free list. The new size must be larger than the current size and should
					# be page-aligned for optimal performance.
					#
					# @parameter new_size [Integer] The new size for the shared memory file.
					# @returns [Boolean] True if resize was successful, false otherwise.
					def resize(new_size)
						old_size = @size
						return false if new_size <= old_size
						
						# Ensure new size is page-aligned (rounds up to nearest page boundary)
						page_size = IO::Buffer::PAGE_SIZE
						new_size = (((new_size + page_size - 1) / page_size) * page_size).to_i
						
						begin
							# Extend the file:
							@file.truncate(new_size)
							
							# Remap the buffer to the new size:
							@buffer&.free
							@buffer = IO::Buffer.map(@file, new_size)
							
							# Calculate new segments to add to free list:
							old_segment_count = old_size / @segment_size
							new_segment_count = new_size / @segment_size
							
							# Add new segments to free list:
							(old_segment_count...new_segment_count).each do |segment_index|
								@free_list << (segment_index * @segment_size)
							end
							
							@size = new_size
							
							Console.info(self, "Resized shared memory", old_size: old_size, new_size: new_size, segments_added: new_segment_count - old_segment_count)
							
							return true
						rescue => error
							Console.error(self, "Failed to resize shared memory", old_size: old_size, new_size: new_size, exception: error)
							return false
						end
					end
					
					# Close the shared memory file.
					def close
						@file&.close
						@buffer = nil
					end
				end
				# Initialize a new utilization monitor.
				#
				# @parameter path [String] Path to the shared memory file.
				# @parameter interval [Integer] Interval in seconds to aggregate and update metrics.
				# @parameter size [Integer] Total size of the shared memory buffer.
				# @parameter segment_size [Integer] Size of each allocation segment (default: 512 bytes).
				def initialize(path: "utilization.shm", interval: 10, size: IO::Buffer::PAGE_SIZE * 8, segment_size: 512)
					@path = path
					@interval = interval
					@segment_size = segment_size
					
					@allocator = SegmentAllocator.new(path, size: size, segment_size: segment_size)
					
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
				
				# Serialize utilization data for JSON.
				#
				# @returns [Hash] Hash mapping service names to aggregated utilization metrics.
				def as_json
					@guard.synchronize do
						aggregated = {}
						
						@workers.each do |worker_id, supervisor_controller|
							service_name = supervisor_controller.state[:name] || "unknown"
							
							data = @allocator.read(worker_id)
							next unless data
							
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
					{type: self.class.monitor_type, data: as_json}
				end
				
				# Emit the utilization metrics.
				#
				# @parameter status [Hash] The utilization metrics.
				def emit(metrics)
					Console.info(self, "Utilization:", metrics: metrics)
				end
				
				# Run the utilization monitor.
				#
				# Periodically aggregates utilization data from all workers.
				#
				# @returns [Async::Task] The task that is running the utilization monitor.
				def run
					Async do
						Loop.run(interval: @interval) do
							self.emit(self.as_json)
						end
					end
				end
			end
		end
	end
end
