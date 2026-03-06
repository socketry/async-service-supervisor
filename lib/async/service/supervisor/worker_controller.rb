# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/controller"
require "stringio"

module Async
	module Service
		module Supervisor
			# Controller for worker operations.
			#
			# Handles diagnostic operations like memory dumps, thread dumps, scheduler dumps, etc.
			class WorkerController < Async::Bus::Controller
				# Initialize the worker controller for the worker.
				def initialize(worker)
					@worker = worker
				end
				
				private def dump(path: nil, log: nil, buffer: true, &block)
					if path
						File.open(path, "w") do |file|
							yield file
						end
						
						return {path: path}
					elsif buffer
						buffer = StringIO.new
						yield buffer
						
						if log
							Console.info(self, log, data: buffer.string)
							return {}
						else
							return {data: buffer.string}
						end
					else
						raise ArgumentError, "Buffered output not supported!"
					end
				end
				
				# Dump the current fiber scheduler hierarchy.
				#
				# Generates a hierarchical view of all running fibers and their relationships.
				#
				# @parameter path [String] Optional file path to save the dump.
				# @parameter log [String] Optional log message to output.
				def scheduler_dump(path: nil, log: nil)
					dump(path: path, log: log) do |file|
						Fiber.scheduler.print_hierarchy(file)
					end
				end
				
				# Dump the entire object space to a file.
				#
				# This is a heavyweight operation that dumps all objects in the heap.
				#
				# @parameter path [String] Optional file path to save the dump.
				def memory_dump(path: nil)
					require "objspace"
					
					dump(path: path, buffer: false) do |file|
						ObjectSpace.dump_all(output: file)
					end
				end
				
				# Dump information about all running threads.
				#
				# Includes thread inspection and backtraces for debugging.
				#
				# @parameter path [String] Optional file path to save the dump.
				def thread_dump(path: nil)
					dump(path: path) do |file|
						Thread.list.each do |thread|
							file.puts(thread.inspect)
							file.puts(thread.backtrace)
						end
					end
				end
				
				# Start garbage collection profiling.
				#
				# Enables the GC profiler to track garbage collection performance.
				#
				# @returns [Hash] Confirmation that profiling started.
				def garbage_profile_start
					GC::Profiler.enable
					return {started: true}
				end
				
				# Stop garbage collection profiling and return results.
				#
				# Disables the GC profiler and returns collected profiling data.
				#
				# @parameter path [String] Optional file path to save the profile.
				def garbage_profile_stop(path: nil)
					dump(path: path) do |file|
						file.puts GC::Profiler.result
					end
				ensure
					GC::Profiler.disable
				end
				
				# Setup utilization observer for this worker.
				#
				# Called by the supervisor to inform the worker of the shared memory file path
				# and allocated offset. Uses the utilization schema from the worker if available.
				#
				# @parameter path [String] Path to the shared memory file that the worker should map.
				# @parameter size [Integer] Size of the shared memory region to map.
				# @parameter offset [Integer] Offset into the shared memory buffer allocated for this worker.
				# @returns [Array] Array of [key, type, offset] tuples describing the utilization schema.
				# 	Returns empty array if no utilization schema is configured.
				def setup_utilization_observer(path, size, offset)
					utilization_schema = @worker.utilization_schema
					return [] unless utilization_schema
					
					schema = Async::Utilization::Schema.build(utilization_schema)
					observer = Async::Utilization::Observer.open(schema, path, size, offset)
					@worker.utilization_registry.observer = observer
					
					# Pass the schema back to the supervisor so it can be used to aggregate the metrics:
					return observer.schema.to_a
				end
			end
		end
	end
end

